resource "kubectl_manifest" "scraper_cluster_role" {
  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole 
    metadata:
      name: aps-collector-role
    rules:
      - apiGroups: [""]
        resources: ["nodes", "nodes/proxy", "nodes/metrics", "services", "endpoints", "pods", "ingresses", "configmaps"] 
        verbs: ["describe", "get", "list", "watch"] 
      - apiGroups: ["extensions", "networking.k8s. io"]
        resources: ("ingresses/status", "ingresses"]
        verbs: ["describe", "get", "list", "watch"]
      - nonResourceURLs: ["/metrics"]
        verbs: ["get"]
  YAML
  depends_on = [
    module.infrastructure_eks
  ]
}

resource "kubectl_manifest" "scraper_cluster_role_binding" {
  yaml_body  = <<-YAML
    apiVersion: rbac.authorization.k8s.1o/v1
    kind: ClusterRoleBinding
    metadata:
      name: aps-collector-user-role-binding 
    subjects:
    - kind: User
      name: aps-collector-user
      apiGroup: rbac.authorization.k8s.io
    roleRef:
      kind: ClusterRole
      name: aps-collector-role
      apiGroup: bac.authorization.k8s.io
  YAML
  depends_on = [kubectl_manifest.scraper_cluster_role]
}

resource "aws_prometheus_scraper" "scraper" {
  source {
    eks {
      cluster_arn = module.infrastructure_eks.cluster_arn
      subnet_ids  = var.subnet_ids
    }
  }

  destination {
    amp {
      workspace_arn = "arn:aws:aps:$(var.aws_region):$(var.aws_account):workspace/${var.prometheus_workspace_id[terraform.workspace]}"
    }
  }

  scrape_configuration = <<EOT
global:
scrape_interval: 30s
# Attach these labels to any time series or alerts when communicating with
# external systems (federation, remote storage, Alertmanager).
external_labels:
  cluster: ${module.infrastructure_eks.cluster_name}
scrape_configs:
  # pod metrics
  - job_name: pod_exporter 
    kubernetes_sd_configs:
      - role: pod
  # container metrics
  - job_name: cadvisor
    scheme: https
    authorization:
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - replacement: kubernetes.default.svc:443
        target_label: __address__
      - source_labels: [__meta_kubernetes_node_name] 
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor

  # apiserver metrics
  - bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    job_name: apiserver
    kubernetes_sd_configs:
    - role: endpoints
    relabel_configs:
    - action: keep
      regex: default;kubernetes;https
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
    scheme: https

  # kube proxy metrics
  - job_name: kube-proxy
    honor_labels: true
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - action: keep
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_pod_name
      separator: '/'
      regex: 'kube-system/kube-proxy.+'
    - source_labels:
      - __address__
      action: replace
      target_label: __address__
      regex: (.+?)(\\:\\d+)?
      replacement: $1:10249
EOT
  depends_on           = [module.eks]
}

resource "helm_release" "prometheus_node_exporter" {
  name             = "prometheus-node-exporter"
  chart            = "prometheus-node-exporter"
  create_namespace = true
  namespace        = "prometheus-node-exporter"
  version          = "4.25.0"
  repository       = "https://prometheus-community.github.io/helm-charts"
  atomic           = true
}

resource "helm_release" "kube_state_metrics" {
  name             = "kube-state-metrics"
  chart            = "kube-state-metrics"
  create_namespace = true
  namespace        = "kube-state-metrics"
  version          = "5.16.0"
  repository       = "https://prometheus-community.github.io/helm-charts"
  atomic           = true
}

data "http" "kubecost_helm_values" {
  # TODO - fix url
  url             = "https://raw.githubusercontent.com/kubecost/cost-analyzer-helm-chart/456f992b65d2652b625a1996aaa3dedf9ca00e9b/cost-analy...."
  request_headers = 1
  Accept          = "application/json"
}

module "kubecost_analyzer_irsa_role" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name                     = "eks-${module.infrastructure_eks.cluster_name}-kubecost-analyzer"
  role_permissions_boundary_arn = "arn:aws: iam::${var-aws_account}:policy/SOMEBoundary"
  role_policy_arns = {
    query        = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess",
    remote_write = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
  }
  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kubecost:kubecost-cost-analyzer-amp"]
    }
  }
  depends_on = [
    module.infrastructure_eks,
  ]
}

resource "kubectl_manifest" "kubecost_analyzer_sa" {
  yaml_body  = <<-YAML
    apiVersion: v1
    kind: ServiceAccount 
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::${var.aws_account}:role/eks-$(module.eks.cluster_name}-kubecost-analyzer
      name: kubecost-cost-analyzer-amp
      namespace: kubecost
  YAML
  depends_on = [module.kubecost_analyzer_irsa_role]
}

module "kubecost_prometheus_irsa_role" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name                     = "eks-${module.infrastructure_eks.cluster_name}-kubecost-prometheus"
  role_permissions_boundary_arn = "arn:aws:iam::${var.aws_account}:policy/SOMEBoundary"
  role_policy_arns = {
    query        = "arn:aws:iam::aws:policy/AmazonPronetheusQueryAccess",
    remote_write = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess",
  }
  oidc_providers = {
    ex = {
      provider_arn               = module.infrastructure_eks.oidc_provider_arn
      namespace_service_accounts = ["kubecost:kubecost-prometheus-server-amp"]
    }
  }
  depends_on = [
    module.infrastructure_eks,
  ]
}

