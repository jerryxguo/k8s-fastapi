# Cluster bootstrap

This used to be a set of manual `kubectl`/`helm` steps run once per cluster
before the first deploy. It's now fully Terraform-managed: `terraform apply`
in `live/<env>` creates the app's namespace, installs the External Secrets
Operator and its `ClusterSecretStore`, and installs the AWS Load Balancer
Controller -- all via the `kubernetes` and `helm` providers configured in
`live/<env>/versions.tf`, authenticated as whatever principal is running
`terraform apply` (the same one already granted cluster-admin via the EKS
access entry). See the "Cluster bootstrap, Terraform-managed" section in
`live/<env>/main.tf` for the actual resources.

There is nothing left for a human to run by hand, and no bootstrap
two-pass either. `terraform apply` is one-shot on a genuinely fresh
environment.

That used not to be the case. The `ClusterSecretStore` was created with
`kubernetes_manifest`, which contacts the API server during *plan* to resolve
the manifest's group-version against the live CRD set. On a fresh environment
the cluster does not exist when the first plan runs, so that lookup fails, and
a plan error aborts the whole apply before creating anything -- including the
`helm_release` that installs the CRD. `depends_on` orders apply, not plan, so
re-running plain `terraform apply` reproduced it indefinitely. The workaround
was a documented two-pass bootstrap per cluster:

```bash
terraform apply -target=helm_release.external_secrets   # no longer needed
terraform apply
```

The store is now delivered by `helm_release.cluster_secret_store` over the
small local chart in `helm/cluster-secret-store/`. `helm_release` performs no
API lookup at plan time, so its plan succeeds against a cluster that does not
exist yet and `depends_on` alone is sufficient to order the apply after the
CRDs exist.

## Then deploy the app

```bash
aws eks update-kubeconfig --name <cluster_name> --region <region>
helm upgrade --install k8s-demo-service infra/k8s/helm/fastapi-service \
  --namespace k8s-demo \
  -f infra/k8s/helm/fastapi-service/values.yaml \
  -f infra/k8s/helm/fastapi-service/values-dev.yaml \
  --set image.repository=<ecr_repository_url output> \
  --set image.tag=<a real tag> \
  --set serviceAccount.roleArn=<app_irsa_role_arn output>
```

No `--create-namespace` here -- it's deliberately **not** used, though not
for a permissions reason anymore (the CI/CD role now runs as cluster-admin,
see below). `--create-namespace` doesn't do a "check first, only create if
missing" dance from the API server's point of view: Helm issues an
unconditional `create` call, and Kubernetes authorizes the verb against the
role's RBAC grants *before* it ever checks whether the object already
exists. This used to matter a lot here: when CI/CD was scoped to
`AmazonEKSEditPolicy`, that `create` call was always forbidden regardless of
whether the namespace already existed -- confirmed against a real cluster
where the namespace had existed for 15+ minutes and the deploy still failed
with "cannot create resource \"namespaces\" ... at the cluster scope".
CI/CD's access entry has since moved to `AmazonEKSClusterAdminPolicy` (see
`modules/eks-cluster/main.tf` and cicd-gotchas.md in the k8s-fastapi-design
skill for why), so that specific failure mode is gone -- but the flag is
still left out, now simply because Terraform already guarantees the
namespace exists (`kubernetes_namespace_v1.app` in `live/<env>/main.tf`)
before any deploy ever runs, and having two systems both try to own the
same namespace object is worth avoiding on its own. The namespace isn't
templated in the Helm chart itself either, see
`helm/fastapi-service/templates/namespace.yaml`.

This is exactly what `.github/workflows/reusable-deploy.yml` automates in
CI once the GitHub Environment variables described in the top-level
`README.md` are set.
