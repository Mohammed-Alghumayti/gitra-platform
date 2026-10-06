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
