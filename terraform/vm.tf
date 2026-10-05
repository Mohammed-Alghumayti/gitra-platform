resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${local.name}-vm"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.main.id]
  tags                  = var.tags

  # SSH keys only — password login is disabled.
  disable_password_authentication = true
  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.admin_ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # First boot: install Docker, clone the repo and launch GitLab + Runner.
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    admin_username = var.admin_username
    repo_url       = var.repo_url
    repo_branch    = var.repo_branch
    external_url   = "http://${azurerm_public_ip.main.ip_address}"
  }))

  # The NSG must be in place before GitLab is exposed.
  depends_on = [azurerm_subnet_network_security_group_association.main]
}
