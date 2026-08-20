# One state bucket per AWS account, named for it: a bucket owned by another
# account returns 403 to these credentials. Backend blocks can't take
# variables, so bucket and profile are literals. The bucket must exist before
# the first init (see DESIGN-NOTES).

terraform {
  backend "s3" {
    bucket       = "k8s-demo-tfstate-137982683245"
    key          = "k8s-demo-service/prod/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
    profile      = "prod-full"
  }
}
