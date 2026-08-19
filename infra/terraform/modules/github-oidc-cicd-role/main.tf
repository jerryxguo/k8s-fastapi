# A GitHub-OIDC-assumable IAM role, scoped to one repo (optionally one
# GitHub Environment), with a permission boundary that restricts it to
# name-prefixed resources. Written directly in this repo (not sourced via an
# external module reference) so the project stays self-contained -- one role
# per environment, since each environment already lives in its own state /
# can live in its own AWS account.

data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : var.existing_oidc_provider_arn

  # GitHub now issues OIDC tokens with immutable subject claims by default
  # for repos created after 2026-07-15 (owner/repo numeric IDs baked in
  # alongside the names, e.g. "org@123456/repo@789012") -- see
  # docs.github.com/actions/reference/openid-connect-reference. When
  # github_owner_id/github_repository_id are set, build the sub condition
  # to match that real format; otherwise fall back to the legacy
  # plain-name format for repos that still use it.
  github_org_claim  = var.github_owner_id != null ? "${var.github_org}@${var.github_owner_id}" : var.github_org
  github_repo_claim = var.github_repository_id != null ? "${var.github_repo}@${var.github_repository_id}" : var.github_repo

  # e.g. "repo:jerryxguo@10950337/k8s-fastapi@1337888631:environment:production"
  oidc_sub = var.github_environment != null ? "repo:${local.github_org_claim}/${local.github_repo_claim}:environment:${var.github_environment}" : "repo:${local.github_org_claim}/${local.github_repo_claim}:ref:refs/heads/${var.github_ref_branch}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect = "Allow"
    # TagSession is required alongside AssumeRoleWithWebIdentity because
    # aws-actions/configure-aws-credentials@v4 attaches GitHub context
    # (repo, ref, sha, workflow, etc.) as role session tags by default.
    # Without this, STS rejects the whole assume-role call with
    # "Not authorized to perform sts:AssumeRoleWithWebIdentity" even
    # though the sub/aud conditions below match correctly.
    actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.oidc_sub]
    }
  }
}

# Permission boundary: everything this role can touch must be named
# "${name_prefix}*". This is the single most important control on this
# role -- it caps the blast radius of a compromised or misconfigured CI/CD
# credential to just this project's own resources.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid    = "ScopedToNamePrefix"
    effect = "Allow"
    actions = [
      "ecr:*",
      "eks:Describe*",
      "eks:List*",
      "eks:AccessKubernetesApi",
      "logs:*",
      "cloudwatch:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/NamePrefix"
      values   = ["${var.name_prefix}*"]
    }
  }

  # A handful of read-only/account-level actions that don't carry a
  # NamePrefix tag to condition on (needed for ECR auth and STS identity
  # checks, neither of which is scoped to a single resource).
  statement {
    sid    = "UnscopedReadOnly"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "eks:DescribeCluster",
      "eks:ListClusters",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name   = "${var.name_prefix}-cicd-boundary"
  policy = data.aws_iam_policy_document.boundary.json
  tags   = var.tags
}

resource "aws_iam_role" "cicd" {
  name                 = "${var.name_prefix}-cicd-${var.github_repo}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = aws_iam_policy.boundary.arn
  max_session_duration = 3600
  tags                 = var.tags
}

data "aws_iam_policy_document" "cicd_permissions" {
  # Only the environment that owns the shared ECR repo (by default, "dev" --
  # see infra/terraform/live/dev/main.tf) needs push access; prod's CI/CD
  # role only ever needs to deploy an image someone else already pushed
  # (cross-account pull granted via modules/ecr-repo's pull_account_ids).
  dynamic "statement" {
    for_each = var.grant_ecr_push ? [1] : []
    content {
      sid       = "PushPullImages"
      effect    = "Allow"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.grant_ecr_push ? [1] : []
    content {
      sid    = "PushPullRepo"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
      ]
      resources = [var.ecr_repository_arn]
    }
  }

  statement {
    sid       = "DescribeAndAuthCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters", "eks:AccessKubernetesApi"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cicd" {
  name   = "cicd-permissions"
  role   = aws_iam_role.cicd.id
  policy = data.aws_iam_policy_document.cicd_permissions.json
}
