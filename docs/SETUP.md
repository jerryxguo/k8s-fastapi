# Setting this up from scratch

End-to-end order for standing up all three environments and the pipeline.
Every step says how to check it worked, because most failures here surface
somewhere other than where they were caused.

## 0. Prerequisites

| Tool | Why | Note |
|---|---|---|
| Terraform **>= 1.10** | backends use the S3 `use_lockfile` argument | 1.7-1.9 fail at `init` with `Unsupported argument` |
| AWS CLI v2 | Terraform's `exec` auth for the kubernetes/helm providers, and bucket bootstrap | |
| `kubectl` | inspecting the cluster | |
| Helm | `make helm-lint` locally | CI installs its own |
| Docker | `make build` / `make run` | not needed for `terraform apply` |
| Pants launcher | everything under `make` | self-bootstraps the version `pants.toml` pins |

Named AWS profiles must exist for each account. The defaults are
`shared-full`, `dev-full`, `prod-full`; override with `-var profile=...` if
yours are named differently. Confirm each resolves to the account you expect:

```bash
for p in shared-full dev-full prod-full; do aws sts get-caller-identity --profile "$p" --query Account --output text; done
```

## 1. Create the Terraform state buckets

One bucket per **account**, named `k8s-demo-tfstate-<account-id>`. Terraform
cannot create the backend it is configured to use, so this is out of band.
Environments in the same account share a bucket; each `backend.tf` names the
bucket for the account that environment runs in.

```bash
ACCOUNT=<account-id>; PROFILE=<profile>; REGION=ap-southeast-2
aws s3api create-bucket --bucket "k8s-demo-tfstate-${ACCOUNT}" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" --profile "$PROFILE"
aws s3api put-bucket-versioning --bucket "k8s-demo-tfstate-${ACCOUNT}" \
  --versioning-configuration Status=Enabled --profile "$PROFILE"
aws s3api put-public-access-block --bucket "k8s-demo-tfstate-${ACCOUNT}" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "$PROFILE"
```

Repeat per account. If the bucket name in `live/<env>/backend.tf` does not
match the account that env's profile authenticates to, `init` fails with a
`403`, not a helpful message.

**Check:** `aws s3api head-bucket --bucket k8s-demo-tfstate-<id> --profile <profile>`
returns without error.

## 2. Fill in tfvars

Copy each `terraform.tfvars.example` to `terraform.tfvars` (gitignored) and set:

| Environment | Required |
|---|---|
| `shared` | `github_org`, `dev_account_id`, `prod_account_id` |
| `dev` | `github_org`, `admin_principal_arn`, `shared_account_id` |
| `prod` | `github_org`, `admin_principal_arn`, `shared_account_id` |

`admin_principal_arn` must be a **real, assumable principal in that same
account** — the identity that runs `terraform apply`. A wrong value is not
rejected at apply; it creates an EKS access entry nobody can use, and fixing
it later shows up as a destroy-and-recreate of the entry granting your own
admin access.

If this is not `jerryxguo/k8s-fastapi`, also override `github_repo`,
`github_owner_id` and `github_repository_id` in each env. GitHub bakes
immutable numeric IDs into the OIDC subject for newer repos, and a mismatch
fails only in CI, with a generic `Not authorized`:

```bash
gh api repos/<owner>/<repo> --jq '.owner.id, .id'
```

## 3. Apply `shared` first

```bash
cd infra/terraform/live/shared && terraform init && terraform apply
```

Order matters: `shared` creates the account's GitHub OIDC provider, and `dev`
defaults to `create_oidc_provider = false` and reuses it (there can be only
one per account). `prod` is a different account, so it creates its own.

**Check:** `terraform output ecr_repository_url` and `cicd_role_arn`.

## 4. Apply `dev`, then `prod`

```bash
cd infra/terraform/live/dev  && terraform init && terraform apply
cd infra/terraform/live/prod && terraform init && terraform apply
```

Each builds a VPC, EKS cluster and node group, the IRSA roles, and installs
the cluster-wide add-ons (External Secrets Operator, AWS Load Balancer
Controller, the `ClusterSecretStore`) plus the app namespace. There is **no
post-apply step and no two-pass bootstrap** — a single `apply` is enough.

Expect 15-20 minutes for the EKS cluster.

**Check:**

```bash
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region ap-southeast-2 --profile <profile>
kubectl get ns k8s-demo
kubectl get clustersecretstore aws-secretsmanager
kubectl -n kube-system get deploy aws-load-balancer-controller
```

## 5. Populate the application secret

Terraform creates `<name_prefix>/app-config` with an empty `{}` placeholder
and `ignore_changes` on its value, so real content is never overwritten by a
later apply. Put real values in out of band:

```bash
aws secretsmanager put-secret-value --secret-id k8s-demo-dev/app-config \
  --secret-string '{"EXAMPLE_KEY":"value"}' --profile dev-full
```

Keys become environment variables on the pod. The app tolerates missing keys
via pydantic defaults, so an empty secret is fine to start.

## 6. Create the GitHub Environments

Three Environments under **Settings -> Environments**: `development`,
`production`, `shared`. The names must match what the IAM trust policies
expect — the OIDC subject is `...:environment:<name>`, so a typo fails as a
generic `Not authorized`.

