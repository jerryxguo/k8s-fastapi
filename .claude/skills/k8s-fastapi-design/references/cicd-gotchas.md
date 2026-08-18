# CI/CD gotchas specific to this project

## Reusable workflow secret scoping

A job inside a *called* (reusable) workflow that declares `environment: <name>` does not automatically get access to secrets defined on that GitHub Environment, even when the reusable workflow lives in the same repository as the caller and is invoked by relative path. The caller also needs `secrets: inherit` (or to pass that specific secret explicitly) on the job that calls it -- without it, every environment-scoped secret silently resolves to an empty string inside the called workflow, which surfaces as something like "Credentials could not be loaded" from whatever action tries to use the secret, with no indication that the secret itself is the problem. This is easy to miss because adding the secret to the Environment in the GitHub UI looks like it should be sufficient, and nothing in the workflow YAML looks obviously wrong.

## GitHub Environment secrets vs. variables in printed workflow logs

An unset secret referenced in a workflow step's `with:` block renders as an omitted line in the printed log output, not as an empty-quoted value -- so a missing `role-to-assume: ${{ secrets.X }}` line in a run's log usually means the secret itself was never set on that Environment, not that the workflow forgot to reference it.

## Production approval gates live in Environment settings, not YAML

A required-reviewer approval gate before a production deploy is configured entirely in GitHub's own Environment protection rules (repo Settings -> Environments -> the environment -> Deployment protection rules), not via anything in the workflow file. A workflow job with `environment: production` does not pause for approval by default -- that only happens once a required reviewer is explicitly configured on that Environment. Don't assume a gate exists just because the job targets a production-sounding environment name.

## Diagnosing "could not load credentials" in an OIDC-based job

When `configure-aws-credentials`-style actions fail to load credentials in CI, check in this order: (1) is the relevant secret actually present in the printed `with:` block, or silently omitted (see above); (2) does the calling job have `secrets: inherit` if the failing step lives in a reusable workflow (see above); (3) does the IAM role's OIDC trust policy actually match the token's subject claim for this exact repo/org/environment. Each of these produces a similarly generic-sounding failure, so check them in order rather than assuming which one it is.
