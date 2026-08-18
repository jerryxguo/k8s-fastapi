# k8s-fastapi -- design notes and operational gotchas

A FastAPI service deployed to AWS EKS via Terraform, built and packaged with Pants, deployed through GitHub Actions CI/CD. This file captures the design rationale and hard-won operational traps for this repo, so a session doesn't have to rediscover them.

## Repo layout

```
pants.toml, BUILD           Pants build config; root BUILD sets cross-cutting
                             __defaults__ for build environments
src/app/                    FastAPI app + its pex_binary/docker_image targets
tests/                      pytest suite (its own Pants source root)
infra/terraform/
  modules/                  Reusable, hand-written modules (vpc, eks-cluster,
                             ecr-repo, github-oidc-cicd-role, irsa-role)
  live/{dev,prod,shared}/    Per-environment root modules. "shared" owns only
                             the ECR repo + its own CI/CD push role. Apply
                             shared first, then dev/prod.
infra/k8s/helm/              Kubernetes-side deploy (Deployment, Service,
                             Ingress, HPA, ExternalSecret)
.github/workflows/            pull-request.yml, release.yml, and the reusable
                             workflows they call
```

## Design decisions and why

- **One shared ECR repository, owned by a dedicated account/environment.** Every environment pulls the exact same image digest; only the owning environment's CI/CD role can push (`grant_ecr_push`). Tradeoff: a dedicated shared owner means losing one environment doesn't take the registry down with it, at the cost of one more account/environment to provision.
- **IRSA (IAM Roles for Service Accounts) per workload identity**, not a shared node-level role -- the app, the EBS CSI driver, and the External Secrets Operator each get their own narrowly-scoped IAM role federated to one specific Kubernetes ServiceAccount.
- **Per-environment, per-repo GitHub OIDC roles**, each trusted only for one GitHub Environment and permission-boundary-scoped to that environment's own named resources -- caps the blast radius of a compromised or misconfigured CI/CD credential.
- **Secrets via Secrets Manager + External Secrets Operator**, not an in-app AWS SDK client -- app code stays free of cloud-specific dependencies; secret sync happens out-of-band.
- **Everything CI/CD needs lives in this repository** -- composite actions/reusable workflows referenced by relative path, never another repo's floating ref.
- **In-cluster smoke test** -- hits the ClusterIP Service directly from inside the cluster rather than needing a runner with access to an internal load balancer.
- **A single Pants resolve** for the whole project (app + test + lint/typecheck tooling) -- no second, genuinely incompatible dependency set exists that would justify a second resolve.
- **Pants over plain pip + hand-written Dockerfile** -- reproducible hash-locked resolve, a dependency graph so lint/test/package only touch what changed, and a pex_binary + docker_image packaging model instead of re-running installs inside the Dockerfile every build.

## Terraform gotchas

**State only knows what it's told.** `plan`/`apply` compares config against the *state file*, not AWS reality. A resource created outside this exact state (manually, from a different machine's local state, or a lost state file) makes Terraform try to create it again, often failing "already exists." Fix via `terraform import` per resource, after confirming the AWS account in use (`aws sts get-caller-identity`). `-refresh-only` reconciles state with reality; it does not pick up config changes.

**Local state does not travel between machines.** A second machine has no way to see another machine's local-state applies -- its `plan` looks like nothing happened yet, or shows a bogus recreate-everything diff. Fix is a remote backend (S3 + DynamoDB lock table), not manually copying the state file (works for one snapshot only) and never committing `terraform.tfstate` to git (plaintext secrets, no locking, bad merge fit). Bootstrapping the S3/DynamoDB backend is chicken-and-egg: create the bucket/table out-of-band first, then `terraform init -migrate-state` (not plain `init`) to copy existing state up. One state bucket per AWS account avoids needing cross-account bucket policies.

**EKS access-entry principal ARN must be a real, assumable identity** -- a real IAM user/role ARN, not one fabricated from an assumed-role STS ARN, and not a leftover placeholder. A wrong value shows up in `plan` as `-/+` (destroy + recreate, not in-place update) on the access entry and its policy association, because AWS's API can't mutate the principal. Applying that plan destroys the entry currently granting your own admin access and replaces it with one for a principal nobody can assume -- read `-/+` diffs on access entries carefully; if the "current" value shown is the one that's actually working today, the tfvars value is wrong, not the state.

**EKS Kubernetes version support windows matter.** Once a version's support window ends, its node-group AMIs stop being published and `apply` fails with "Requested AMI for this version is not supported" with no config change. The one-minor-version-at-a-time rule only applies to *upgrading* an existing cluster, not creation -- destroying and recreating lets you jump straight to any currently-supported version.

