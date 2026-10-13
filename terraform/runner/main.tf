# CI runner (Member 1): gitra-runner-rg, VNet, subnet, NSG, public IP, NIC, VM.
# Disposable: the workflow can rebuild it in any region at any time.

# ==========================================================================
# Terraform settings and provider
# ==========================================================================
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # State lives in an Azure Storage account so every GitHub Actions run sees
  # the same infrastructure. The workflow creates the account and passes its
  # name with -backend-config (see .github/workflows/deploy.yml).
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    # gitra-runner-rg only holds the runner. When it moves region, it must be
    # deletable even if a failed VM attempt left a disk behind in it.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # Authenticates with ARM_* environment variables (GitHub Actions) or `az login`.
  subscription_id = var.subscription_id
}

# ==========================================================================
# Variables
# ==========================================================================
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

# ==========================================================================
# Resource group
# ==========================================================================
locals {
  # "gitra-runner-*": kept apart from the team's existing gitra-rg / gitra-gitlab-vm.
  name = "${var.project_name}-runner"
}

resource "azurerm_resource_group" "main" {
  name     = "${local.name}-rg"
  location = var.location
  tags     = var.tags
}

# ==========================================================================
# Network: VNet, subnet, public IP, NIC
# ==========================================================================
# Network for the runner VM only. GitLab runs on the team's existing VM.
resource "azurerm_virtual_network" "main" {
  name                = "${local.name}-vnet"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "${local.name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address_prefix]

  # A subnet has no region of its own: when the VNet is rebuilt (e.g. a new
  # RUNNER_LOCATION), rebuild the subnet too instead of assuming it survived.
  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.main]
  }
}

# Static, so the staging URL never changes. Also gives the VM outbound access
# (pulling images, reaching GitLab over HTTPS).
resource "azurerm_public_ip" "runner" {
  name                = "${local.name}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "runner" {
  name                = "${local.name}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.runner.id
  }
}

# ==========================================================================
# Security: NSG rules and NIC association
# ==========================================================================
# Only the ports the runner VM needs; Azure's default rules deny all other
# inbound traffic. (The GitLab VM's NSG is managed by the deploy workflow.)
locals {
  runner_nsg_rules = {
    Allow-SSH-Admin = {
      priority = 100
      port     = "22"
      sources  = var.admin_source_cidrs
    }
    Allow-Staging-App = {
      priority = 110
      port     = "5000"
      sources  = var.user_source_cidrs
    }
  }
}

resource "azurerm_network_security_group" "runner" {
  name                = "${local.name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  dynamic "security_rule" {
    for_each = local.runner_nsg_rules
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefixes    = security_rule.value.sources
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_interface_security_group_association" "runner" {
  network_interface_id      = azurerm_network_interface.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id

  # Re-attach whenever the NIC or NSG is rebuilt (their IDs keep the same name).
  lifecycle {
    replace_triggered_by = [azurerm_network_interface.runner, azurerm_network_security_group.runner]
  }
}

# ==========================================================================
# Virtual machine
# ==========================================================================
# Runner VM: CI jobs + staging app, isolated from GitLab's data and secrets.
resource "azurerm_linux_virtual_machine" "runner" {
  name                  = "${local.name}-vm"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.runner_vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.runner.id]
  tags                  = var.tags

  # SSH keys only — password login is disabled.
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 32
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # First boot: Docker + fail2ban → clone repo → start the runner.
  # Registration with GitLab is done by the deploy workflow.
  custom_data = base64encode(templatefile("${path.module}/cloud-init-runner.yaml.tftpl", {
    admin_username = var.admin_username
    repo_url       = var.repo_url
    repo_branch    = var.repo_branch
    external_url   = var.gitlab_url
  }))

  # The NSG must be in place before the VM is reachable.
  depends_on = [azurerm_network_interface_security_group_association.runner]
}

# ==========================================================================
# Outputs
# ==========================================================================
output "runner_public_ip" {
  description = "Public IP of the runner VM."
  value       = azurerm_public_ip.runner.ip_address
}

output "runner_ssh_command" {
  description = "Admin SSH into the runner VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.runner.ip_address}"
}

output "staging_app_url" {
  description = "Sample app deployed by the CI/CD pipeline."
  value       = "http://${azurerm_public_ip.runner.ip_address}:5000"
}
