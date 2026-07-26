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
    name                       = "Allow-AppGateway-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "10.1.1.0/24" # snet-agw
    destination_address_prefix = "10.1.2.0/24" # snet-app
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
    source_address_prefix      = "10.1.2.0/24" # snet-app
    destination_address_prefix = "10.1.3.0/24" # snet-db
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

resource "azurerm_subnet_route_table_association" "app_udr_assoc" {
  subnet_id      = azurerm_subnet.snet_app.id
  route_table_id = azurerm_route_table.spoke_udr.id
}

resource "azurerm_subnet_route_table_association" "db_udr_assoc" {
  subnet_id      = azurerm_subnet.snet_db.id
  route_table_id = azurerm_route_table.spoke_udr.id
}