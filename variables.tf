variable "desired_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 3
}

variable "min_size" {
  default = 1
}

variable "ami_type" {
  type = string
}

variable "instance_types" {
  type    = string
  default = ["t3.medium"]
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_account" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "flux_repository" {
  type     = string
  nullable = false
}

variable "flux_ui_password_hash" {
  type     = string
  nullable = false
}

variable "flux_ui_username" {
  type     = string
  nullable = false
}

variable "prometheus_workspace_id" {
  type = string
}

variable "grafana_workspace_id" {
  type = string
}

variable "aws_k8s_scraper_iam_role_arn" {
  type = string
}