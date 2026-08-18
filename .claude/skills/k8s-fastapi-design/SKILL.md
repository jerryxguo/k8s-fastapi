---
name: k8s-fastapi-design
description: Captures the architecture, design rationale, and hard-won operational gotchas for the k8s-fastapi project (a FastAPI service deployed to AWS EKS via Terraform, built with Pants, deployed through GitHub Actions CI/CD). Use when working on this repo's Terraform (infra/terraform), Pants config (pants.toml, BUILD files), Dockerfile/packaging, GitHub Actions workflows, or EKS/Kubernetes manifests, or when a change in one of those areas produces an error that looks like it should already have a known cause -- check references/ before re-deriving the fix from scratch.
---

# k8s-fastapi design notes

This project is a FastAPI service on AWS EKS, provisioned with Terraform, built and packaged with Pants, and deployed via GitHub Actions. This skill exists so a session picking up this repo doesn't have to rediscover its design decisions or re-hit the same operational traps that were already solved once.

## When to use

- Editing anything under `infra/terraform/` (modules or `live/<env>`)
- Editing `pants.toml`, any `BUILD` file, or the Dockerfile under `src/app/`
- Editing `.github/workflows/*.yml` or debugging a CI run
- An error surfaces that mentions Terraform state/providers, EKS access entries, IRSA, GitHub OIDC, Pants resolves, or Docker cross-platform builds -- these have known causes, see `references/`

## How this repo is organized

```
pants.toml, BUILD           Pants build config; root BUILD sets cross-cutting
                             __defaults__ for build environments
src/app/                    FastAPI app + its pex_binary/docker_image targets
tests/                      pytest suite (its own Pants source root -- see
                             references/pants-build.md)
infra/terraform/
  modules/                  Reusable, hand-written modules (vpc, eks-cluster,
                             ecr-repo, github-oidc-cicd-role, irsa-role) --
                             the VPC/EKS modules underneath are well-audited
                             public registry modules; the smaller
                             account-level pieces are owned outright here.
  live/{dev,prod,shared}/    Per-environment root modules. "shared" owns only
                             the ECR repo + its own CI/CD push role; nothing
                             else runs there. Apply shared first, then
                             dev/prod (each needs shared's account ID).
infra/k8s/helm/              The Kubernetes-side deploy (Deployment, Service,
                             Ingress, HPA, ExternalSecret) for this service
.github/workflows/            pull-request.yml, release.yml, and the reusable
                             workflows they call
```

## Design decisions and why

- **One shared ECR repository, owned by a dedicated account.** Every environment pulls the exact same image digest from one place; only the owning account's CI/CD role can push (`grant_ecr_push`). This is what makes "the same build is promoted unchanged through every environment" actually true -- see `references/architecture.md` for the tradeoffs.
- **IRSA (IAM Roles for Service Accounts) per workload identity**, not a shared node-level role -- the app, the EBS CSI driver, and the External Secrets Operator each get their own narrowly-scoped IAM role federated to a specific Kubernetes ServiceAccount.
- **Per-environment, per-repo GitHub OIDC roles**, each trusted only for one GitHub Environment and permission-boundary-scoped to that environment's own named resources.
- **Secrets via Secrets Manager + External Secrets Operator**, not an in-app AWS SDK client -- application code stays free of cloud-specific dependencies.
- **A single Pants resolve** for the whole project (app + test + lint/typecheck tooling) -- there's no second, genuinely incompatible dependency set that would justify a second resolve.

Full rationale, including things that look over-engineered until you see the failure mode they prevent, is in `references/architecture.md`.

## Known gotchas (read before you hit them again)

- `references/terraform-gotchas.md` -- state drift between machines, EKS access-entry replacement traps, Kubernetes version upgrade constraints, IRSA-for-addons, GitHub OIDC trust-subject matching, and the S3+DynamoDB remote-state bootstrap sequence.
- `references/pants-build.md` -- resolve/source-root config traps, and building a Docker image whose target architecture differs from the machine running `pants package`.
- `references/cicd-gotchas.md` -- reusable-workflow secret scoping, GitHub Environment secrets vs. variables, and Docker credential-helper failures inside Pants's build sandbox.

If you hit an error in one of these areas that isn't covered, add it to the relevant reference file once solved -- that's the entire point of this skill.
