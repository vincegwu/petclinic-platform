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
