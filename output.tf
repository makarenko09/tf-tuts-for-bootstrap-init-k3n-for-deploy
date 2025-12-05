# Выходные значения — возвращаются после apply, полезны для Jenkins (e.g., для последующих stages).
output "kubeconfig_path" {
 description = "Путь к скачанному kubeconfig на Jenkins-хосте"
 value       = "kubeconfig.yaml"
 sensitive   = false
}