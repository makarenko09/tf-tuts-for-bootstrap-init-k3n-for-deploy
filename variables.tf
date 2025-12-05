# Входные переменные — позволяют параметризовать без hardcode (передавать из Jenkins).
variable "vps_ip" {
   type        = string
   description = "IP вашего VPS (из VDSina dashboard, e.g., '85.198.111.128')"
}

variable "ssh_key_path" {
   type        = string
   default     = "~/.ssh/id_rsa"
   description = "Путь к SSH ключу на Jenkins-хосте (где хранится приватный ключ для user dev)"
}

variable "github_repo" {
   type        = string
   description = "GitHub repo для Flux (e.g., 'yourusername/gitops-repo' — из GitHub > Repos > Create new)"
}

variable "github_token" {
   type        = string
   sensitive   = true  # Маркирует как sensitive: значение маскируется в output/logs для безопасности.
   description = "GitHub PAT (Personal Access Token) для Flux (из GitHub > Settings > Developer settings > Personal access tokens > Generate new, scopes: repo)"
}