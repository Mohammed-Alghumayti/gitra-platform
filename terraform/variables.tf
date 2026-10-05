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
  description = "Azure region. The workflow uses the GitLab VM's region."
  type        = string
  default     = "eastus"
}

variable "vnet_address_space" {
  description = "Address space of the runner's virtual network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix of the runner subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "runner_vm_size" {
  description = "Runner VM size (runs CI jobs and the staging app)."
  type        = string
  default     = "Standard_B2s" # 2 vCPU, 4 GB RAM
}

variable "admin_username" {
  description = "Admin user on the runner VM."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key (contents) for the runner VM. Password login is disabled."
  type        = string
}

variable "admin_source_cidrs" {
  description = "CIDRs allowed to reach admin SSH (port 22). Open by default; SSH is key-only and fail2ban blocks brute force."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "user_source_cidrs" {
  description = "CIDRs allowed to reach the staging app. Public by design."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "gitlab_url" {
  description = "GitLab URL the runner connects to, e.g. https://gitra-xxxx.eastus.cloudapp.azure.com"
  type        = string
}

variable "repo_url" {
  description = "Git repository cloned on the runner VM."
  type        = string
  default     = "https://github.com/Mohammed-Alghumayti/gitra-platform.git"
}

variable "repo_branch" {
  description = "Branch of repo_url to clone."
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
