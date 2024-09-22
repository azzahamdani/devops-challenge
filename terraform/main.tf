provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

locals {
  name   = "ex-${basename(path.cwd)}"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16" # "192.168.0.0/16" # 
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Example     = local.name
    GithubRepo  = "terraform-aws-vpc"
    GithubOrg   = "terraform-aws-modules"
    Terraform   = "true"
    Environment = "dev"
  }
}

################################################################################
# VPC Module
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = "1"
  }

  tags = merge(local.tags, {
    "kubernetes.io/cluster/${local.name}" = "shared"
  })

}

################################################################################
# EC2 for Kubernetes Control Plane
################################################################################

# Policy for Putting Join Command to SSM parameter Store
resource "aws_iam_policy" "control_plane_ssm_put" {
  name        = "${local.name}-control-plane-ssm-put"
  path        = "/"
  description = "IAM policy for control plane to put parameters in SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/k8s/worker-join-command"
      }
    ]
  })
}

module "ec2_control_plane" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  name = "${local.name}-control-plane"

  instance_type = "t3.medium"
  ami                         = data.aws_ami.amazon_linux_2.id
  #ami                         = data.aws_ami.eks_optimized.id
  monitoring                  = true
  vpc_security_group_ids      = [module.security_group_control_plane.security_group_id]
  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false

  private_ip = "10.0.1.100" # "192.168.1.100" 

  user_data = base64encode(file("${path.module}/control-plane-userdata.sh"))
  # user_data = base64encode(templatefile("${path.module}/control-plane-cloud-init.yaml", {
  #   install_dependencies_script = file("${path.module}/control-plane-install-dependencies.sh")
  #   configure_control_plane_script = file("${path.module}/control-plane-configure.sh")
  # }))

  create_iam_instance_profile = true
  iam_role_name               = "${local.name}-control-plane-role"
  iam_role_description        = "IAM role for Kubernetes control plane EC2 instance"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEKSClusterPolicy             = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    AmazonEKSVPCResourceController     = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    ControlPlaneSSMPut                 = aws_iam_policy.control_plane_ssm_put.arn
  }

  tags = merge(local.tags, {
    Role = "Kubernetes Control Plane"
  })

  depends_on = [
    module.vpc,
    module.vpc_endpoints,
    module.security_group_control_plane
  ]
}

################################################################################
# AutoScaling Group for Worker Nodes
################################################################################

# Create an IAM policy for ALB Controller
resource "aws_iam_policy" "alb_controller" {
  name        = "${local.name}-alb-controller"
  path        = "/"
  description = "IAM policy for ALB Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" : "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })
}

module "asg_worker_nodes" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"

  name = "${local.name}-worker-nodes"

  min_size                  = 3
  max_size                  = 3
  desired_capacity          = 3
  wait_for_capacity_timeout = 0
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.vpc.private_subnets

  instance_type = "t3.medium"
  image_id      = data.aws_ami.amazon_linux_2.id
  # image_id = data.aws_ami.eks_optimized.id

  security_groups = [module.security_group_worker_nodes.security_group_id]

  create_iam_instance_profile = true
  iam_role_name               = "${local.name}-worker-node-role"
  iam_role_description        = "IAM role for Kubernetes worker nodes"
  iam_role_policies = {
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEKSWorkerNodePolicy          = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    AmazonEKS_CNI_Policy               = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    ALBControllerPolicy                = aws_iam_policy.alb_controller.arn
  }

  user_data = base64encode(file("${path.module}/worker-node-userdata.sh"))
  # user_data = base64encode(templatefile("${path.module}/worker-node-cloud-init.yaml", {
  #   install_dependencies_script = file("${path.module}/worker-node-install-dependencies.sh")
  #   configure_worker_script = file("${path.module}/worker-node-configure.sh")
  # }))

  tags = local.tags

  tag_specifications = [
    {
      resource_type = "instance"
      tags = merge(
        {
          "kubernetes.io/cluster/${local.name}" = "owned"
          "Role"                                = "Kubernetes Worker Node"
          "Name"                                = "${local.name}-worker-node"
        },
        local.tags
      )
    },
    {
      resource_type = "volume"
      tags = merge(
        {
          "kubernetes.io/cluster/${local.name}" = "owned"
        },
        local.tags
      )
    }
  ]

  # Ensure dependency on the control plane
  depends_on = [
    module.vpc,
    module.vpc_endpoints,
    module.security_group_worker_nodes,
    module.ec2_control_plane
  ]
}

################################################################################
# Security Group for Control Plane
################################################################################

module "security_group_control_plane" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-control-plane"
  description = "Security group for Kubernetes control plane"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      rule        = "https-443-tcp"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      rule        = "http-80-tcp"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      description = "DNS TCP"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      description = "DNS UDP"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      description = "Kubernetes API server"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 2379
      to_port     = 2380
      protocol    = "tcp"
      description = "etcd server client API"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 10250
      to_port     = 10252
      protocol    = "tcp"
      description = "Kubelet API, kube-scheduler, kube-controller-manager"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 30000
      to_port     = 32767
      protocol    = "tcp"
      description = "NodePort Services"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
  ]

  # Allow all traffic from worker nodes
  ingress_with_source_security_group_id = [
    {
      rule                     = "all-all"
      source_security_group_id = module.security_group_worker_nodes.security_group_id
    }
  ]

  # Allow all traffic between control plane nodes
  ingress_with_self = [
    {
      rule = "all-all"
    }
  ]

  # Egress rules
  egress_rules = ["all-all"]

  tags = local.tags
}

################################################################################
# Security Group for Worker Nodes
################################################################################

module "security_group_worker_nodes" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-worker-nodes"
  description = "Security group for Kubernetes worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress_with_cidr_blocks = [
    {
      from_port   = 53
      to_port     = 53
      protocol    = "tcp"
      description = "DNS TCP"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
    {
      from_port   = 53
      to_port     = 53
      protocol    = "udp"
      description = "DNS UDP"
      cidr_blocks = module.vpc.vpc_cidr_block
    }
  ]

  ingress_with_source_security_group_id = [
    {
      rule                     = "all-all"
      source_security_group_id = module.security_group_control_plane.security_group_id
    }
  ]

  ingress_with_self = [
    {
      rule = "all-all"
    }
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

################################################################################
# VPC Endpoints for SSM
################################################################################

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    },
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    },
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
    }
  }

  create_security_group      = true
  security_group_name_prefix = "${local.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from private subnets"
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# data "aws_ami" "eks_optimized" {
#   most_recent = true
#   owners      = ["amazon"]

#   filter {
#     name   = "name"
#     values = ["amazon-eks-node-1.30-v*"] # Replace 1.27 with your desired Kubernetes version
#   }
# }