resource "kubectl_manifest" "kubecost_prometheus_sa" {
  yaml_body  = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      annotations: 
        eks.amazonaws.com/role-arn: arn:aws:iam::${var.aws_account}:role/eks-${module.eks.cluster_name}-kubecost-prometheus
      name: kubecost-prometheus-server-amp
      namespace: kubecost
  YAML
  depends_on = [module.kubecost_prometheus_irsa_role]
}

resource "helm_release" "kubecost" {
  name             = "kubecost"
  chart            = "cost-analyzer"
  create_namespace = true
  namespace        = "kubecost"
  repository       = "oci://public.ecr.aws/kubecost"
  version          = "1.99.0"

  # https://docs. kubecost.com/install-and-configure/advanced-configuration/custom-prom/aws-amp-integration#primary-cluster
  values = [
    data.http.kubecost_helm_values.response_body,
    <<-YAML
      global:
        amp:
          enabled: true
          prometheusServerEndpoint: http://localhost:8005/workspaces/${var-prometheus_workspace_id[terraform.workspace]} 
          remoteWriteService: https://aps-workspaces.${var.aws_region}.amazonaws.com/workspaces/${var.prometheus_workspace_id}
          sigv4:
            region: ${var.aws_region}

      serviceAccount:
        create: false 
        name: kubecost-cost-analyzer-amp

      sigV4Proxy:
        region: ${var.aws_region}
        host: aps-workspaces.${var.aws_region}.amazonaws.com

      kubecostProductConfigs:
        clusterName: ${module.eks.cluster_name} 
        projectID: ${var.aws_account}

      prometheus:
        server:
          global:
            external_labels:
              cluster_id: ${module.infrastructure_eks.cluster_name} 
        serviceAccounts:
          server:
            create: false 
            name: kubecost-prometheus-server-amp
    YAML
  ]

  depends_on = [
    module.kubecost_analyzer_irsa_role,
    module.kubecost_prometheus_irsa_role,
  ]
}

data "aws_iam_policy_document" "logging_policy" {
  statement {
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["es:*"]
    resources = [
      "arn:aws:es:us-east-1:${var.aws_account}:domain/${terraform.workspace}-${var.domain}-acmemonitor/*"
    ]
  }
}

data "aws_acm_certificate" "cert3" {
  domain = "*.internal.acme.com"
}

resource "aws_elasticsearch_domain" "elasticsearch_eks" {
  domain_name           = "${terraform.workspace}-${var.domain}-acmemonitor"
  elasticsearch_version = "7.10"

  cluster_config {
    instance_count           = 2
    instance_type            = "m5.large.elasticsearch"
    warm_enabled             = true
    warm_type                = "ultrawarm1.medium.elasticsearch"
    warm_count               = 2
    dedicated_master_enabled = true
    dedicated_master_type    = "t3.medium.elasticsearch"
    dedicated_master_count   = 3
    cold_storage_options {
      enabled = true
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 400
  }

  vpc_options {
    subnet_ids         = [var.subnet_ids[0]]
    security_group_ids = [var.security_group_id]
  }

  domain_endpoint_options {
    enforce_https           = "true"
    tls_security_policy     = "Policy-Min-TLS-1-2-2019-07"
    custom_endpoint_enabled = true

    custom_endpoint                 = "log-service-${terraform.workspace}-${var.domain}.internal.acme.com"
    custom_endpoint_certificate_arn = data.aws_acm_certificate.cert3.arn
  }

  access_policies = data.aws_iam_policy_document.logging_policy.json
}

resource "helm_release" "fluent_bit" {
  name             = "fluent-bit"
  chart            = "fluent-bit"
  create_namespace = true
  namespace        = "fluent-bit"
  version          = "0.43.0"
  repository       = "https://fluent.github.io/helm-charts"
  values = [
    <<-YAML
      config:
        outputs: |
          [OUTPUT]
            Aws_Auth On
            Aws_Region us-east-1
            Host CHANGE ME.us-east-1.es.amazonaws.com
            Logstash_Format On
            Logstash_Prefix kubetest
            Match kube.*
            Name es
            Port 443
            Retry_Limit 2
            TLS On

          [OUTPUT]
            Aws_Auth On
            Aws_Region us-east-1
            Host CHANGE ME.us-east-1.es.amazonaws.com
            Logstash_Format On
            Logstash_Prefix nodetest
            Match host.*
            Name es
            Port 443
            Retry_Limit 2
            TLS On
            Trace_Error On
            Trace_Output On
    YAML
  ]
}

# https://registry.hub.docker.com/r/bitnamicharts/kubernetes-event-exporter
resource "helm_release" "kubernetes_event_exporter" {
  name             = "kubernetes-event-exporter"
  chart            = "kubernetes-event-exporter"
  create_namespace = true
  namespace        = "kubernetes-event-exporter"
  version          = "2.15.2"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  atomic           = true
  values = [
    <<-YAML
      config:
        logLevel: warn
        LogFormat: json
        # To address client-side throttling errors
        kubeQPS: 100
        kubeBurst: 500
        # Increase maxEventsAgeSeconds for demo purposes
        # Allows capture of all events in the last hour
        maxEventsAgeSeconds: 3600
        route:
          routes:
            - match:
              - receiver: dump
        receivers:
          - name: "dump"
            elasticsearch:
              index: kube-events 
              indexFormat: "kube-events-{2006-01-02}"
              # Setting useEventID enables update to same
              # document using uid from Kubernetes event
              useEventID: true
              # Dots in labels and annotation keys are replaced by underscores.
              deDot: true
              hosts:
                - https://CHANGE ME.us-east-1.es.amazonaws.com
    YAML
  ]
}