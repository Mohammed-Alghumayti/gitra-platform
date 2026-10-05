# Plan-level tests with a mocked Azure provider — no Azure account needed.
# Run: terraform init && terraform test

# Mocked IDs must look like real Azure resource IDs.
mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/publicIPAddresses/mock-pip"
      fqdn       = "gitra-platform.eastus.cloudapp.azure.com"
      ip_address = "20.0.0.10"
    }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/mock-subnet" }
  }
  mock_resource "azurerm_network_interface" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/networkInterfaces/mock-nic" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/networkSecurityGroups/mock-nsg" }
  }
}

variables {
  subscription_id           = "00000000-0000-0000-0000-000000000000"
  admin_ssh_public_key_path = "tests/test_key.pub"
}

run "gitlab_and_runner_are_separate_vms" {
  command = apply

  assert {
    condition     = azurerm_linux_virtual_machine.gitlab.name != azurerm_linux_virtual_machine.runner.name && azurerm_network_interface.gitlab.name != azurerm_network_interface.runner.name
    error_message = "GitLab and the runner must be on different VMs and NICs."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.gitlab.custom_data), "deploy.sh") && !strcontains(base64decode(azurerm_linux_virtual_machine.gitlab.custom_data), "deploy_runner.sh")
    error_message = "The GitLab VM must deploy GitLab only, not the runner."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runner.custom_data), "deploy_runner.sh")
    error_message = "The runner VM must start the runner."
  }
}

run "gitlab_uses_https_and_hardening" {
  command = apply

  assert {
    condition     = output.gitlab_url == "https://gitra-platform.eastus.cloudapp.azure.com"
    error_message = "GitLab must be served over HTTPS on the Azure DNS name."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.gitlab.custom_data), "GITLAB_EXTERNAL_URL=https://")
    error_message = "cloud-init must configure an https:// external_url."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.gitlab.custom_data), "harden_gitlab.sh")
    error_message = "cloud-init must apply GitLab security settings."
  }

  assert {
    condition     = azurerm_linux_virtual_machine.gitlab.disable_password_authentication && azurerm_linux_virtual_machine.runner.disable_password_authentication
    error_message = "Both VMs must be SSH-key only."
  }
}

run "nsg_ports_are_minimal" {
  command = apply

  assert {
    condition     = toset([for r in azurerm_network_security_group.gitlab.security_rule : r.destination_port_range]) == toset(["22", "80", "443", "2224"])
    error_message = "GitLab NSG must open exactly 22, 80, 443, 2224."
  }

  assert {
    condition     = toset([for r in azurerm_network_security_group.runner.security_rule : r.destination_port_range]) == toset(["22", "5000"])
    error_message = "Runner NSG must open exactly 22 and 5000."
  }
}
