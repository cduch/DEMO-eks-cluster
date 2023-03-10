provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}


data "terraform_remote_state" "hcpstack" {
  backend = "remote"

  config = {
    organization = "carstenduch"
    workspaces = {
      name = "HCP_Stack"
    }
  }
}

resource "aws_subnet" "ekssubnet1" {
  vpc_id     = data.terraform_remote_state.hcpstack.outputs.vpc_id
  cidr_block = "172.31.16.0/20"

  tags = {
    Name = "EKS-Subnet1"
  }
}
resource "aws_subnet" "ekssubnet2" {
  vpc_id     = data.terraform_remote_state.hcpstack.outputs.vpc_id
  cidr_block = "172.31.32.0/20"

  tags = {
    Name = "EKS-Subnet2"
  }
}
resource "aws_subnet" "ekssubnet3" {
  vpc_id     = data.terraform_remote_state.hcpstack.outputs.vpc_id
  cidr_block = "172.31.0.0/20"

  tags = {
    Name = "EKS-Subnet3"
  }
}


data "aws_subnets" "vpcsubnets" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.hcpstack.outputs.vpc_id]
  }
  depends_on = [
    aws_subnet.ekssubnet1,
    aws_subnet.ekssubnet2,
    aws_subnet.ekssubnet3
  ]
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.5.1"

  cluster_name    = var.cluster_name
  cluster_version = "1.24"

  vpc_id                         = data.terraform_remote_state.hcpstack.outputs.vpc_id
  subnet_ids                     = data.aws_subnets.vpcsubnets.ids
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "node-group-2"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.5.2-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}
