# ==========================================
# 1. Resource Groups
# ==========================================

resource "azurerm_resource_group" "hub" {
  name     = var.hub_rg_name
  location = var.location
}

resource "azurerm_resource_group" "spoke" {
  name     = var.spoke_rg_name
  location = var.location
}

# ==========================================
# 2. Hub Virtual Network & Subnets
# ==========================================

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub-prod-01"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = var.hub_vnet_cidr
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.0.0/27"]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/26"]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.2.0/26"]
}

# ==========================================
# 3. Spoke Virtual Network & Subnets
# ==========================================

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-app-prod-01"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  address_space       = var.spoke_vnet_cidr
}

resource "azurerm_subnet" "snet_agw" {
  name                 = "snet-agw"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_subnet" "snet_app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_subnet" "snet_db" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.3.0/24"]
}

resource "azurerm_subnet" "snet_mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.4.0/24"]
}

# ==========================================
# 4. Bidirectional VNet Peering
# ==========================================

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                         = "peer-hub-to-app"
  resource_group_name          = azurerm_resource_group.hub.name
  virtual_network_name         = azurerm_virtual_network.hub.name
  remote_virtual_network_id    = azurerm_virtual_network.spoke.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                         = "peer-app-to-hub"
  resource_group_name          = azurerm_resource_group.spoke.name
  virtual_network_name         = azurerm_virtual_network.spoke.name
  remote_virtual_network_id    = azurerm_virtual_network.hub.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

# ==========================================
# 5. Network Security Groups (NSGs)
# ==========================================
resource "azurerm_network_security_group" "nsg_app" {
  name                = "nsg-app-prod-01"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name

  security_rule {
    name                       = "Allow-AGW-Inbound-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"            # Set to 80 for Nginx!
    source_address_prefix      = "10.1.1.0/24"    # snet-agw
    destination_address_prefix = "10.1.2.0/24"    # snet-app
  }
}

resource "azurerm_network_security_group" "nsg_db" {
  name                = "nsg-db-prod-01"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name

  security_rule {
    name                       = "Allow-AppSubnet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.1.2.0/24"    # snet-app
    destination_address_prefix = "10.1.3.0/24"    # snet-db
  }
}

resource "azurerm_subnet_network_security_group_association" "app_assoc" {
  subnet_id                 = azurerm_subnet.snet_app.id
  network_security_group_id = azurerm_network_security_group.nsg_app.id
}

resource "azurerm_subnet_network_security_group_association" "db_assoc" {
  subnet_id                 = azurerm_subnet.snet_db.id
  network_security_group_id = azurerm_network_security_group.nsg_db.id
}

# ==========================================
# 6. User Defined Routes (UDR - Forced Tunneling)
# ==========================================

resource "azurerm_route_table" "spoke_udr" {
  name                = "rt-spoke-to-firewall"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name

  route {
    name                   = "dg-to-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.1.4" # Azure Firewall IP in Hub VNet
  }
}

# "azurerm_subnet_route_table_association" "app_udr_assoc" {
#  subnet_id      = azurerm_subnet.snet_app.id
#  route_table_id = azurerm_route_table.spoke_udr.id
#}

resource "azurerm_subnet_route_table_association" "db_udr_assoc" {
  subnet_id      = azurerm_subnet.snet_db.id
  route_table_id = azurerm_route_table.spoke_udr.id
}

# ==========================================
# Module 02: Azure Bastion
# ==========================================

resource "azurerm_public_ip" "bastion_pip" {
  name                = "pip-bastion-prod-01"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "bastion" {
  name                = "bas-hub-prod-01"
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  ip_configuration {
    name                 = "bastion-ip-config"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}
# ==========================================
# 8. Module 03: Workload VMs (App & DB Tiers)
# ==========================================

# Temporary Public IP for VM internet access
# resource "azurerm_public_ip" "temp_vm_pip" {
#  name                = "pip-temp-vm-01"
#  resource_group_name = azurerm_resource_group.spoke.name
#  location            = azurerm_resource_group.spoke.location
#  allocation_method   = "Static"
#  sku                 = "Standard"
#}

# Network Interface (NIC) for App VM inside snet-app (Private IP only)
resource "azurerm_network_interface" "nic_app" {
  name                = "nic-vm-app-prod-01"
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_app.id
    private_ip_address_allocation = "Dynamic"
#    public_ip_address_id          = azurerm_public_ip.temp_vm_pip.id
  }
}

# App Tier Virtual Machine
resource "azurerm_linux_virtual_machine" "vm_app" {
  name                            = "vm-app-prod-01"
  resource_group_name             = azurerm_resource_group.spoke.name
  location                        = azurerm_resource_group.spoke.location
  size                            = "Standard_DC1ds_v3"
  # --- SPOT VM CONFIGURATION ---
  priority                        = "Spot"
  eviction_policy                 = "Deallocate"
  # ------------------------------
  admin_username                  = "azureuser"
  admin_password                  = "P@ssw0rd123456!" # Practice password
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic_app.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

# --- MODULE 04: APPLICATION GATEWAY ---

# 1. Public IP for Application Gateway
resource "azurerm_public_ip" "agw_pip" {
  name                = "pip-agw-prod-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 2. Application Gateway Instance
resource "azurerm_application_gateway" "agw" {
  name                = "agw-spoke-prod-01"
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }
  
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
  gateway_ip_configuration {
    name      = "agw-ip-config"
    subnet_id = azurerm_subnet.snet_agw.id
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.agw_pip.id
  }

  backend_address_pool {
    name         = "app-vm-backend-pool"
    ip_addresses = [azurerm_network_interface.nic_app.private_ip_address]
  }

  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule-http-to-backend"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "app-vm-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }
}