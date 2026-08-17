# ADR-0001: All-Public Subnet Design (No NAT Gateway)

**Last Updated:** 2026-08-17

**Purpose:** Records the decision to place all VPC resources (EKS nodes, RDS, ALB) in public subnets instead of using a private-subnet/NAT Gateway topology, and the compensating controls that make this safe enough for a learning environment.

**Status:** Accepted
**Date:** 2026-08-12

## Context

The platform runs in a single AWS account per student/learner, with a hard constraint on minimizing monthly cost (see `docs/technical-spec.md`). A conventional production VPC topology puts compute and data resources (EKS nodes, RDS) in private subnets, with a NAT Gateway providing outbound internet access and a public subnet reserved for internet-facing load balancers only.

A NAT Gateway costs a flat hourly rate plus per-GB data processing charges. Across two environments (dev + prod), each with its own NAT Gateway(s) for AZ redundancy, this adds an estimated **$35–65/month per student** — a significant fraction of the total budget for a project whose primary goal is Kubernetes/AWS learning, not production hosting.

VPC endpoints (for ECR, S3, Secrets Manager, etc.) are the usual companion to a private-subnet design, avoiding NAT data-processing charges for AWS API traffic — but they carry their own hourly cost per endpoint and are only worth it once private subnets are in play.

## Decision

Use a single **all-public subnet** design for both `dev` and `prod`:

- 2 public subnets per environment, one per AZ (`10.0.1.0/24` / `10.0.2.0/24` in dev; `10.1.1.0/24` / `10.1.2.0/24` in prod)
- 1 Internet Gateway per VPC, 1 public route table (`0.0.0.0/0` → IGW)
- **No NAT Gateway, no private subnets, no VPC endpoints**
- EKS nodes, RDS, and the ALB all run in the same public subnets (`map_public_ip_on_launch = true`)
- Security groups become the **primary access control boundary** in place of network-layer (subnet) isolation:
  - **RDS SG:** allows TCP `3306` from the EKS Node SG only — never `0.0.0.0/0`
  - **EKS Node SG:** ingress limited to the EKS Cluster SG (control plane), self (inter-node traffic), and the ALB SG on the NodePort range (`30000–32767`)
  - **EKS Cluster SG:** ingress on `443` from the EKS Node SG only
  - **ALB SG:** the only SG with direct internet ingress (`80`/`443` from `0.0.0.0/0`), matching its role as the public entry point

Each resource is reachable only from the specific security group one hop closer to the internet, so despite sharing one routable address space, RDS is unreachable from anywhere except EKS nodes, and EKS nodes are unreachable from the internet except through the ALB's NodePort range.

## Consequences

**Positive:**
- Saves ~$35–65/month per student by eliminating NAT Gateway and VPC endpoint costs
- Simpler network topology — one route table, no NAT/endpoint troubleshooting, easier for students to reason about
- Security groups still enforce a real, verifiable access chain (ALB → node → RDS), so there is no fully open lateral path

**Negative:**
- **Less defense-in-depth than a production topology.** There is no network-layer isolation between internet-facing and backend resources — every resource has a public IP and a routable path to `0.0.0.0/0`; security is enforced entirely by security group rules being correct, with no subnet-level backstop if a rule is ever misconfigured
- EKS nodes and RDS are directly addressable from the internet at the network layer (blocked only by SG rules, not by subnet routing)
- This pattern is **not recommended for production workloads outside this learning context** — a real production deployment should use private subnets for nodes/RDS with a NAT Gateway (or VPC endpoints) for egress, and this trade-off should be explicitly called out to students as a cost-vs-security decision, not a best practice to copy verbatim

## Related

- `docs/technical-spec.md` — VPC Network Design, Security Groups sections
- `terraform/modules/vpc/` — implementation
- Jira: E-2 Networking epic, PETPLAT-6
