variable "cluster_name" {
  description = "Nome do cluster kind"
  type        = string
  default     = "mural"
}

variable "namespace" {
  description = "Namespace onde o chart do Mural é instalado"
  type        = string
  default     = "mural"
}

variable "ingress_host" {
  description = "Host usado pelo Ingress (resolve para 127.0.0.1 via *.localtest.me)"
  type        = string
  default     = "mural.localtest.me"
}

variable "api_image_repository" {
  type    = string
  default = "mural-api"
}

variable "api_image_tag" {
  type    = string
  default = "local"
}

variable "web_image_repository" {
  type    = string
  default = "mural-web"
}

variable "web_image_tag" {
  type    = string
  default = "local"
}

variable "postgres_user" {
  type    = string
  default = "mural"
}

variable "postgres_password" {
  description = "Senha do Postgres. Sobrescreva via TF_VAR_postgres_password ou -var em produção; o default aqui existe só para o desafio."
  type        = string
  default     = "mural"
  sensitive   = true
}

variable "postgres_database" {
  type    = string
  default = "mural"
}
