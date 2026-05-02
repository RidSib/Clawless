data "local_file" "ssh_key" {
  filename = pathexpand(var.public_key_path)
}

locals {
  common_tags = {
    environment = var.environment
    project     = var.project
    owner       = var.owner
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  name                = "${var.vm_name}-vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.10.0.0/16"]
  tags                = local.common_tags
}

resource "azurerm_subnet" "main" {
  name                 = "${var.vm_name}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "main" {
  name                = "${var.vm_name}-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "main" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Parity with GCP stack: expose gateway directly.
  security_rule {
    name                       = "allow-openclaw-gateway"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "18789"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.realtime_nsg_https ? [1] : []
    content {
      name                       = "allow-https-realtime"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_interface" "main" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "dev" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.ssh_user
  network_interface_ids = [
    azurerm_network_interface.main.id
  ]
  tags = local.common_tags

  admin_ssh_key {
    username   = var.ssh_user
    public_key = data.local_file.ssh_key.content
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 50
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(templatefile("${path.module}/../cloud-init.yaml", {
    ssh_public_key = trimspace(data.local_file.ssh_key.content)
    telegram_user_id = var.telegram_user_id
    github_token = var.github_token
    vercel_token = var.vercel_token
    azure_openai_api_key = var.azure_openai_api_key
    azure_openai_endpoint = var.azure_openai_endpoint
    azure_openai_realtime_deployment_name = (
      var.azure_openai_realtime_deployment_name
    )
    openai_api_key = var.openai_api_key
    twilio_auth_token = var.twilio_auth_token
    realtime_public_url = var.realtime_public_url
    realtime_provider = var.realtime_provider
    realtime_voice_flag = var.realtime_voice_enabled ? "1" : "0"
    realtime_voice_repo_url = var.realtime_voice_repo_url
    realtime_caddy_flag = trimspace(var.realtime_caddy_hostname) != "" ? "1" : "0"
    realtime_caddy_hostname = var.realtime_caddy_hostname
    cloudflare_tunnel_flag = trimspace(var.cloudflare_tunnel_token) != "" ? "1" : "0"
    cloudflare_tunnel_token = var.cloudflare_tunnel_token
    openclaw_runtime_extras_dockerfile_b64 = base64encode(file(
      "${path.module}/../docker/openclaw-runtime-extras.Dockerfile"
    ))
    workspace_identity_b64 = base64encode(file(
      "${path.module}/../workspace-seed/IDENTITY.md"
    ))
    workspace_user_b64 = base64encode(file(
      "${path.module}/../workspace-seed/USER.md"
    ))
    workspace_soul_b64 = base64encode(file(
      "${path.module}/../workspace-seed/SOUL.md"
    ))
  }))
}
