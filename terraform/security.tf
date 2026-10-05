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
}
