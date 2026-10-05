variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "project_name" {
  description = "Prefix used for every resource name."
  type        = string
  default     = "gitra"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix of the VM subnet."
  type        = string
  default     = "10.10.1.0/24"
}

variable "vm_size" {
  description = "VM size. GitLab CE needs at least 4 GB RAM; 8 GB is recommended."
  type        = string
  default     = "Standard_D2s_v3" # 2 vCPU, 8 GB RAM
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB (holds Docker images and GitLab data)."
  type        = number
  default     = 64
}

variable "admin_username" {
  description = "Admin user on the VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key_path" {
  description = "Path to the SSH public key used to log in to the VM (password login is disabled)."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "admin_source_cidrs" {
  description = "CIDRs allowed to reach admin SSH (port 22). Restrict to the team's IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "user_source_cidrs" {
  description = "CIDRs allowed to reach GitLab web, Git SSH and the staging app."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "repo_url" {
  description = "Git repository cloned on the VM to deploy GitLab."
  type        = string
  default     = "https://github.com/Mohammed-Alghumayti/gitra-platform.git"
}

variable "repo_branch" {
  description = "Branch of repo_url to deploy."
  type        = string
  default     = "Testing"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project = "gitra-platform"
    managed = "terraform"
  }
}
