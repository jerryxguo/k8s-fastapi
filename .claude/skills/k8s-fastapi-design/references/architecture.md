# Architecture and design rationale

## Terraform module strategy

Compute infrastructure (VPC, EKS cluster, node group) is provisioned with well-audited public registry modules -- hand-rolling that wiring is more error-prone than it looks and buys nothing. The smaller, project-specific pieces (ECR repo, GitHub OIDC CI/CD role, IRSA roles) are hand-written modules owned outright by this repo, since they're simple enough to review directly and don't benefit from a third-party abstraction.

## ECR strategy: one shared repository, one owning account

There is exactly one ECR repository, owned by a dedicated "shared" environment that has no VPC, no EKS cluster, and no application running in it -- just the ECR repo and the one GitHub OIDC role allowed to push to it. That environment's `ecr-repo` module grants cross-account pull to every other environment's account. Neither of the other environments' Terraform creates an ECR repository at all -- each references the shared repo's ARN directly, and each one's CI/CD role is created with `grant_ecr_push = false`. Only the shared environment's CI/CD role can push; every other environment can only describe/deploy.

This is a deliberate tradeoff against the simpler alternative of folding the shared repo into one of the environments directly (avoiding a dedicated extra AWS account): a dedicated shared account means losing one environment doesn't take the registry down with it, and no environment that also runs a real workload doubles as the thing every other environment's deploy depends on.

## GitHub OIDC -> per-environment IAM role

Each environment gets its own IAM role, trusted only for that GitHub Environment via an OIDC subject condition, with a permission boundary restricting it to resources tagged with that environment's own name prefix. This caps the blast radius of a compromised or misconfigured CI/CD credential to just that one environment's own resources -- see `terraform-gotchas.md` for the exact subject-matching mechanics and how this fails silently if misconfigured.

## IRSA over node-level credentials

Every workload identity that needs AWS API access -- the application itself, the EBS CSI driver's controller, the External Secrets Operator -- gets its own IAM role federated through the cluster's OIDC provider to one specific Kubernetes ServiceAccount, rather than a broad role shared by every pod on a node. A missing IRSA role for a cluster add-on is a common, easy-to-miss gap (see `terraform-gotchas.md`).

## Autoscaling by default

The Helm chart enables a HorizontalPodAutoscaler out of the box, since a static replica count is a common gap in simple container deployments and is easy to get wrong by omission later.

## Secrets via Secrets Manager + External Secrets Operator

Application settings are read via a plain settings object with zero direct AWS SDK calls -- secret sync happens out-of-band via the External Secrets Operator, so application code carries no cloud-provider-specific dependency at all.

## Everything CI/CD needs lives in this repository

Every composite action and reusable workflow is defined locally and referenced by relative path, not pulled from another repository's floating branch/tag ref. That means no floating-tag risk, and nothing to break if some other repository changes out from under this one.

## In-cluster smoke test

The post-deploy smoke test hits the ClusterIP Service directly from inside the cluster via a throwaway pod, rather than reaching the Ingress from an external runner -- no need for a runner with network access to an internal load balancer, and just as meaningful a check for a healthcheck-style endpoint.

## Promotion order and environment gating

Promotion goes strictly one environment to the next, each gated by its own CI/CD environment (approval rules + environment-scoped secrets), smoke-tested after every deploy so a failing environment blocks the next one rather than silently propagating a bad build forward.

## Build tooling choice (Pants)

This project builds with Pants rather than a plain pip install + hand-written Dockerfile, for a reproducible hash-locked dependency resolve, a fine-grained dependency graph (lint/test/package only touch what actually changed), and a pex_binary + docker_image packaging model instead of re-running package installs inside the Dockerfile on every build. See `pants-build.md` for the traps this introduces.
