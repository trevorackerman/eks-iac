terraform {
  required_version = ">= ???" # latest version???
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.34.0"
    }
    flux = {
      source = "fluxcd/flux"
    }
    github = {
      source   = "integrations/github"
      versdion = ">=5.18.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9.0"
    }
    kubectl {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}
