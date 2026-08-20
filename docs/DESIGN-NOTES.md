# Design notes

This project is an example service demonstrating a self-contained pattern
for running a FastAPI service on AWS EKS with Terraform, Helm, and GitHub
Actions. This document records the key design decisions and why they were
made, plus what you'd need to change to adapt this into a real service.

## Design decisions

- **Terraform, not a proprietary stack-management tool.** Compute
  infrastructure (VPC, EKS cluster, node group) is provisioned with the
  audited `terraform-aws-modules/vpc/aws` and `terraform-aws-modules/eks/aws`
  registry modules; the smaller pieces (ECR repo, GitHub OIDC CI/CD role,
  IRSA roles) are hand-written modules owned outright by this repo. Using
  well-audited public registry modules for the VPC/cluster is standard
  Terraform practice and far less error-prone than hand-rolling that wiring.
- **GitHub OIDC → per-environment, permission-boundary-scoped IAM role.**
  Each environment (dev/prod/shared) gets its own IAM role, trusted only
  for that GitHub Environment, with a permission boundary that restricts it
  to resources named `${name_prefix}*`. This caps the blast radius of a
  compromised or misconfigured CI/CD credential.
- **IRSA (IAM Roles for Service Accounts) instead of node-level or
  instance-profile credentials.** Every workload identity (the app itself,
  the External Secrets Operator) gets its own narrowly-scoped IAM role,
  federated through the cluster's OIDC provider to a specific Kubernetes
  ServiceAccount -- not a broad role shared by every pod on a node.
- **Autoscaling by default.** The Helm chart enables a
  `HorizontalPodAutoscaler` (`infra/k8s/helm/fastapi-service/templates/hpa.yaml`)
  out of the box, since a static replica count is a common gap in simple
  container deployments and is easy to get wrong by omission. An HPA is inert
  without a metrics source, so Terraform installs the `metrics-server` EKS
  add-on and opens the node security group on :10251 for it -- both are
  required, and the manifest looks correct without either. Note the target is
  70% of the container's CPU *requests*, not of the node, and CPU is a weak
  signal for an async I/O-bound app: it may saturate on concurrency long
  before CPU reaches the threshold. Pod autoscaling only; nothing scales
  nodes (no Cluster Autoscaler or Karpenter).
- **Secrets via AWS Secrets Manager + External Secrets Operator, not an
  app-level AWS SDK client.** `src/app/settings.py` is a plain
  `pydantic-settings` reader with zero AWS SDK calls -- secret sync happens
  out-of-band via the External Secrets Operator, so the application code
  itself has no AWS-specific dependencies at all.
- **Everything CI/CD needs lives in this repository.** Every composite
  action and reusable workflow (`bootstrap-pants`, `generate-build-version`,
  `reusable-build-and-push.yml`, `reusable-deploy.yml`,
  `reusable-smoke-test.yml`) is defined locally and referenced by relative
  path, not pulled from another repository's `@main`/`@master` ref. That
  means no floating-tag risk and nothing to break if some other repo
  changes.
- **In-cluster smoke test rather than an external Postman/Newman run.**
  `reusable-smoke-test.yml` hits the ClusterIP Service directly via
  `kubectl run`, so there's no need for a runner with network access to an
  internal load balancer. Swap in a real contract-test suite the same way
  if the app grows real endpoints worth testing that way.
- **Promotion order: development → production**, each gated by its own
  GitHub Environment (approval rules + environment-scoped secrets),
  smoke-tested after every deploy so a failing environment blocks the next
  one.

## Build tooling: Pants

