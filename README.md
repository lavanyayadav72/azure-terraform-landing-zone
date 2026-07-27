## Azure Enterprise Landing Zone (Hub & Spoke Architecture)

This repository contains the Infrastructure as Code (IaC) written in **Terraform** to provision a production-grade, secure **Hub-and-Spoke Network Topology** in Microsoft Azure following the **Microsoft Cloud Adoption Framework (CAF)** guidelines.


## 🏛️ Architecture Overview

The infrastructure isolates core connectivity services (Hub VNet) from application workloads (Spoke VNet), enforcing security boundaries through Network Security Groups (NSGs) and User-Defined Routes (UDRs).

```text
                      +------------------------------------------+
                      |               HUB VNET                   |
                      |            (10.0.0.0/16)                 |
                      |                                          |
                      |  [GatewaySubnet]    [AzureFirewallSubnet]|
                      |  (10.0.0.0/27)        (10.0.1.0/26)    |
                      |                                          |
                      |          [AzureBastionSubnet]            |
                      |             (10.0.2.0/26)                |
                      +--------------------+---------------------+
                                           |
                                 Bidirectional VNet
                                      Peering
                                           |
                      +--------------------+---------------------+
                      |              SPOKE VNET                  |
                      |            (10.1.0.0/16)                 |
                      |                                          |
                      |  [snet-agw]   (10.1.1.0/24)              |
                      |  [snet-app]   (10.1.2.0/24) --> NSG & UDR|
                      |  [snet-db]    (10.1.3.0/24) --> NSG & UDR|
                      |  [snet-mgmt]  (10.1.4.0/24)              |
                      +------------------------------------------+
```

### Key Components Provisioned

1. **Hub Virtual Network (`vnet-hub-prod-01`)**:
   * Dedicated subnets for VPN/ExpressRoute Gateway, Azure Firewall, and Azure Bastion.
2. **Spoke Virtual Network (`vnet-app-prod-01`)**:
   * Segmented subnets for Application Gateway (`snet-agw`), Application Tier (`snet-app`), Database Tier (`snet-db`), and Management (`snet-mgmt`).
3. **Bidirectional VNet Peering**:
   * Enables low-latency, private routing between Hub and Spoke VNets.
4. **Network Security Groups (NSGs)**:
   * **`nsg-app-prod-01`**: Permits HTTP traffic (Port 8080) strictly from `snet-agw`.
   * **`nsg-db-prod-01`**: Permits SQL traffic (Port 1433) strictly from `snet-app`.
5. **User-Defined Routes (UDR)**:
   * Forced tunneling routing table (`rt-spoke-to-firewall`) routing all default egress traffic (`0.0.0.0/0`) to the central firewall IP (`10.0.1.4`).
6. **Remote State Backend**:
   * State stored securely in an **Azure Storage Account** Blob Container (`tfstate`) with state locking enabled.


## 🛠️ Prerequisites & Tools Used

* **Terraform**: `>= 1.5.0`
* **AzureRM Provider**: `~> 3.0`
* **Azure CLI**: `2.x+`
* **Git** for version control

## 🚀 Deployment Instructions

### 1. Authenticate with Azure
az login
### 2. Configure Remote Backend
Ensure your Azure Storage Account and Blob Container exist, then initialize Terraform:
terraform init
### 3. Execution Plan
Review the resources to be created:
terraform plan
### 4. Deploy Infrastructure
Apply the configuration to provision Azure resources:
terraform apply -auto-approve

### 🔒 Security Practices Implemented
No Public IPs on Workload Subnets: App and DB subnets are completely private.

Least-Privilege Security Rules: Micro-segmentation enforced via NSG associations.

Remote State Protection: .tfstate files are excluded via .gitignore to prevent secret leakage.

