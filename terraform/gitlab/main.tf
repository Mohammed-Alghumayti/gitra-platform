# GitLab platform (Member 1): gitra-rg, VNet, subnet, NSG, public IP, NIC, VM.
# These resources already existed when Terraform took them over:
# import_existing.sh adopts them into the state without recreating anything.
# prevent_destroy guards the ones holding data or the address.

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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Same storage account as the runner, different state file
  # (key=gitra-gitlab.tfstate, passed by the workflow).
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# ==========================================================================
# Variables
# ==========================================================================
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

# ==========================================================================
# Resource group
# ==========================================================================
resource "azurerm_resource_group" "gitlab" {
  name     = "gitra-rg"
  location = var.location

  lifecycle {
    prevent_destroy = true
  }
}

# ==========================================================================
# Network: VNet, subnet, public IP, NIC
# ==========================================================================
resource "azurerm_virtual_network" "gitlab" {
  name                = "vnet-eastus-1"
  location            = azurerm_resource_group.gitlab.location
  resource_group_name = azurerm_resource_group.gitlab.name
  address_space       = [var.vnet_address_space]
}

resource "azurerm_subnet" "gitlab" {
  name                              = "snet-eastus-1"
  resource_group_name               = azurerm_resource_group.gitlab.name
  virtual_network_name              = azurerm_virtual_network.gitlab.name
  address_prefixes                  = [var.subnet_address_prefix]
  private_endpoint_network_policies = "Disabled"
}

# Static IP + DNS name: GitLab's URL, clone links and HTTPS certificate
# depend on it, so it must never change.
resource "azurerm_public_ip" "gitlab" {
  name                = "gitra-gitlab-vm-ip"
  location            = azurerm_resource_group.gitlab.location
  resource_group_name = azurerm_resource_group.gitlab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.zone]
  domain_name_label   = var.dns_label

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_network_interface" "gitlab" {
  name                = "gitra-gitlab-vm703"
  location            = azurerm_resource_group.gitlab.location
  resource_group_name = azurerm_resource_group.gitlab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.gitlab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.gitlab.id
    primary                       = true
  }
}

# ==========================================================================
# Security: NSG rules and NIC association
# ==========================================================================
# Only the ports GitLab needs; Azure's default rules deny all other inbound
# traffic. Rule names and priorities match the existing NSG.
locals {
  gitlab_nsg_rules = {
    default-allow-ssh = { priority = 1000, port = "22" }   # VM administration
    Allow-HTTPS       = { priority = 1010, port = "443" }  # GitLab web UI
    Allow-HTTP        = { priority = 1020, port = "80" }   # redirect to HTTPS + Let's Encrypt
    Allow-Gitlab-SSH  = { priority = 1030, port = "2224" } # Git over SSH
  }
}

resource "azurerm_network_security_group" "gitlab" {
  name                = "gitra-gitlab-vm-nsg"
  location            = azurerm_resource_group.gitlab.location
  resource_group_name = azurerm_resource_group.gitlab.name

  dynamic "security_rule" {
    for_each = local.gitlab_nsg_rules
    content {
      name                       = security_rule.key
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = var.public_source_cidrs
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_interface_security_group_association" "gitlab" {
  network_interface_id      = azurerm_network_interface.gitlab.id
  network_security_group_id = azurerm_network_security_group.gitlab.id
}

# ==========================================================================
# Virtual machine
# ==========================================================================
# The VM was created with password login. Changing that through Terraform
# would rebuild the VM (and lose GitLab's data), so the password is ignored
# here: the value below is only a placeholder Terraform requires and is never
# sent to Azure (see ignore_changes).
resource "random_password" "placeholder" {
  length  = 32
  special = true
}

resource "azurerm_linux_virtual_machine" "gitlab" {
  name                  = "gitra-gitlab-vm"
  location              = azurerm_resource_group.gitlab.location
  resource_group_name   = azurerm_resource_group.gitlab.name
  size                  = var.vm_size
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.gitlab.id]

  admin_username                  = var.admin_username
  admin_password                  = random_password.placeholder.result
  disable_password_authentication = false

  # Trusted Launch, as created.
  secure_boot_enabled = true
  vtpm_enabled        = true

  disk_controller_type = "SCSI"

  os_disk {
    name                 = "gitra-gitlab-vm_OsDisk_1_790b35debd4a4c7f852806bcaa406c01"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "canonical"
    offer     = "ubuntu-22_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # As on the existing VM; without this block Terraform plans to clear them.
  additional_capabilities {
    hibernation_enabled = false
    ultra_ssd_enabled   = false
  }

  # Boot diagnostics with a managed storage account.
  boot_diagnostics {}

  lifecycle {
    # The VM holds all of GitLab's data.
    prevent_destroy = true
    # Set at creation; changing them would force a rebuild.
    ignore_changes = [admin_password, admin_ssh_key, custom_data, source_image_reference]
  }
}

# ==========================================================================
# Outputs
# ==========================================================================
output "gitlab_url" {
  description = "GitLab over HTTPS."
  value       = "https://${azurerm_public_ip.gitlab.fqdn}"
}

output "gitlab_public_ip" {
  description = "Public IP of the GitLab VM."
  value       = azurerm_public_ip.gitlab.ip_address
}
