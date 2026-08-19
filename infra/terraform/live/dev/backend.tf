# One state bucket per AWS account. Backend blocks can't take variables, so
# bucket and profile are literals rather than var.profile.

terraform {
  backend "s3" {
    bucket       = "k8s-demo-tfstate-621508399429"
    key          = "k8s-demo-service/dev/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
    profile      = "dev-full"
  }
}
