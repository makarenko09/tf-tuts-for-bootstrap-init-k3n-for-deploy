# Null resource для подготовки VPS — не создает реальный ресурс, но запускает provisioners.
resource "null_resource" "prepare_vps" {
  # Connection блок: определяет SSH подключение к VPS — использует user "dev" и ключ.
  connection {
    type        = "ssh"
    host        = var.vps_ip
    user        = "dev"
    private_key = file(var.ssh_key_path)  # Читает приватный ключ из файла (без хранения в state).
  }
  # Provisioner remote-exec: выполняет команды на VPS по SSH — подготавливает ОС.
  provisioner "remote-exec" {
    inline = [
      "sudo apt update && sudo apt upgrade -y",  # Обновляет пакеты для безопасности.
      "sudo apt install -y curl wget git ufw",  # Устанавливает утилиты (curl для k3s, ufw для firewall).
      "sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab",  # Отключает swap (требование K8s).
      "sudo ufw default deny incoming && sudo ufw default allow outgoing",  # Базовые правила UFW.
      "sudo ufw allow 22/tcp && sudo ufw allow 6443/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp",  # Открывает порты для SSH, K8s API, HTTP/HTTPS.
      "sudo ufw --force enable"  # Активирует firewall.
    ]
  }
}

# Null resource для установки k3s — зависит от prepare_vps (sequential execution).
resource "null_resource" "install_k3s" {
  depends_on = [null_resource.prepare_vps]  # Ждет завершения подготовки.
  connection {  # Аналогичный SSH connection.
    type        = "ssh"
    host        = var.vps_ip
    user        = "dev"
    private_key = file(var.ssh_key_path)
  }
  provisioner "remote-exec" {  # Устанавливает k3s с флагами для security/resources.
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--write-kubeconfig-mode=640 --tls-san=${var.vps_ip} --disable=servicelb\" sh -s -",  # Установка k3s: secure kubeconfig, TLS SAN для IP, отключение lb для low-res.
      "sudo cp /etc/rancher/k3s/k3s.yaml /home/dev/.kube/config",  # Копирует kubeconfig для user dev.
      "sudo chown dev:dev /home/dev/.kube/config"  # Устанавливает ownership.
    ]
  }
  provisioner "local-exec" {  # Local provisioner: скачивает kubeconfig на Jenkins-хост.
    command = "scp dev@${var.vps_ip}:/home/dev/.kube/config kubeconfig.yaml"
  }
}

# Helm release для cert-manager — устанавливает чарт из repo.
resource "helm_release" "cert_manager" {
  depends_on = [null_resource.install_k3s]  # Ждет k3s.
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"  # Repo для чарта.
  chart      = "cert-manager"  # Имя чарта.
  namespace  = "cert-manager"  # Namespace для установки.
  create_namespace = true  # Создает ns если нет.
  set {  # Set параметр: включает CRDs.
    name  = "installCRDs"
    value = "true"
  }
}

# Kubernetes manifest для ClusterIssuer — создает ресурс для Let's Encrypt.
resource "kubernetes_manifest" "cluster_issuer" {
  depends_on = [helm_release.cert_manager]
  manifest = {  # YAML-like структура: определяет ACME issuer.
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = { name = "letsencrypt" }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"  # ACME server для production.
        email  = "your@email.com"  # Замените на ваш реальный email (для Let's Encrypt уведомлений, из вашего аккаунта).
        privateKeySecretRef = { name = "letsencrypt" }  # Secret для private key.
        solvers = [{ http01 = { ingress = { class = "traefik" } } }]  # Solver: HTTP-01 с Traefik.
      }
    }
  }
}

# Module для FluxCD из Terraform Registry — уменьшает код, используя готовый модуль.
module "flux" {
  source  = "fluxcd/flux/kubernetes"  # Из registry.terraform.io.
  version = "1.7.3"  # Актуальная версия на 2025 (проверено в Terraform Registry).
  github_owner = split("/", var.github_repo)[0]  # Owner из repo var.
  github_repository = split("/", var.github_repo)[1]  # Repo name.
  branch = "main"  # Branch для bootstrap.
  target_path = "clusters/production"  # Path в repo для manifests.
  github_token = var.github_token  # Token для auth (из env/Jenkins).
}

# Namespace для app.
resource "kubernetes_namespace" "app_prod" {
  depends_on = [null_resource.install_k3s]
  metadata { name = "app-prod" }  # Создает ns app-prod.
}

# RBAC role для app-prod — определяет permissions.
resource "kubernetes_role" "app_prod_manager" {
  depends_on = [kubernetes_namespace.app_prod]
  metadata {
    name      = "app-prod-manager"
    namespace = "app-prod"
  }
  rule {  # Rule: permissions для deployments/services/ingresses.
    api_groups = ["", "apps", "networking.k8s.io"]
    resources  = ["deployments", "services", "ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

# Role binding: привязывает Flux SA к role.
resource "kubernetes_role_binding" "flux_binding" {
  depends_on = [kubernetes_role.app_prod_manager]
  metadata {
    name      = "flux-to-app-prod"
    namespace = "app-prod"
  }
  role_ref {  # Ссылка на role.
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "app-prod-manager"
  }
  subject {  # Subject: Flux controller SA.
    kind      = "ServiceAccount"
    name      = "kustomize-controller"
    namespace = "flux-system"
  }
}