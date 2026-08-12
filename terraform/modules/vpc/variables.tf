variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone (same order as availability_zones)"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones to spread public subnets across (same order as public_subnet_cidrs)"
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to merge into every resource"
  type        = map(string)
  default     = {}
}
