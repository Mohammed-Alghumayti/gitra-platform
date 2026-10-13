# Tests with a mocked Azure provider — no Azure account needed.
# Run: terraform init -backend=false && terraform test

# Mocked IDs must look like real Azure resource IDs.
mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = {
      id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/gitra-rg/providers/Microsoft.Network/publicIPAddresses/mock-pip"
      ip_address = "20.0.0.20"
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
  subscription_id      = "00000000-0000-0000-0000-000000000000"
  admin_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqweEUK2w/Vck50baGNEDNABZitNbORQgvBHcgOXrAWlmWIjtzBlijMfdT8YrtXk7GUb03K4M3jfHXSDucU8MpxLQp7IwjcVqCJQVRwB6J0CzgaEmH0IAZoNtcnrQnM9pI8SrP8T8qs5NCkxZO2XaaYGRYiV2Q1x7Ry5hhtUD+lhGOnCEKc5qd25BkGJfnYVV3S34MFpQ2jlxhZxRZfG6GJ57WF/RcVXmpZ3Qz9Rm9s5VDcnAzh6sjx/+tUkYft8ah+717EgVHns0M157xcHA5g1wmNIn2UQAAwsjbciev6akdXrGFQDJac+7NMejMQ6FuiJz7KWqhEzVVKLS9ZK/9 test-only-not-a-real-key"
  gitlab_url           = "https://gitra-test.eastus.cloudapp.azure.com"
}

run "runner_vm_starts_the_runner_against_gitlab" {
  command = apply

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runner.custom_data), "deploy_runner.sh")
    error_message = "The runner VM must start the runner on first boot."
  }

  assert {
    condition     = strcontains(base64decode(azurerm_linux_virtual_machine.runner.custom_data), "GITLAB_EXTERNAL_URL=https://gitra-test.eastus.cloudapp.azure.com")
    error_message = "The runner must point at GitLab's HTTPS URL."
  }

  assert {
    condition     = !strcontains(base64decode(azurerm_linux_virtual_machine.runner.custom_data), "scripts/deploy.sh")
    error_message = "The runner VM must not run GitLab."
  }
}

run "never_touches_the_existing_gitlab_resources" {
  command = apply

  assert {
    condition     = azurerm_resource_group.main.name == "gitra-runner-rg" && azurerm_linux_virtual_machine.runner.name == "gitra-runner-vm"
    error_message = "Runner resources must not reuse the existing gitra-rg / gitra-gitlab-vm names."
  }
}

run "runner_vm_is_locked_down" {
  command = apply

  assert {
    condition     = azurerm_linux_virtual_machine.runner.disable_password_authentication
    error_message = "The runner VM must be SSH-key only."
  }

  assert {
    condition     = toset([for r in azurerm_network_security_group.runner.security_rule : r.destination_port_range]) == toset(["22", "5000"])
    error_message = "Runner NSG must open exactly 22 and 5000."
  }

  assert {
    condition     = output.staging_app_url == "http://20.0.0.20:5000"
    error_message = "Staging URL must use the runner's public IP."
  }
}
