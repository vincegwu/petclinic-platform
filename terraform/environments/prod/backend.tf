# Remote state backend for the prod environment.
#
# Run scripts/bootstrap-state.sh once per AWS account before the first
# `terraform init`. It provisions the S3 bucket and DynamoDB table below and
# prints the exact bucket name — replace the placeholder account ID with it.
# Same bucket as dev, separate state key.

terraform {
  backend "s3" {
    bucket         = "petclinic-terraform-state-205930623242"
    key            = "petclinic/prod/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "petclinic-terraform-locks"
    encrypt        = true
  }
}
