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

  backend "remote" {
    organization = "your-org"  # <--- ЗАМЕНИТЕ НА ВАШУ ОРГАНИЗАЦИЮ В TF CLOUD
    workspaces {
      name = "k3s-vps-setup" # <--- ЗАМЕНИТЕ НА ИМЯ ВАШЕГО WORKSPACE
    }
  }
}

provider "kubernetes" {
  config_path = "kubeconfig.yaml" # <--- Путь к kubeconfig.yaml на Jenkins-контроллере (в рабочей директории пайплайна)
}

provider "helm" {
  kubernetes {
    config_path = "kubeconfig.yaml" # <--- Путь к kubeconfig.yaml на Jenkins-контроллере (в рабочей директории пайплайна)
  }
}