**Cluster add-ons need their own IRSA role.** An add-on that calls AWS APIs (e.g. a CSI driver) needs a dedicated IAM role bound via IRSA, or its pods crash-loop with `UnauthorizedOperation` (falling back to the node's much narrower instance role) even though the add-on itself "created successfully."

**GitHub OIDC trust subject must match exactly.** The trust condition compares the token's `sub` claim to a literal string built from org/repo/environment -- a placeholder org value means the condition never matches the real token, and `AssumeRoleWithWebIdentity` fails with `Not authorized`. Make this variable required with no default so it fails at `plan` time, not silently in CI. Also: a variable existing at an environment's root doesn't automatically reach a child module -- it must be explicitly passed in the module block, or the module silently uses its own default instead. Note: for a personal GitHub account (not an org), the same field is just the username -- the OIDC subject format (`repo:<owner>/<repo>:environment:<env>`) doesn't change.

**Provider "Unrecognized remote plugin message" errors are usually environmental.** If every provider (even the simplest ones) fails identically loading its schema, something is blocking the machine from executing freshly-downloaded plugin binaries -- check for a quarantine/Gatekeeper flag (macOS: `xattr -l <path>`, clear with `xattr -dr com.apple.quarantine <path>`), try a clean re-download (wipe `.terraform`, reinit), and if neither works, run the provider binary directly to see the actual OS-level error instead of Terraform's generic translation of it.

## Pants build gotchas

**Resolve and source-root config.** Set `[python].default_resolve` or targets without an explicit `resolve=` fall back to Pants's own default resolve name, which doesn't exist here, breaking lint/test with an unrecognized-resolve error. Every top-level source directory (e.g. a `tests/` sibling of `src/`) needs its own entry in `[source].root_patterns`, or it has no source root at all.

**Cross-platform Docker builds.** `pants package` resolves dependencies for whatever machine runs the command, not for whatever machine the image will run on. Building on a different CPU architecture than the EKS node group bundles wheels for the wrong platform, and the Dockerfile's venv-unpack step (running inside a container matching the *target* architecture) fails with "Failed to find compatible interpreter" / "this pex had no distributions." Fix with either a `docker_environment` (executes the resolve on the real target architecture, natively when possible, via Docker/emulation as a `fallback_environment` otherwise -- handles anything needing compilation) or a `complete_platforms` file on the `pex_binary` (fetches prebuilt wheels for the target platform tag directly -- simpler, but only works if every dependency ships a prebuilt wheel for that platform). Either way, the `docker_image`'s own `build_platform` must match the same target architecture, or the final `docker build` step defaults to the host's architecture regardless of what the PEX contains. Set these repo-wide via `__defaults__` in the root `BUILD` file (cascades down the whole tree, overridable locally) rather than repeating per target.

**Docker credential helper visibility.** Pants runs `docker build` in a sandboxed subprocess that doesn't inherit the full shell `PATH` -- a credential-store helper that resolves fine in a normal terminal can fail inside Pants's sandbox with "executable file not found in $PATH." Fix via `[docker].env_vars` passing `PATH` through, not reconfiguring Docker itself.

**Lockfile is committed, not regenerated in CI.** Generated once and committed; CI has no step to regenerate it, so it must already be present for lint/test/package to resolve anything. Regenerate and recommit whenever the underlying requirements file changes.

## CI/CD gotchas

**Reusable workflow secret scoping.** A job in a *called* reusable workflow declaring `environment: <name>` does not automatically get that Environment's secrets, even same-repo/relative-path. The caller job also needs `secrets: inherit` (or explicit secret passing) -- without it, every environment-scoped secret silently resolves to an empty string, surfacing as a generic "credentials could not be loaded" with nothing pointing at secrets being the cause.

**Environment secrets vs. variables in logs.** An unset secret referenced in a step's `with:` block renders as an omitted line in the printed log, not an empty-quoted value -- a missing `role-to-assume:` line usually means the secret was never set on that Environment, not that the workflow forgot to reference it.

**Production approval gates live in Environment settings, not YAML.** Configured entirely under repo Settings -> Environments -> Deployment protection rules. A job with `environment: production` does not pause for approval by default -- only once a required reviewer is explicitly added.

**Diagnosing "could not load credentials" in an OIDC job**, check in order: (1) is the secret actually present in the printed `with:` block; (2) does the calling job have `secrets: inherit` if the step lives in a reusable workflow; (3) does the IAM role's OIDC trust policy match the token's subject for this exact repo/org/environment. Each produces a similar-looking failure -- check in this order rather than guessing.
