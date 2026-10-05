# Runner VM: CI jobs + staging app, isolated from GitLab's data and secrets.
resource "azurerm_linux_virtual_machine" "runner" {
  name                  = "${local.name}-runner-vm"
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
