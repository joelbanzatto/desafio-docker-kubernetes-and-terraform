output "cluster_name" {
  value = kind_cluster.default.name
}

output "kubeconfig_path" {
  value = kind_cluster.default.kubeconfig_path
}

output "app_url" {
  value = "http://${var.ingress_host}"
}
