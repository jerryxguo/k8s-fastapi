locals {
  cluster_name = "${var.name_prefix}-eks"
  tags = {
    NamePrefix = var.name_prefix
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix  = var.name_prefix
  cluster_name = local.cluster_name
  vpc_cidr     = var.vpc_cidr

  # Prod gets one NAT gateway per AZ for resilience, unlike dev's single
  # shared NAT gateway.
  single_nat_gateway = false

  tags = local.tags
}

# No ECR module here: the "shared" environment owns the single shared repo
# and grants this account cross-account pull (see
# infra/terraform/live/shared/main.tf's pull_account_ids) -- the same image
# digest built and pushed there is what gets deployed straight to
# production.
locals {
  ecr_repository_arn = "arn:aws:ecr:${var.region}:${var.shared_account_id}:repository/k8s-demo-shared/service-api"
}

module "eks" {
  source = "../../modules/eks-cluster"

  cluster_name        = local.cluster_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  admin_principal_arn = var.admin_principal_arn
  cicd_role_arn       = module.cicd_role.role_arn

  node_min_size     = 3
  node_max_size     = 6
  node_desired_size = 3

  tags = local.tags
}

module "cicd_role" {
  source = "../../modules/github-oidc-cicd-role"

  name_prefix                = var.name_prefix
  github_org                 = var.github_org
  github_repo                = var.github_repo
  github_owner_id            = var.github_owner_id
  github_repository_id       = var.github_repository_id
  github_environment         = "production"
  grant_ecr_push             = false # prod only deploys; "shared" owns push access
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
  tags                       = local.tags
}

resource "aws_secretsmanager_secret" "app" {
  name = "${var.name_prefix}/app-config"
  tags = local.tags
}

# aws_secretsmanager_secret only creates the secret's container -- it has
# zero versions until something puts a value into it, and GetSecretValue
# (what ExternalSecret's dataFrom.extract calls) fails outright against a
# secret with no version at all ("Secret does not exist" from ESO's point
# of view, even though the secret resource itself is right there in the
# console). This placeholder version is required just to make the secret
# syncable -- {} is valid, empty JSON, matching values.yaml's note that the
# app tolerates missing keys via plain pydantic defaults.
# `lifecycle.ignore_changes` is deliberate: once a human populates the real
# value out of band (AWS CLI/console, never committed here), a future
# `terraform apply` must not stomp it back to this placeholder.
resource "aws_secretsmanager_secret_version" "app" {
  secret_id     = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({})

  lifecycle {
    ignore_changes = [secret_string]
  }
}

module "app_irsa" {
  source = "../../modules/irsa-role"

  name_prefix          = var.name_prefix
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "k8s-demo"
  service_account_name = "k8s-demo-service"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOwnSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.app.arn]
      }
    ]
  })

  tags = local.tags
}

module "external_secrets_irsa" {
  source = "../../modules/irsa-role"

  name_prefix          = var.name_prefix
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "external-secrets"
  service_account_name = "external-secrets"

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEnvironmentSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = ["arn:aws:secretsmanager:${var.region}:*:secret:${var.name_prefix}/*"]
      }
    ]
  })

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Cluster bootstrap, Terraform-managed. This used to be a set of manual
# kubectl/helm steps in infra/k8s/README.md -- moved here so a fresh
# environment is fully stood up by `terraform apply` alone, with nothing
# left for a human to run by hand afterward. None of this runs as CI: it runs
# as whatever principal applies Terraform (var.admin_principal_arn), granted
# cluster-admin by the access entry in modules/eks-cluster/main.tf.
# ---------------------------------------------------------------------------

# The app's namespace. Not templated in the Helm chart itself (see
# infra/k8s/helm/fastapi-service/templates/namespace.yaml) so Terraform stays
# the single owner of the namespace object.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "k8s-demo"
  }

  depends_on = [module.eks]
}

# Namespace for the hyperion service, sharing this same EKS cluster. Same
# reasoning as kubernetes_namespace_v1.app above, and a worked example of
# adding a second service's namespace to this shared cluster.
resource "kubernetes_namespace_v1" "hyperion" {
  metadata {
    name = "hyperion"
  }

  depends_on = [module.eks]
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  # Pinned: unpinned, two applies weeks apart can install different operator
  # versions, including across a CRD API-version bump.
  version          = "2.9.0"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  # Replaces the manual `kubectl annotate serviceaccount ...` step --
  # the IRSA role annotation is applied by Helm at install time instead.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa.role_arn
  }

  depends_on = [module.eks, module.external_secrets_irsa]
}

# The ClusterSecretStore the app chart's ExternalSecret references.
#
# helm_release, not kubernetes_manifest: kubernetes_manifest resolves its
# group-version against the live API during *plan*, which cannot succeed on a
# fresh environment where the cluster does not exist yet -- and a plan error
# aborts the whole apply, including the release that installs the CRD. Helm
# does no plan-time lookup, so depends_on below is sufficient and `terraform
# apply` is one-shot. The chart pins apiVersion v1; v1beta1 is no longer
# served and fails as if the CRD were missing.
resource "helm_release" "cluster_secret_store" {
  name  = "cluster-secret-store"
  chart = "${path.module}/../../../k8s/helm/cluster-secret-store"
  # Cluster-scoped object, but a Helm release still needs a namespace to keep
  # its own release metadata in. external-secrets already exists by this
  # point (helm_release.external_secrets creates it).
  namespace = "external-secrets"

  set {
    name  = "region"
    value = var.region
  }

  # Orders the apply after the operator and therefore after its CRDs. Unlike
  # the kubernetes_manifest version, this is sufficient on its own.
  depends_on = [helm_release.external_secrets]
}

# AWS Load Balancer Controller. AWS publishes no managed policy ARN for it,
# so the policy is vendored (policies/aws-load-balancer-controller-v2.13.4.json,
# from that tag's docs/install/iam_policy.json) rather than fetched at apply
# time: an apply then needs no third-party egress, and a permission change
# shows up in a diff. The vendored version and the chart version below must
# move together -- a controller newer than its policy fails at runtime, not
# at apply.
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.name_prefix}-alb-controller"
  policy = file("${path.module}/../../policies/aws-load-balancer-controller-v2.13.4.json")
  tags   = local.tags
}

module "alb_controller_irsa" {
  source = "../../modules/irsa-role"

  name_prefix          = var.name_prefix
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  managed_policy_arns  = [aws_iam_policy.alb_controller.arn]

  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  # Chart version is not the app version: 1.13.4 ships controller v2.13.4,
  # matching the vendored IAM policy. Newest is 3.x (a major controller
  # release) -- moving there means bumping the policy too.
  version   = "1.13.4"
  namespace = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa.role_arn
  }

  depends_on = [module.eks, module.alb_controller_irsa]
}