This project builds with [Pants](https://www.pantsbuild.org/) rather than a
plain `pip install` + hand-written `Dockerfile`. Pants gives a Python service
like this one a few things a plain venv + Makefile setup doesn't: a
reproducible, hash-locked dependency resolve (`src/requirements.lock`),
fine-grained BUILD-file-based dependency graph (so `pants lint`/`test`/
`package` only touch what actually changed), and a `pex_binary` +
`docker_image` packaging model instead of re-running `pip install` inside the
`Dockerfile` on every build. Concretely:

- **One resolve.** `[python.resolves]` in `pants.toml` defines a single
  `k8s_python_default` resolve backed by `src/requirements.txt` /
  `src/requirements.lock`, covering runtime, test, and lint/typecheck
  dependencies together -- this project has no second, incompatible
  dependency set that would need its own resolve.
- **Public PyPI only.** `pants.toml` has no `[python-repos]` section, since
  this project only depends on public PyPI packages and Pants' default index
  is already PyPI.
- **`pex_binary` + `docker_image`, not `pip install` in the `Dockerfile`.**
  `src/app/BUILD` defines a `pex_binary` (a single self-contained executable
  Python file bundling the app + its locked dependencies) and a
  `docker_image` that packages it. `src/app/Dockerfile` copies in the
  already-built PEX (`COPY src.app/app.pex /app.pex`) and converts it to a
  venv layout for faster container startup (`PEX_TOOLS=1 ... venv
  --compile`). `docker build` is never run by hand against this Dockerfile;
  always go through `pants package src/app:docker` (wired up as `make
  build`).
- **Non-root container user.** The final image stage still creates and
  switches to an unprivileged `appuser`, consistent with this project's other
  deliberate hardening choices (see the autoscaling bullet above).
- **CI installs Pants via `pantsbuild/actions/init-pants`,** Pants' own
  official GitHub Action (see `.github/actions/bootstrap-pants`), which also
  restores Pants' named-cache and LMDB process-cache GitHub Actions caches so
  repeat CI runs don't redo unchanged work.
- **The lockfile is not fabricated, and it's committed.** `src/requirements.lock`
  is generated by Pants itself (`pants generate-lockfiles`, wired up as
  `make lock`) and encodes per-platform wheel hashes -- it can only be
  produced by an actual Pants binary. It is present and committed. CI has
  no step that generates it, so `pants lint`/`test`/`package` all fail
  outright if it is ever missing -- regenerate and recommit it with `make
  lock` whenever `src/requirements.txt` changes.

## ECR strategy (read this before you `terraform apply`)

There's exactly one ECR repository, `k8s-demo-shared/service-api`, owned by
a **dedicated `shared` AWS account** (`infra/terraform/live/shared`) that
exists for exactly this purpose -- it has no VPC, no EKS cluster, and no
app running in it, just the ECR repo and the one GitHub OIDC role allowed
to push to it. `shared`'s `ecr-repo` module grants cross-account pull to
both `dev_account_id` and `prod_account_id`. That's what makes "the same
image is promoted unchanged through every environment" actually true.

Neither `dev` nor `prod`'s Terraform creates an ECR repository at all --
each references the shared account's repo ARN directly
(`local.ecr_repository_arn`, built from its own `shared_account_id`
tfvar), and each one's CI/CD role is created with `grant_ecr_push = false`.
Only the `shared` GitHub Environment's CI/CD role can push;
`development`/`production` can only `eks:DescribeCluster` + deploy.

This is a deliberate choice over the simpler alternative of just having
`dev` own the shared repo (dev's own AWS account, no extra account to
provision): a dedicated `shared` account means losing dev doesn't take the
registry down with it, and no environment that also runs a real workload
doubles as the thing every other environment's deploy depends on. If you'd
rather fold `shared` back into `dev` to avoid provisioning a fourth AWS
account, move the `ecr` module and `grant_ecr_push = true` into
`live/dev/main.tf` and point `prod`'s `shared_account_id` at dev's account
ID instead.

## Things you must fill in before this is real (not generic placeholders)

- `admin_principal_arn` in `live/dev/terraform.tfvars` and
  `live/prod/terraform.tfvars` (`shared` has no EKS cluster, so it has no
  `admin_principal_arn`). Each environment ships a `terraform.tfvars.example`
  to copy; `*.tfvars` is gitignored.
- `shared_account_id` in both `live/dev/terraform.tfvars` and
  `live/prod/terraform.tfvars`, and `dev_account_id`/`prod_account_id` in
  `live/shared/terraform.tfvars`.
- `github_org`/`github_repo`. At each `live/<env>` root, `github_org` is
  required with no default and `github_repo` defaults to `k8s-fastapi`.
  `modules/github-oidc-cicd-role` requires both with no defaults at all, so
  a root that forgets to pass one through fails at `plan` with "Missing
  required argument" rather than silently building an OIDC trust condition
  nobody's token can match. Point these at your actual GitHub owner and
  repository name.
- A real S3 bucket for Terraform remote state, **one per AWS account**,
  named `k8s-demo-tfstate-<account-id>`. Each `live/<env>/backend.tf`
  already has an active (not commented-out) S3 backend block, and there is
  no DynamoDB lock table anywhere: locking uses the S3 backend's native
  `use_lockfile`, which requires Terraform >= 1.10. Each environment's
  backend names the bucket for the account it runs in. The bucket
  must exist before the first `terraform init` -- Terraform cannot create the
  backend it is configured to use. See `docs/SETUP.md` step 1 for the
  create-bucket commands.
- Per-environment GitHub Environment variables/secrets: `AWS_ROLE_ARN`
  (the `cicd_role_arn` Terraform output) on all three; `AWS_REGION`,
  `EKS_CLUSTER_NAME`, `APP_IRSA_ROLE_ARN`, `ENVIRONMENT_SHORT` (`dev`/`prod`)
  on `development`/`production` only (`shared` has none of these, since
  nothing deploys there); and, on `shared` only, `ECR_REPOSITORY` (the
  `ecr_repository_url` output). See the top-level `README.md`'s "Wiring up
  GitHub" section.
- Nothing for the two cluster add-ons: Terraform installs both the AWS Load
  Balancer Controller (chart 1.13.4 / controller v2.13.4) and the External
  Secrets Operator (chart 2.9.0), each pinned in `live/<env>/main.tf`. The
  ALB controller's chart version and the `data "http"` IAM policy tag must
  be bumped together -- chart 3.x exists and is a major controller release
  needing a different policy, so treat that as a deliberate upgrade.
- Cluster add-ons that this Helm chart assumes are already installed:
  the AWS Load Balancer Controller and the External Secrets Operator (both
  public Helm charts, not part of this repo -- see `infra/k8s/README.md`).

## Validation caveat

CI now enforces most of this on every PR and every merge to `main`:
`.github/workflows/reusable-infra-checks.yml` runs `terraform fmt -check`,
`terraform validate` against all three roots, `helm lint`, and `helm
template` for both environments and the TLS branch, and the build job
depends on it. What follows is the state of things that CI still does *not*
cover.

Terraform CLI, Helm CLI, and the Pants launcher were not available in the
sandbox this project was originally built in, so much of it was only
syntax-checked. Current state:

- **Terraform: validated.** `terraform init -backend=false && terraform
  validate` passes for all three roots (`dev`, `prod`, `shared`). `plan`
  and `apply` have still never been run, so anything that only surfaces
  against real AWS state remains unverified.
- **Helm: linted.** `make helm-lint` passes (both charts, both value sets,
  and both branches of the Ingress TLS conditional). That proves the
  templates render; not that they are correct against a live cluster.
- **Pants: tested and linted, not packaged.** `pants test ::`, `pants lint
  check ::` and `pants tailor --check` all pass. `pants package src/app:docker`
  (`make build`) has **not** been run, so the cross-platform packaging path
  above is unproven.

All of the above ran on macOS/arm64 (Pants selects `local_macos`); CI runs on
linux/x86_64, so a platform-specific failure would not have been caught.
