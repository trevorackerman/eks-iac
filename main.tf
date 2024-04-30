data "aws_availability_zones" "available" {}

resource "aws_ec2_tag" "internal-elb" {
  for_each    = toset(var.subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

resource "aws_ec2_tag" "cluster" {
  for_each    = toset(var.subnet_ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${module.eks.cluster_name}"
  value       = "shared"
}

resource "aws_ec2_tag" "karpenter_subnets" {
  for_each    = toset(var.subnet_ids)
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = "karpenter"
}

resource "aws_ec2_tag" "karpenter_security_groups" {
  for_each    = toset([var.security_group_id])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = "karpenter"
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = var.cluster_name
  cluster_version = "1.28"
  vpc_id          = var.vpc_id
  subnet_ids      = var.subnet_ids

  cluster_endpoint_public_access = false
  cluster_security_group_id      = var.security_group_id
  create_cluster_security_group  = false
  create_node_security_group     = false
  node_security_group_id         = var.security_group_id

  iam_role_name            = "${var.cluster_name}-eks"
  iam_role_use_name_prefix = false
  # iam_role_permissions_boundary = "arn:aws:iam::${var.aws_account}:policy/infra/PleaseCreateABoundaryAndChangeThis"

  cluster_encryption_policy_name         = "${var.cluster_name}-eks-encryption"
  cluster_security_group_use_name_prefix = false

  node_security_group_name            = "${var.cluster_name}-eks-node"
  node_security_group_use_name_prefix = false

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${var.aws_account}:role/${terraform.workspace}-${var.cluster_name}-karpenter-node"
      username = "system:node:{{EC2PrivateDNSName}}"
      groups = [
        "system:bootstrappers",
        "system:nodes",
      ]
    },
    {
      # managed prometheus with aws
      # TODO this is hard to automate at the moment, trying to recreate the aws-auth configmap has been a big footgun
      rolearn  = "var.kubernetes_scraper_iam_role_arn"
      username = "aps-collector-user"
      groups = [
        "system:master",
      ]
    }
  ]

  eks_managed_node_group_defaults = {
    ami_type = var.ami_type
  }

  eks_managed_node_groups = {
    default = {
      name                      = var.default_node_group_name
      use_name_prefix           = false
      iam_role_name             = "${var.cluster_name}-eks-node-group"
      iam_role_user_name_prefix = false
      #iam_role_permissions_boundary 
      iam_role_additional_policies = {
        policy = "awn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
      instance_types = var.instance_types
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size
    }
  }

  # Required for using Kubecost
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }
}

module "eks_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.15"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_vefrsion
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_cert_manager = true
  cert_manager = {
    role_name = "${module.eks.cluster_name}-cert-manager"
    #  role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix = false
    policy_name          = "${module.eks.cluster_name}-cert-manager"
  }

  enable_external_secrets = true
  external_secrets_manager_arns = [
    "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account}:secret:${terraform.workspace}/*"
  ]
  external_secrets = {
    role_name                     = "${module.eks.cluster_name}-external-secrets"
    role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix          = false
    policy_name                   = "${module.eks.cluster_name}-external-secrets"
  }

  enable_metrics_server = true
  metrics_server = {
    role_name                     = "${module.eks.cluster_name}-metrics-server"
    role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix          = false
    policy_name                   = "${module.eks.cluster_name}-metrics-server"
  }

  enable_karpenter                           = true
  karpenter_enable_instance_profile_creation = true
  karpenter {
    role_name                     = "${module.eks.cluster_name}-karpenter"
    role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix          = false
    policy_name                   = "${module.eks.cluster_name}-karpenter"
  }

  karpenter_node = {
    iam_role_name                 = "${module.eks.cluster_name}-karpenter"
    iam_role_name_use_prefix      = false
    iam_role_permissions_boundary = "arn...policy"
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    role_name                     = "${module.eks.cluster_name}-karpenter"
    role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix          = false
    policy_name                   = "${module.eks.cluster_name}-karpenter"
  }

  enable_external_dns = true
  external_dns = {
    role_name                     = "${module.eks.cluster_name}-karpenter"
    role_permissions_boundary_arn = "arn...policy"
    role_name_use_prefix          = false
    policy_name                   = "${module.eks.cluster_name}-karpenter"
    values = [
      "extraArgs: [--zone-id-filter=SOMEZONEID]"
    ]
  }

  external_dns_route53_zone_arns = ["arn:aws:route53::hostedzone/SOMEZONEID"]
}

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: "${module.infrastructure_eks.cluster_name}"
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.aws_region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secrets-sa
                namespace: external-secrets
  YAML
  depends_on = [
    module.eks_addons
  ]
}


resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          requirements:
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["2"]
          nodeClassRef:
            name: default
          limits:
            cpu: 1000
          disruption:
            consolidationPolicy: WhenUnderutilized
            expireAfter: 720h # 30 days
  YAML
  depends_on = [
    module.eks_addons
  ]
}

resource "kubectl_manifest" "ec2_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: AL2
      role: "${module.eks.cluster_name}-karpenter-node"
      instanceProfile: "${module.eks.cluster_name}-karpenter-node"
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "karpenter"
      securityGroupSelectorTerms:
        - tags:
          karpenter.sh/discovery: "karpenter"
      tags:
        Name: ${module.eks.cluster_name}-karpenter
  YAML
  depends_on = [
    module.eks_addons
  ]
}
