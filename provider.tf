# Определяет требуемые провайдеры и их версии — это инициализирует plugins при terraform init.
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
  # Конфигурация backend: remote для Terraform Cloud — state хранится удаленно, token из env TF_TOKEN_app_terraform_io (из Jenkins creds).
  backend "remote" {
    organization = "your-org"  # Замените на вашу organization из Terraform Cloud (User > Organizations > Create or select).
    workspaces {
      name = "k3s-vps-setup"  # Замените на имя вашего workspace из Terraform Cloud (Workspaces > Create workspace).
    }
  }
}

# Provider kubernetes: подключается к k3s с локальным kubeconfig.
provider "kubernetes" {
  config_path = "kubeconfig.yaml"  # Путь к скачанному kubeconfig.
}

# Provider helm: использует тот же kubeconfig для Helm.
provider "helm" {
  kubernetes {
    config_path = "kubeconfig.yaml"
  }
}