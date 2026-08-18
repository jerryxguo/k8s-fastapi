# Architecture

```
                       ┌─────────────────────────────────────────────────────┐
                       │                  GitHub (your-org/K8s)               │
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
- **`infra/terraform/`** -- everything that exists at the AWS-account level,
  split across three environments: `dev` and `prod` each get a VPC, EKS
  cluster + node group, IAM (CI/CD OIDC role, IRSA roles), and one
  placeholder Secrets Manager secret; `shared` gets only the ECR repo and a
  push-only CI/CD OIDC role -- no VPC, no EKS, no app. Terraform never
  touches anything *inside* a cluster.
- **`infra/k8s/helm/fastapi-service/`** -- everything that runs *inside*
  the cluster for this one service: Deployment, Service, Ingress, HPA,
  ServiceAccount, ConfigMap, ExternalSecret. Deployed by `helm upgrade
  --install` from CI, never by Terraform. Nothing is deployed into `shared`
  -- it has no cluster to deploy to.
- **`.github/`** -- the pipeline gluing the two together: build once (in
  the `shared` GitHub Environment, since that's the account that owns the
  ECR repo), then deploy the identical image to development and production
  in order, each behind its own GitHub Environment (approval rules +
  environment-scoped `AWS_ROLE_ARN` secret).

## Cluster add-ons this chart assumes are already installed

Two pieces of cluster-wide infrastructure are referenced by the Helm chart
(the Ingress's `alb.ingress.kubernetes.io/*` annotations, and the
`ExternalSecret`'s `ClusterSecretStore`) but are **not** created by this
chart or by Terraform, because they're cluster-wide add-ons shared by every
workload, not something one service's chart should own:

1. **AWS Load Balancer Controller** -- watches `Ingress` resources with
   `ingressClassName: alb` and provisions/updates the actual ALB.
2. **External Secrets Operator** -- watches `ExternalSecret` resources and
   syncs the referenced Secrets Manager secret into a real Kubernetes
   `Secret`.

See `infra/k8s/README.md` for how to install both (one-time, per cluster)
using the `external_secrets_irsa_role_arn` Terraform output.
