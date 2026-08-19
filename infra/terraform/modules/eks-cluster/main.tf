# IRSA for the EKS-managed aws-ebs-csi-driver add-on's controller
# deployment, bound to the fixed service account name the add-on creates
# (ebs-csi-controller-sa in kube-system) -- not the general-purpose
# irsa-role module, since this needs module.eks's own OIDC provider
# outputs, and pulling those in from a caller (the way live/dev/main.tf
# wires up module.app_irsa) would mean this module can't stand on its own
# for something as basic as making its own add-ons functional.
data "aws_iam_policy_document" "ebs_csi_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-irsa"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Thin wrapper around terraform-aws-modules/eks/aws. This owns the compute
# platform (cluster + node group) that the Helm chart in infra/k8s later
# deploys the FastAPI service onto.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Module-managed OIDC provider is what makes IRSA possible -- workloads
  # assume IAM roles via their Kubernetes ServiceAccount instead of an
  # instance profile or a shared node-level role.
  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    # service_account_role_arn wires up IRSA for the driver's controller
    # deployment (the part that calls the EC2 API to create/attach/delete
    # EBS volumes). Without it, the controller pods have no AWS credentials
    # at all and crash-loop indefinitely trying to start -- which is also
    # why the add-on itself never reports healthy: EKS won't mark
    # aws-ebs-csi-driver ACTIVE while its controller deployment can't get
    # its pods running, so `terraform apply` just times out waiting. The
    # ebs-csi-node daemonset pods run fine without this, since the
    # per-node agent doesn't need EC2 API access.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = aws_iam_role.ebs_csi.arn
    }
  }

  eks_managed_node_groups = {
    default = {
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      labels = {
        "role" = "app"
      }
    }
  }

  # Grant the Terraform caller and the CI/CD role cluster-admin via the
  # modern EKS Access Entry API rather than editing the aws-auth ConfigMap
  # by hand -- avoids the classic "locked myself out of the cluster" trap.
  authentication_mode = "API_AND_CONFIG_MAP"

  # Both entries unconditional, and cicd_role_arn is required rather than
  # optional: gating a key on an apply-time-unknown ARN makes the for_each key
  # set unknown, which Terraform rejects at plan.
  access_entries = {
    terraform-caller = {
      principal_arn = var.admin_principal_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    cicd = {
      principal_arn = var.cicd_role_arn
      policy_associations = {
        deploy = {
          # DECISION: cluster-admin, not a narrower policy. This project
          # originally scoped CI/CD to AmazonEKSEditPolicy specifically so
          # a compromised GitHub Actions credential couldn't touch
          # cluster-scoped resources. In practice that traded a one-time
          # security decision for ongoing, recurring friction: AWS's
          # managed access policies (Edit, View, Admin) are each a fixed,
          # AWS-defined permission set that can never be extended -- not
          # even by aggregating a custom ClusterRole into Kubernetes'
          # native "edit"/"admin" roles, since access entries bound via
          # policy_associations never consult those objects at all (see
          # cicd-gotchas.md's writeup on this, kept for the general
          # lesson). Every new CRD a Helm chart introduces (ExternalSecret
          # was the first) would otherwise need its own hand-rolled
          # kubernetes_groups + ClusterRoleBinding workaround, forever.
          # Cluster-admin trades that away: a compromised CI/CD credential
          # could do real damage (read all secrets, delete nodes, disable
          # the ALB controller, touch other namespaces), but this was a
          # deliberate, explicit choice to accept that risk in exchange
          # for CI/CD simply working without per-CRD RBAC plumbing.
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  tags = var.tags
}
