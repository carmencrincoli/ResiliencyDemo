# E-commerce Resiliency Demo for Azure Local

A comprehensive, production-ready e-commerce application demonstrating high-availability architecture and infrastructure automation on Azure Local (formerly Azure Stack HCI). This project showcases best practices for building resilient applications with automated deployment using Azure Bicep templates.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)
- [Related Documentation](#related-documentation)

## 🎯 Overview

This project deploys a fully functional e-commerce web application on Azure Local infrastructure, demonstrating:

- **High Availability**: Multiple web application servers behind an NGINX load balancer
- **Database Replication**: PostgreSQL primary-replica configuration for data redundancy
- **Automated Deployment**: Complete infrastructure provisioning via Bicep templates
- **Production-Ready**: Comprehensive logging, monitoring, and health checks
- **Zero-Touch Onboarding**: Azure Arc-enabled VMs for cloud-based management

### What Gets Deployed

The solution automatically provisions and configures:
- **5 Virtual Machines** on Azure Local (2 web apps, 2 databases, 1 load balancer)
- **Next.js 14** full-stack e-commerce application with TypeScript
- **PostgreSQL 16** database with streaming replication
- **NGINX** load balancer with health checks and SSL/TLS
- **Complete observability** with structured logging and monitoring

## 📋 Prerequisites

### Azure Requirements
- **Azure Subscription** with appropriate permissions
- **Azure Local (Stack HCI)** cluster deployed and configured
- **Custom Location** created for the Azure Local cluster
- **Logical Network** configured with available IP addresses
- **VM Image**: Ubuntu 24.04 LTS gallery image

### Local Development Tools
- **Azure CLI** (latest version)
- **PowerShell** 7.0 or later
- **Bicep CLI** (or Azure CLI with Bicep support)

### Network Requirements
- **5 Static IP Addresses** in the same subnet
- **/24 Virtual Network** (255.255.255.0 subnet mask) - **Required**
  - The project is designed for /24 networks and cannot be changed without modifying the codebase
  - All 5 IPs must be in the same /24 subnet
- **Outbound Internet Access** for package downloads
- **Azure Storage Access** for deployment scripts

## 🚀 Quick Start

### 1. Clone the Repository
```powershell
git clone <repository-url>
cd ResiliencyDemo
```

### 2. Configure Parameters
Edit `main.bicepparam` with your environment details:
```bicep
param customLocationName = 'your-custom-location'
param logicalNetworkName = 'your-logical-network'
param azureLocalResourceGroup = 'your-azure-local-rg'
param vmImageName = 'ubuntu2404-lts-image-name'

param staticIPs = {
  loadBalancer: '192.168.x.111'
  dbPrimary: '192.168.x.112'
  dbReplica: '192.168.x.113'
  webapp1: '192.168.x.114'
  webapp2: '192.168.x.115'
}

param adminPassword = 'YourSecurePassword!'
param servicePassword = 'YourDatabasePassword!'
```

### 3. Prepare Deployment
Run the preparation script to upload assets to Azure Storage:
```powershell
.\Prepare-Deployment.ps1 `
    -ResourceGroupName "rg-ecommerce-demo" `
    -Location "eastus"
```

This script will:
- Create or use existing Azure Storage Account
- Upload deployment scripts and application archives
- Update the parameters file with storage account details

### 4. Deploy Infrastructure
```powershell
# Create resource group
az group create --name rg-ecommerce-demo --location eastus

# Deploy the Bicep template
az deployment group create `
    --resource-group rg-ecommerce-demo `
    --template-file ./infra/main.bicep `
    --parameters ./main.bicepparam
```

### 5. Access the Application
Once deployment completes (15-20 minutes):
```
http://192.168.x.111  (your load balancer IP)
```

## � Documentation

Detailed documentation is organized into focused guides:

- **[Architecture & Application Stack](documentation/ARCHITECTURE.md)** - System architecture, component details, application stack, infrastructure as code, application features, and resiliency features
- **[Deployment Guide & Configuration](documentation/DEPLOYMENT.md)** - Step-by-step deployment, parameter configuration, environment variables, and customization options
- **[Monitoring & Troubleshooting](documentation/MONITORING.md)** - Health checks, log locations, PM2 management, database operations, and detailed troubleshooting guides

## 🤝 Contributing

Contributions are welcome! Please consider:
- Testing on Azure Local environments
- Improving resiliency features
- Adding monitoring capabilities
- Enhancing documentation

## 📝 License

This project is provided as a demonstration and reference architecture. Modify as needed for your use case.

## 🔗 Related Documentation

- [Azure Local Documentation](https://learn.microsoft.com/azure-stack/hci/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Next.js Documentation](https://nextjs.org/docs)
- [PostgreSQL Replication](https://www.postgresql.org/docs/16/high-availability.html)
- [NGINX Load Balancing](https://nginx.org/en/docs/http/load_balancing.html)

---

**Built with ❤️ for Azure Local demonstrations**
