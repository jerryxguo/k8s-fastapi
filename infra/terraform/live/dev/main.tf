locals {
  cluster_name = "${var.name_prefix}-eks"
  tags = {
    NamePrefix = var.name_prefix
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = var.name_prefix
  cluster_name       = local.cluster_name
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = true # cheaper for dev; prod overrides to false
  tags               = local.tags
}

# No ECR module here: the "shared" environment owns the single shared repo
# and grants this account cross-account pull (see
# infra/terraform/live/shared/main.tf's pull_account_ids) -- the same image
# digest built and pushed there is what every environment deploys.
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

  node_min_size     = 1
  node_max_size     = 3
  node_desired_size = 2

  tags = local.tags
}

module "cicd_role" {
  source = "../../modules/github-oidc-cicd-role"

  name_prefix                 = var.name_prefix
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  github_owner_id             = var.github_owner_id
  github_repository_id        = var.github_repository_id
  github_environment          = "development"
  grant_ecr_push              = false # dev only deploys; "shared" owns push access
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
  tags                       = local.tags
}

# Example Secrets Manager secret the app would read via the External Secrets
# Operator + IRSA. Left empty/placeholder;
# populate real values out of band (never commit real secrets to tfvars).
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

  name_prefix           = var.name_prefix
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "k8s-demo"
  service_account_name  = "k8s-demo-service"

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

# IRSA identity for the external-secrets operator itself (cluster add-on
# installed via Helm -- see infra/k8s/README.md), so it can read any secret
# under this environment's name_prefix on behalf of workloads.
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
# left for a human to run by hand afterward. The CI/CD role's IAM policy
# (modules/eks-cluster/main.tf) stays deliberately scoped to
# AmazonEKSEditPolicy -- none of this needs to run as CI; it runs as
# whatever principal is applying Terraform (var.admin_principal_arn), the
# same one already granted cluster-admin via the EKS access entry.
# ---------------------------------------------------------------------------

# The app's namespace. Not templated in the Helm chart itself (see
# infra/k8s/helm/fastapi-service/templates/namespace.yaml) because
# namespace create/update is a cluster-scoped action the CI/CD role can't
# perform -- so it's created here instead, before the app is ever deployed.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = "k8s-demo"
  }

  depends_on = [module.eks]
}

# Namespace for the hyperion service, sharing this same EKS cluster. Same
# reasoning as kubernetes_namespace_v1.app above -- if hyperion's own
# deploy job assumes a CI/CD role scoped the same way (AmazonEKSEditPolicy,
# not cluster-admin), its Helm chart can't template/manage this namespace
# itself either, so it's created here instead.
resource "kubernetes_namespace_v1" "hyperion" {
  metadata {
    name = "hyperion"
  }

  depends_on = [module.eks]
}

# NOTE: this used to be a ClusterRole + ClusterRoleBinding granting the
# CI/CD role permission to manage ExternalSecret objects specifically
# (see cicd-gotchas.md in the k8s-fastapi-design skill for the full story
# of why a naive aggregate-to-edit label didn't work). Removed now that
# the "cicd" access entry in modules/eks-cluster/main.tf uses
# AmazonEKSClusterAdminPolicy -- cluster-admin already covers this and
# every other resource type, current or future, so a per-CRD RBAC grant
# here would just be redundant dead weight.

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
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

# The ClusterSecretStore the chart's ExternalSecret resources reference.
#
# KNOWN BOOTSTRAP CAVEAT: kubernetes_manifest validates its manifest against
# the target CRD's schema at *plan* time, not just apply time -- so on a
# genuinely fresh cluster, the very first `terraform apply` will fail here
# (the external-secrets CRDs don't exist yet when this resource is
# planned, even though helm_release.external_secrets is what's about to
# create them).
#
# IMPORTANT: re-running plain `terraform apply` does NOT fix this on its
# own. Terraform computes the full plan for every resource before applying
# anything; if any one resource's plan errors, the whole apply aborts
# before creating ANYTHING -- including helm_release.external_secrets,
# which is what would install the CRD in the first place. depends_on only
# orders apply once a plan exists; it can't rescue a resource whose plan
# itself fails. Re-running untargeted just reproduces the same error
# forever on a genuinely fresh cluster.
#
# The actual fix, once per fresh cluster: force a first pass that installs
# the CRDs without ever planning this resource, then apply normally.
#   terraform apply -target=helm_release.external_secrets
#   terraform apply
# -target only pulls in a resource's dependencies (module.eks,
# module.external_secrets_irsa), never things that depend on it -- so this
# resource is excluded from that first plan entirely and can't block it.
# The second, untargeted apply then succeeds (CRDs exist) and also picks
# up everything else still pending. Every apply after that is unaffected.
#
# apiVersion pinned to v1, not v1beta1: chart version 2.9.0 (external-secrets
# operator) only serves ClusterSecretStore under external-secrets.io/v1 --
# v1beta1 was promoted/removed. `kubectl api-resources` against a live
# cluster confirmed this (clustersecretstores  external-secrets.io/v1). Using
# a version the CRD doesn't serve fails with the same "cannot select exact
# GV from REST mapper" error as a genuinely-missing CRD, which is easy to
# misdiagnose as the CRD-bootstrap caveat above rather than a stale
# apiVersion -- confirm what a CRD actually serves with `kubectl api-resources`
# before assuming a GV error is the bootstrap-ordering issue.
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

# AWS Load Balancer Controller -- required for infra/k8s/helm's
# ingress.yaml (className: alb). The IAM policy is AWS's own published
# policy for this controller (there's no AWS-managed policy ARN for it),
# fetched at apply time rather than vendored as a ~500-line local copy so
# it doesn't silently go stale; pin the URL's version tag deliberately and
# bump it occasionally rather than tracking a branch.
data "http" "alb_controller_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.0/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name   = "${var.name_prefix}-alb-controller"
  policy = data.http.alb_controller_policy.response_body
}

module "alb_controller_irsa" {
  source = "../../modules/irsa-role"

  name_prefix           = var.name_prefix
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "kube-system"
  service_account_name  = "aws-load-balancer-controller"
  managed_policy_arns   = [aws_iam_policy.alb_controller.arn]

  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

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
