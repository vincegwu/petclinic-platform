# Module: vpc
# All-public subnet design (no NAT Gateway, no private subnets) — see ADR-0001.
# Security groups are the primary access control boundary.

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  public_subnets = {
    for idx, az in var.availability_zones :
    az => var.public_subnet_cidrs[idx]
  }
}

check "subnet_az_count_match" {
  assert {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
    error_message = "public_subnet_cidrs and availability_zones must have the same number of elements."
  }
}

# ---------------------------------------------------------------------------
# VPC, Internet Gateway, public subnets, routing
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                         = "${local.name_prefix}-public-${each.key}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Lock down the VPC's implicit default security group (CIS AWS Foundations 5.3).
# It is never referenced elsewhere in this design — adopting it with no rules
# means anything that accidentally falls back to it gets zero access instead
# of the AWS-provided "allow all from self / all outbound" default.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-default-sg"
  })
}

# ---------------------------------------------------------------------------
# Security Groups (empty shells — all rules attached separately below to
# avoid a dependency cycle between eks_cluster <-> eks_node <-> alb, and to
# ensure AWS's implicit default allow-all-egress rule is not left in place)
# ---------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# --- EKS cluster SG rules ---------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node_https" {
  security_group_id            = aws_security_group.eks_cluster.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "API server access from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.common_tags
}

# --- EKS node SG rules -------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_all" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  description                  = "All traffic from EKS control plane"
  ip_protocol                  = "-1"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "node_self_all" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "Inter-node communication"
  ip_protocol                  = "-1"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "node_kubelet_from_cluster" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.eks_cluster.id
  description                  = "Kubelet API from control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "NodePort services from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.common_tags
}

# --- RDS SG rules -------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "rds_mysql_from_node" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "MySQL from EKS worker nodes only"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306

  tags = local.common_tags
}

# --- ALB SG rules ---------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_node_nodeport" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "To node NodePort target groups"
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "alb_healthcheck_to_node" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.eks_node.id
  description                  = "Health checks to nodes"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = local.common_tags
}
