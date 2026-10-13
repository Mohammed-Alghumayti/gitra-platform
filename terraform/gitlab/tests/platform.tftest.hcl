# Tests with mocked providers — no Azure account needed.
# Run: terraform init -backend=false && terraform test

mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/publicIPAddresses/gitra-gitlab-vm-ip"
      fqdn       = "gitra-25ee91e6.eastus.cloudapp.azure.com"
      ip_address = "20.55.88.3"
    }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/virtualNetworks/vnet-eastus-1/subnets/snet-eastus-1" }
  }
  mock_resource "azurerm_network_interface" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/networkInterfaces/gitra-gitlab-vm703" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/networkSecurityGroups/gitra-gitlab-vm-nsg" }
  }
}

mock_provider "random" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
}

run "matches_the_existing_platform" {
  command = plan

  assert {
    condition     = azurerm_resource_group.gitlab.name == "gitra-rg" && azurerm_linux_virtual_machine.gitlab.name == "gitra-gitlab-vm"
    error_message = "Names must match the existing resources so they are imported, not recreated."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.gitlab.size == "Standard_D4s_v4" && azurerm_linux_virtual_machine.gitlab.zone == "1"
    error_message = "VM size and zone must match the existing VM."
  }

  assert {
    condition     = azurerm_virtual_network.gitlab.address_space == toset(["172.16.0.0/16"]) && azurerm_subnet.gitlab.address_prefixes == tolist(["172.16.0.0/24"])
    error_message = "Network ranges must match the existing VNet/subnet."
  }

  assert {
    condition     = azurerm_public_ip.gitlab.allocation_method == "Static" && azurerm_public_ip.gitlab.domain_name_label == "gitra-25ee91e6"
    error_message = "The public IP must stay static with the same DNS name (GitLab URL + HTTPS)."
  }
}

run "nsg_opens_only_gitlab_ports" {
  command = plan

  assert {
    condition     = toset([for r in azurerm_network_security_group.gitlab.security_rule : r.destination_port_range]) == toset(["22", "80", "443", "2224"])
    error_message = "GitLab NSG must open exactly 22, 80, 443 and 2224."
  }
}
