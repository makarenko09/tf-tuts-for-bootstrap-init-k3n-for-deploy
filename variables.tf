variable "vps_ip" {
   type        = string
   description = "IP вашего VPS"
}

variable "ssh_key_path" {
   type        = string
   default     = "C:/Users/your_user/.ssh/id_rsa" # <--- ЗАМЕНИТЕ НА ПУТЬ К ВАШЕМУ КЛЮЧУ НА WINDOWS
   description = "Путь к SSH ключу на Jenkins-контроллере (Windows)"
}

variable "github_repo" {
   type        = string
   description = "GitHub repo для Flux (e.g., 'yourusername/gitops-repo')"
}

variable "github_token" {
   type        = string
   sensitive   = true
   description = "GitHub PAT для Flux"
}