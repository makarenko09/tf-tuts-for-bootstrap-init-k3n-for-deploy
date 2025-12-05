resource "null_resource" "prepare_vps" {
  connection {
    type        = "ssh"
    host        = var.vps_ip
    user        = "dev" # <--- ИЗМЕНИТЕ ПРИ НЕОБХОДИМОСТИ
    private_key = file(var.ssh_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt upgrade -y",
      "sudo apt install -y curl wget git ufw",
      "sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab",
      "sudo ufw default deny incoming && sudo ufw default allow outgoing",
      "sudo ufw allow 22/tcp && sudo ufw allow 6443/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp",
      "sudo ufw --force enable"
    ]
  }
}

resource "null_resource" "install_k3s" {
  depends_on = [null_resource.prepare_vps]

  connection {
    type        = "ssh"
    host        = var.vps_ip
    user        = "dev" # <--- ИЗМЕНИТЕ ПРИ НЕОБХОДИМОСТИ
    private_key = file(var.ssh_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--write-kubeconfig-mode=640 --tls-san=${var.vps_ip} --disable=servicelb\" sh -s -",
      "sudo cp /etc/rancher/k3s/k3s.yaml /home/dev/.kube/config", # <--- ИЗМЕНИТЕ 'dev' НА ВАШЕГО ПОЛЬЗОВАТЕЛЯ, ЕСЛИ ОТЛИЧАЕТСЯ
      "sudo chown dev:dev /home/dev/.kube/config" # <--- ИЗМЕНИТЕ 'dev' НА ВАШЕГО ПОЛЬЗОВАТЕЛЯ, ЕСЛИ ОТЛИЧАЕТСЯ
    ]
  }

  provisioner "local-exec" {
    command = "scp dev@${var.vps_ip}:/home/dev/.kube/config kubeconfig.yaml" # <--- ИЗМЕНИТЕ 'dev' НА ВАШЕГО ПОЛЬЗОВАТЕЛЯ, ЕСЛИ ОТЛИЧАЕТСЯ
  }
}

resource "helm_release" "cert_manager" {
  depends_on = [null_resource.install_k3s]
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_manifest" "cluster_issuer" {
  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = { name = "letsencrypt" }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory" # <--- ИСПОЛЬЗУЙТЕ https://acme-staging-v02.api.letsencrypt.org/directory ДЛЯ ТЕСТИРОВАНИЯ
        email  = "your@email.com" # <--- ЗАМЕНИТЕ НА ВАШ РЕАЛЬНЫЙ EMAIL
        privateKeySecretRef = { name = "letsencrypt" }
        solvers = [{
          http01 = { ingress = { class = "traefik" } }
        }]
      }
    }
  }
}

module "flux" {
  source  = "fluxcd/flux/kubernetes"
  version = "1.7.3"
  github_owner      = split("/", var.github_repo)[0]
  github_repository = split("/", var.github_repo)[1]
  branch = "main"
  target_path = "clusters/production"
  github_token = var.github_token
}

resource "kubernetes_namespace" "app_prod" {
  depends_on = [null_resource.install_k3s]
  metadata { name = "app-prod" }
}

resource "kubernetes_role" "app_prod_manager" {
  depends_on = [kubernetes_namespace.app_prod]
  metadata {
    name      = "app-prod-manager"
    namespace = "app-prod"
  }
  rule {
    api_groups = ["", "apps", "networking.k8s.io"]
    resources  = ["deployments", "services", "ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "flux_binding" {
  depends_on = [kubernetes_role.app_prod_manager]
  metadata {
    name      = "flux-to-app-prod"
    namespace = "app-prod"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "app-prod-manager"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "kustomize-controller"
    namespace = "flux-system"
  }
}