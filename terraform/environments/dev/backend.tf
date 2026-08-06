# Remote state backend for the dev environment.
#
# Run scripts/bootstrap-state.sh once per AWS account before the first
# `terraform init`. It provisions the S3 bucket and DynamoDB table below and
# prints the exact bucket name — replace the placeholder account ID with it.

terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-205930623242"
    key            = "petclinic/dev/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
