variable "region" {
  description = "AWS region for the platform."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix for every resource name."
  type        = string
  default     = "secure-platform"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must be a /16 so the subnet math in vpc.tf holds."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread subnets and nodes across."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway (cheaper, lab use) instead of one per AZ (production)."
  type        = bool
  default     = false
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint, e.g. your IP as [\"203.0.113.10/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one CIDR and never 0.0.0.0/0; the Kubernetes API must not be open to the internet."
  }
}

variable "cluster_admin_principal_arns" {
  description = "IAM role/user ARNs granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "ecr_repositories" {
  description = "ECR repositories to create (one per service)."
  type        = list(string)
  default     = ["secure-event-api"]
}

variable "github_org" {
  description = "GitHub organisation or user that owns the repositories."
  type        = string
}

variable "app_repo" {
  description = "Application source repository allowed to push images."
  type        = string
  default     = "app-source"
}

variable "infra_repo" {
  description = "Infrastructure repository allowed to plan/apply Terraform."
  type        = string
  default     = "infra"
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub user/org. Set it (with github_repo_ids) when GitHub issues immutable OIDC subjects like repo:org@123/name@456."
  type        = string
  default     = ""
}

variable "github_repo_ids" {
  description = "Numeric GitHub repository IDs keyed by repo name, used for immutable OIDC subjects."
  type        = map(string)
  default     = {}
}

variable "create_github_oidc_provider" {
  description = "Set false if the account already has the token.actions.githubusercontent.com provider."
  type        = bool
  default     = true
}

variable "terraform_state_bucket" {
  description = "S3 bucket holding Terraform state (read access is granted to the plan role)."
  type        = string
}

variable "terraform_apply_policy_arns" {
  description = "Policies attached to the apply role. Bootstrapping EKS/VPC/IAM needs broad rights; the role is only assumable from the approval-protected GitHub environment."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}
