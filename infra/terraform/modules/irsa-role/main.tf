# Generic reusable "IAM Role for Service Account" (IRSA) module: a
# Kubernetes ServiceAccount assumes this role via the cluster's OIDC
# provider. Instantiated once per workload identity needed (the app itself,
# and separately for cluster add-ons like external-secrets).

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-${var.service_account_name}-irsa"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  # Keyed on list index rather than toset(var.managed_policy_arns): for_each
  # requires its KEY set to be known at plan time, but the values themselves
  # can still be unknown. alb_controller_irsa passes
  # [aws_iam_policy.alb_controller.arn] -- an ARN created in this same apply,
  # so its value is unknown at plan time. toset() over a list containing an
  # unknown value produces unknown set members, which for_each rejects
  # outright ("Invalid for_each argument ... cannot be determined until
  # apply"). Indices (0, 1, 2, ...) are always known regardless of what the
  # values resolve to, so keying on those sidesteps the problem entirely.
  # (Same class of issue as the access_entries for_each note in
  # modules/eks-cluster/main.tf.)
  for_each   = { for idx, arn in var.managed_policy_arns : idx => arn }
  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count  = var.inline_policy_json == null ? 0 : 1
  name   = "inline"
  role   = aws_iam_role.this.id
  policy = var.inline_policy_json
}
