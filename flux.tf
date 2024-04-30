resource "kubectl_manifest" "flux_system_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: flux-system
  YAML
}

resource "kubectl_manifest" "flux_system_secret" {
  yamL_body = <<-YAML
    apiVersion: external-secrets.io/vlbeta1
    kind: ExternalSecret 
    metadata:
      name: flux-system
      namespace: flux-system 
    spec:
      dataFrom:
        - extract:
          key: ${terraform.workspace}/${var.domain}/flux-system 
      secretStoreRef:
        name: Stmodule.infrastructure_eks.cluster_name} 
        kind: ClusterSecretStore
      target:
        name: flux-system 
      refreshInterval: "5m"
  YAML

  depends_on = [
    module.eks_addons,
    kubectl_manifest.flux_system_namespace,
    kubectl_manifest.cluster_secret_store,
  ]
}

resource "kubectl_manifest" "devops_namespace" {
  yaml_body = <<-YAML
    apiVersion: v1 
    kind: Namespace 
    metadata:
      name: flux-acmedevops
  YAML
}

# resource "flux_bootstrap git" "this" {
#   disable_ secret_creation = true
#   https://registry.terraform.io/providers/fluxcd/flux/latest/docs/resource
#   components_extra = (
#     # https://ataiva.com/how-to-write-if-else-statements-in-terraform/
#     (terraform workspace - "community" || terraform.workspace = "stagehand")
#     ["image-reflector-controller", "image-automation-controller"] : []
#   )
#   path = "clusters/$(module. infrastructure_eks.cluster_name}"
#   depends_on = [
#     kubectl_manifest.flux_system_secret, 
#     Kubectl_manifest.devops_namespace,
#     kubectl_manifest.flux_system_namespace,
#   ]
# }

# resource "helm_release" "flux_dashboard" {
#   name = "flux-dashboard"
#   namespace = "flux-system"
#   repository = "oci://ghcr.i/weaveworks/charts"
#   chart = "weave-gitops"
#   set {
#     name = "LogLevel"
#     value = "debug"
#   }
#
#   set {
#     name= "adminUser.create"
#     value = true
#   }
# 
#   set {
#     name = "adminUser.passwordHash"
#     value = var.flux_ui_password_hash
#   }
#
#   depends_on = [
#     module.eks,
#     flux_bootstrap_git.this,
#     kubectl_manifest.flux_system_namespace,
#     kubectl_manifest.flux_system_secret,
#     Kubectl_manifest.ec2_node_class,
#     kubectl_manifest.karpenter_node_pool
#   ]
# }

# resource "kubectl_manifest" "flux ui ingress" {
#   yaml.body= <<-YAML
#     apiVersion: networking.k8s.10/vl
#     kind: Ingress
#     metadata:
#       annotations:
#         alb.ingress.kubernetes.io/group.name: ${terraform.workspace}
#         alb.ingress.kubernetes.io/load-balancer-name: ${terraform.workspace)
#         alb.ingress.kubernetes.io/scheme: internal
#         alb.ingress.kubernetes.io/target-type: ip
#         alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:${var.aws_region}
#         alb.ingress.kubernetes.io/listen-ports: '|/{"HTTP": 80}, {"HTTPS" :44 alb.ingress.kubernetes.io/ssl-redirect: ' 443'
#         alb.ingress.kubernetes.io/backend-protocol: HTTPS
#       name: flux-dashboard-weave-gitops
#       namespace: flux-system
#     spec:
#       ingressClassName: alb
#       rules:
#       - host: flux-${var.domain)-$(terraform.workspace}.internal.acme.com
#         http:
#           paths:
#           - backend:
#               service:
#                 name: flux-dashboard-weave-gitops
#                 port:
#                   number: 9001
#             path: /
#             pathType: Prefix
#   YAML
#   depends_on = [
#     helm_release.flux_dashboard
#   ]
# }
