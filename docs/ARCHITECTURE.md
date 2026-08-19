# Architecture

```
                       ┌─────────────────────────────────────────────────────┐
                       │           GitHub (jerryxguo/k8s-fastapi)            │
                       │  pull-request.yml / release.yml                     │
                       │  → code-check, unit-test (every PR)                 │
                       │  → build (docker build, push to ECR) [shared account]│
                       │  → deploy: development → production                 │
                       │    (each an OIDC role-assume into that account)     │
                       └──────────────┬──────────────────────┬───────────────┘
                                      │ GitHub OIDC           │ GitHub OIDC
                                      │ (shared's role,       │ (per-env IAM role,
                                      │  push-only)            │  permission-boundary
                                      │                        │  scoped)
                       ┌──────────────▼───────────────┐  ┌────▼────────────────────┐
                       │   AWS account: shared          │  │  AWS account (×2:        │
                       │                                 │  │  dev / prod)             │
                       │  No VPC, no EKS, no app --      │  │                          │
                       │  this account exists only to    │  │  ┌─────────────────────┐ │
                       │  own the registry.               │  │  │ VPC (terraform-aws- │ │
                       │                                  │  │  │ modules/vpc/aws)    │ │
                       │  ECR: k8s-demo-shared/service-api │  │  │ public + private     │ │
                       │  (cross-account pull granted to   │  │  │ subnets, tagged for  │ │
                       │   dev + prod account IDs)          │  │  │ ALB/EKS              │ │
                       └────────────────────────────────┘  │  │                      │ │
                                                            │  │  ┌────────────────┐  │ │
                                                            │  │  │ EKS cluster     │  │ │
                                                            │  │  │ (terraform-aws- │  │ │
                                                            │  │  │ modules/eks/aws)│  │ │
                                                            │  │  │ + managed node  │  │ │
                                                            │  │  │ group + OIDC    │  │ │
                                                            │  │  │ provider (IRSA) │  │ │
                                                            │  │  │                 │  │ │
                                                            │  │  │ Deployment (Helm)│ │ │
                                                            │  │  │  ├─ ServiceAccount│ │ │
                                                            │  │  │  │  (IRSA →      │  │ │
                                                            │  │  │  │   app_irsa)   │  │ │
                                                            │  │  │  ├─ ConfigMap    │  │ │
                                                            │  │  │  ├─ ExternalSecret│ │ │
                                                            │  │  │  │  → Secrets Mgr│  │ │
                                                            │  │  │  ├─ Service       │  │ │
                                                            │  │  │  │  (ClusterIP)   │  │ │
                                                            │  │  │  ├─ Ingress       │  │ │
                                                            │  │  │  │  (ALB, internal)│ │ │
                                                            │  │  │  └─ HPA (CPU 70%) │  │ │
                                                            │  │  └────────────────┘  │ │
                                                            │  └─────────────────────┘ │
                                                            └──────────────────────────┘
```

## Component ownership

- **`src/app/`** -- the FastAPI service itself. No AWS SDK calls; reads
  configuration purely from environment variables (populated by a
  ConfigMap + a Secret synced from Secrets Manager).
- **`infra/terraform/`** -- the AWS-account level, plus cluster *bootstrap*.
  `dev` and `prod` each get a VPC, EKS cluster + node group, IAM (CI/CD OIDC
  role, IRSA roles), and one placeholder Secrets Manager secret; `shared`
  gets only the ECR repo and a push-only CI/CD OIDC role -- no VPC, no EKS,
  no app. Terraform also creates a small number of *cluster-wide* objects,
  because they are shared by every workload rather than owned by one
  service's chart: the app and hyperion namespaces, the External Secrets
  Operator, the AWS Load Balancer Controller, and the `ClusterSecretStore`
  (via `infra/k8s/helm/cluster-secret-store`). The dividing line is
  cluster-wide versus per-service, not Terraform versus Helm -- Terraform
  uses Helm for two of those four.
- **`infra/k8s/helm/fastapi-service/`** -- everything that runs *inside* the
  cluster for this one service: Deployment, Service, Ingress, HPA,
  PodDisruptionBudget, ServiceAccount, ConfigMap, ExternalSecret. Deployed by
  `helm upgrade --install` from CI, never by Terraform. Nothing is deployed
  into `shared` -- it has no cluster to deploy to.
- **`.github/`** -- the pipeline gluing the two together: build once (in
  the `shared` GitHub Environment, since that's the account that owns the
  ECR repo), then deploy the identical image to development and production
  in order, each behind its own GitHub Environment (approval rules +
  environment-scoped `AWS_ROLE_ARN` secret).

## Cluster add-ons the app chart depends on (installed by Terraform)

Two pieces of cluster-wide infrastructure are referenced by the app chart
(the Ingress's `alb.ingress.kubernetes.io/*` annotations, and the
`ExternalSecret`'s `ClusterSecretStore`). They are **not** created by that
chart, because they are shared by every workload rather than owned by one
service -- but they are created, by Terraform, in the same `apply` that
builds the cluster (`helm_release` resources in `live/<env>/main.tf`). There
is no manual post-apply installation step:

1. **AWS Load Balancer Controller** -- watches this service's `Ingress`
   and provisions/updates the actual ALB. The chart selects it via
   `spec.ingressClassName: alb`, which resolves to the `IngressClass` the
   controller's own chart creates (`createIngressClassResource` and
   `ingressClass` default to `true`/`alb`). The listener set follows
   `ingress.certificateArn`: unset (the default, and the case for both
   environments today, whose hosts are `*.example.com` placeholders) gives
   a plain HTTP listener on :80; set to a real ACM certificate ARN gives
   HTTP + HTTPS with an HTTP->HTTPS redirect. Terraform does not provision
   an ACM certificate, so that ARN is supplied per environment once a real
   domain exists.
2. **External Secrets Operator** -- watches `ExternalSecret` resources and
   syncs the referenced Secrets Manager secret into a real Kubernetes
   `Secret`.

Both are installed by Terraform, wired to their own IRSA roles
(`external_secrets_irsa_role_arn`, and the ALB controller's role) via the
service-account annotation each chart sets at install time. See
`infra/k8s/README.md` for the detail.
