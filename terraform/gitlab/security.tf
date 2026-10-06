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
