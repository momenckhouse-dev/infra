data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  cluster_name = "${var.project_name}-eks"
  account_id   = data.aws_caller_identity.current.account_id

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    Repo      = "${var.github_org}/${var.infra_repo}"
  }
}

# Layout inside the /16:
#   private (nodes, pods)  10.x.0.0/20,  10.x.16.0/20, 10.x.32.0/20
#   public  (ALB, NAT)     10.x.48.0/24, 10.x.49.0/24, 10.x.50.0/24
#   intra   (EKS ENIs)     10.x.52.0/24, 10.x.53.0/24, 10.x.54.0/24
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 48 + i)]
  intra_subnets   = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, 52 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = 30

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.13"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${var.project_name}-s3" }
    }
  }
}
