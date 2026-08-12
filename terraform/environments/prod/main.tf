# Root module for the prod environment.
# Modules (vpc, eks, ecr, rds, dns, secrets, observability) are wired in here
# as each epic implements them. See docs/jira-backlog.md for the build order.

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones

  tags = local.common_tags
}
