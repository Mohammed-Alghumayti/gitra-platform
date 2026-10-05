# Each VM gets its own NSG with only the ports it needs; Azure's default rules
# deny all other inbound traffic.
locals {
  gitlab_nsg_rules = {
    Allow-SSH-Admin = {
      priority = 100
      port     = "22"
      sources  = var.admin_source_cidrs
    }
    Allow-HTTP = { # redirects to HTTPS + Let's Encrypt challenge
      priority = 110
      port     = "80"
      sources  = var.user_source_cidrs
    }
    Allow-HTTPS = {
      priority = 120
      port     = "443"
      sources  = var.user_source_cidrs
    }
    Allow-GitLab-SSH = {
      priority = 130
      port     = "2224"
      sources  = var.user_source_cidrs
    }
  }

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

resource "azurerm_network_security_group" "gitlab" {
  name                = "${local.name}-gitlab-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

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
      source_address_prefixes    = security_rule.value.sources
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_security_group" "runner" {
  name                = "${local.name}-runner-nsg"
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

resource "azurerm_network_interface_security_group_association" "gitlab" {
  network_interface_id      = azurerm_network_interface.gitlab.id
  network_security_group_id = azurerm_network_security_group.gitlab.id
}

resource "azurerm_network_interface_security_group_association" "runner" {
  network_interface_id      = azurerm_network_interface.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}
