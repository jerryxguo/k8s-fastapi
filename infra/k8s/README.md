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

There is nothing left for a human to run by hand for these in steady state
-- **except one known rough edge on a genuinely fresh cluster's first
bootstrap**: `kubernetes_manifest.cluster_secret_store` validates its
manifest against the target CRD's schema at *plan* time, and the External
Secrets Operator's CRDs don't exist yet on a brand new cluster (even though
the same apply is what's about to install them via
`helm_release.external_secrets`).

Re-running plain `terraform apply` does **not** fix this on its own, and
will just fail the same way forever. Terraform computes the full plan for
every resource before applying anything; if any one resource's plan
errors, the whole apply aborts before creating *anything* -- including
`helm_release.external_secrets`, which is what would install the CRD in
the first place. The fix is to force a first pass that installs the CRDs
without ever planning the resource that needs them, then apply normally:

```bash
terraform apply -target=helm_release.external_secrets
terraform apply
```

`-target` only pulls in a resource's dependencies (here, `module.eks` and
`module.external_secrets_irsa`), never things that depend on it -- so
`cluster_secret_store` is excluded from that first plan entirely and can't
block it. The second, untargeted apply then succeeds (the CRDs now exist)
and also picks up everything else still pending from earlier failed
attempts. This is only needed once per fresh cluster; every apply after
that is unaffected.

## Then deploy the app

```bash
aws eks update-kubeconfig --name <cluster_name> --region <region>
helm upgrade --install k8s-demo-service infra/k8s/helm/fastapi-service \
  --namespace k8s-demo --create-namespace \
  -f infra/k8s/helm/fastapi-service/values.yaml \
  -f infra/k8s/helm/fastapi-service/values-dev.yaml \
  --set image.repository=<ecr_repository_url output> \
  --set image.tag=<a real tag> \
  --set serviceAccount.roleArn=<app_irsa_role_arn output>
```

(`--create-namespace` is left in as a harmless fallback -- it only attempts
creation if the namespace is missing, which it won't be once the Terraform
apply above has run. The namespace isn't templated in the Helm chart itself,
see `helm/fastapi-service/templates/namespace.yaml` -- namespace
create/update is a cluster-scoped action the CI/CD role's intentionally
narrow IAM policy, `AmazonEKSEditPolicy`, can't perform.)

This is exactly what `.github/workflows/reusable-deploy.yml` automates in
CI once the GitHub Environment variables described in the top-level
`README.md` are set.
