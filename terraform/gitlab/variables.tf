variable "subscription_id" {
  description = "Azure subscription ID."
  type        = string
}

variable "location" {
  description = "Azure region of the GitLab platform."
  type        = string
  default     = "eastus"
}

variable "zone" {
  description = "Availability zone of the VM, its public IP and disk."
  type        = string
  default     = "1"
}

variable "vm_size" {
  description = "GitLab VM size. GitLab CE needs at least 4 GB RAM; 8 GB+ recommended."
  type        = string
  default     = "Standard_D4s_v4" # 4 vCPU, 16 GB RAM
}

variable "admin_username" {
  description = "VM admin user."
  type        = string
  default     = "gitra"
}

variable "dns_label" {
  description = "Free Azure DNS name: <dns_label>.<location>.cloudapp.azure.com (used for HTTPS)."
  type        = string
  default     = "gitra-25ee91e6"
}

variable "vnet_address_space" {
  description = "Address space of the platform VNet."
  type        = string
  default     = "172.16.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix of the platform subnet."
  type        = string
  default     = "172.16.0.0/24"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB (holds Docker images and GitLab data)."
  type        = number
  default     = 30
}

variable "public_source_cidrs" {
  description = "Who may reach GitLab (web + Git SSH). Public by design."
  type        = string
  default     = "*"
}