Set these as **variables** (not secrets — none of them are sensitive, and an
unset secret renders as an omitted log line, which is harder to debug):

| Variable | `shared` | `development` | `production` | Value |
|---|:--:|:--:|:--:|---|
| `AWS_ROLE_ARN` | yes | yes | yes | that env's `cicd_role_arn` output |
| `AWS_REGION` | yes | yes | yes | e.g. `ap-southeast-2` |
| `ECR_REPOSITORY` | yes | - | - | `shared`'s `ecr_repository_url` output |
| `EKS_CLUSTER_NAME` | - | yes | yes | that env's `cluster_name` output |
| `APP_IRSA_ROLE_ARN` | - | yes | yes | that env's `app_irsa_role_arn` output |
| `ENVIRONMENT_SHORT` | - | `dev` | `prod` | selects `values-<short>.yaml` |
| `APP_NAMESPACE` | - | optional | optional | defaults to `k8s-demo` |
| `APP_CERTIFICATE_ARN` | - | optional | optional | ACM cert ARN; unset means plain HTTP |

The deploy job checks these up front and fails naming the missing one, so a
mistake here is cheap to diagnose.

## 7. Protection rules

- **`production`**: add a required reviewer under Deployment protection rules.
  This is the only production gate; a job with `environment: production` does
  **not** pause for approval on its own.
- **`development`**: set "Deployment branches and tags" to allow the branches
  you want deployable. Protected-branches-only blocks
  `manual-deploy-development` for feature branches.

## 8. First deploy

Open a PR (runs checks, builds, deploys to `development`, smoke-tests), or use
**Actions -> manual-deploy-development -> Run workflow** and pick a branch.
Merging to `main` promotes the same image through `development -> production`.

## 9. Local development

```bash
make lock   # only when src/requirements.txt changes; commit the result
make test
make lint
make build  # cross-builds for linux/x86_64
make run    # then: curl localhost:8080/healthcheck
```

## Tearing it down

Order matters more than it looks, and two steps fail confusingly if skipped.

**1. Delete the app release first, while the ALB controller is still running.**
The controller is what deletes the ALB. Destroy the cluster first and it dies
with the cluster, leaving the ALB and its security groups orphaned, and the VPC
destroy then fails with `DependencyViolation` on the leftover ENIs.

```bash
helm uninstall k8s-demo-service -n k8s-demo    # per environment
aws elbv2 describe-load-balancers --profile <p> --region ap-southeast-2 \
  --query 'LoadBalancers[].LoadBalancerName'   # wait until empty
```

**2. Set `secret_recovery_window_days = 0` before destroying, if you intend to
re-apply.** Secrets Manager soft-deletes: the name stays reserved for the
recovery window, and re-creating it fails with "already scheduled for
deletion". `dev` already defaults to 0; `prod` defaults to 30. Apply the change
first, then destroy. To recover from having skipped it:

```bash
aws secretsmanager restore-secret --secret-id <name> --profile <p>
aws secretsmanager delete-secret --secret-id <name> --force-delete-without-recovery --profile <p>
```

**3. Destroy `dev` and `prod`, then `shared` last.** `shared` owns the ECR repo
and the account's GitHub OIDC provider that `dev`'s IAM role trusts.

**4. Empty ECR before destroying `shared`.** `modules/ecr-repo` sets no
`force_delete`, so a non-empty repository refuses to delete:

```bash
aws ecr batch-delete-image --repository-name k8s-demo-shared/service-api \
  --region ap-southeast-2 --profile shared-full \
  --image-ids "$(aws ecr list-images --repository-name k8s-demo-shared/service-api \
    --region ap-southeast-2 --profile shared-full --query imageIds --output json)"
```

If a destroy wedges because the cluster is already unreachable, drop the
in-cluster resources from state rather than fighting it:

```bash
terraform state rm helm_release.cluster_secret_store helm_release.external_secrets \
  helm_release.aws_load_balancer_controller \
  kubernetes_namespace_v1.app kubernetes_namespace_v1.hyperion
```

**Not removed by `destroy`:** the state buckets (not Terraform-managed, and
versioned, so emptying them means deleting every object *version*), the EKS
KMS keys (scheduled for deletion on a 7-30 day window, not deleted), and the
control-plane CloudWatch log groups.

**After re-applying, refresh your kubeconfig.** `update-kubeconfig` keys the
context by cluster ARN, which is identical across a destroy/recreate, so a
rebuilt cluster silently inherits the old endpoint and `kubectl` fails with a
DNS error that reads like a network problem:

```bash
aws eks update-kubeconfig --name <cluster> --region ap-southeast-2 --profile <p>
```

## Known gaps

- **TLS is not set up.** No ACM certificate is provisioned; both environments
  serve plain HTTP on `:80`. Set `APP_CERTIFICATE_ARN` once you own a real
  domain and the chart switches to HTTPS with a redirect.
- **Node autoscaling is not set up.** The HPA scales pods; nothing scales
  nodes. Node counts change only when `node_desired_size` does.
- The `*.example.com` hosts in `values-dev.yaml`/`values-prod.yaml` are
  placeholders and need replacing with real DNS.
