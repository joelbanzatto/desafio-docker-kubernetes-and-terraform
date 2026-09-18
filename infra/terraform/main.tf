provider "kind" {}

resource "kind_cluster" "default" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.default.endpoint
  client_certificate     = kind_cluster.default.client_certificate
  client_key             = kind_cluster.default.client_key
  cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.default.endpoint
    client_certificate     = kind_cluster.default.client_certificate
    client_key             = kind_cluster.default.client_key
    cluster_ca_certificate = kind_cluster.default.cluster_ca_certificate
  }
}

# Hashes de código-fonte disparam rebuild/reload das imagens só quando o
# conteúdo muda de verdade — é isso que garante o "apply 2x -> 0 changed".
locals {
  repo_root = "${path.module}/../.."

  api_source_hash = sha1(join("", [
    for f in sort(fileset("${local.repo_root}/app/api", "**")) :
    filesha1("${local.repo_root}/app/api/${f}")
  ]))
  web_source_hash = sha1(join("", [
    for f in sort(fileset("${local.repo_root}/app/web", "**")) :
    filesha1("${local.repo_root}/app/web/${f}")
  ]))
  api_dockerfile_hash = filesha1("${local.repo_root}/app/docker/api.Dockerfile")
  web_dockerfile_hash = filesha1("${local.repo_root}/app/docker/web.Dockerfile")
}

resource "null_resource" "build_api_image" {
  triggers = {
    source_hash     = local.api_source_hash
    dockerfile_hash = local.api_dockerfile_hash
    image           = "${var.api_image_repository}:${var.api_image_tag}"
  }

  provisioner "local-exec" {
    command = "docker build -f ${local.repo_root}/app/docker/api.Dockerfile -t ${var.api_image_repository}:${var.api_image_tag} ${local.repo_root}"
  }
}

resource "null_resource" "build_web_image" {
  triggers = {
    source_hash     = local.web_source_hash
    dockerfile_hash = local.web_dockerfile_hash
    image           = "${var.web_image_repository}:${var.web_image_tag}"
  }

  provisioner "local-exec" {
    command = "docker build -f ${local.repo_root}/app/docker/web.Dockerfile -t ${var.web_image_repository}:${var.web_image_tag} ${local.repo_root}"
  }
}

resource "null_resource" "load_api_image" {
  triggers = {
    cluster     = kind_cluster.default.id
    source_hash = local.api_source_hash
    image       = "${var.api_image_repository}:${var.api_image_tag}"
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.api_image_repository}:${var.api_image_tag} --name ${var.cluster_name}"
  }

  depends_on = [kind_cluster.default, null_resource.build_api_image]
}

resource "null_resource" "load_web_image" {
  triggers = {
    cluster     = kind_cluster.default.id
    source_hash = local.web_source_hash
    image       = "${var.web_image_repository}:${var.web_image_tag}"
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.web_image_repository}:${var.web_image_tag} --name ${var.cluster_name}"
  }

  depends_on = [kind_cluster.default, null_resource.build_web_image]
}

resource "kubernetes_namespace" "mural" {
  metadata {
    name = var.namespace
  }

  depends_on = [kind_cluster.default]
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  namespace        = "traefik"
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "ports.web.hostPort"
    value = "80"
  }
  set {
    name  = "ports.websecure.hostPort"
    value = "443"
  }
  set {
    name  = "nodeSelector.ingress-ready"
    value = "true"
    type  = "string"
  }
  set {
    name  = "service.spec.type"
    value = "ClusterIP"
  }

  depends_on = [kind_cluster.default]
}

resource "helm_release" "mural" {
  name      = "mural"
  chart     = "${local.repo_root}/infra/helm/mural"
  namespace = var.namespace
  # wait=false porque a StatefulSet/Deployment da API nunca "fica pronta"
  # antes do hook post-install (migração) rodar — e Helm só executa hooks
  # post-install DEPOIS de esperar os recursos normais, se wait=true. Com
  # wait=false o Helm ainda aguarda o Job do hook terminar (isso é sempre
  # bloqueante, independente da flag), só não trava esperando a API.
  wait    = false
  timeout = 300

  set {
    name  = "image.api.repository"
    value = var.api_image_repository
  }
  set {
    name  = "image.api.tag"
    value = var.api_image_tag
  }
  set {
    name  = "image.web.repository"
    value = var.web_image_repository
  }
  set {
    name  = "image.web.tag"
    value = var.web_image_tag
  }
  set {
    name  = "ingress.host"
    value = var.ingress_host
  }
  set {
    name  = "ingress.className"
    value = "traefik"
  }
  set {
    name  = "postgres.user"
    value = var.postgres_user
  }
  set_sensitive {
    name  = "postgres.password"
    value = var.postgres_password
  }
  set {
    name  = "postgres.database"
    value = var.postgres_database
  }

  depends_on = [
    kubernetes_namespace.mural,
    helm_release.traefik,
    null_resource.load_api_image,
    null_resource.load_web_image,
  ]
}
