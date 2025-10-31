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
- **Network Security Group** with comprehensive security rules for all components
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
- **Virtual Network** with sufficient address space for 5 VMs
  - Supports any subnet size (e.g., /24, /25, /26, /27, or larger)
  - All 5 IPs must be in the same subnet
- **Outbound Internet Access** for package downloads
- **Azure Storage Access** for deployment scripts

## 🚀 Quick Start

### 1. Clone the Repository
```powershell
git clone https://github.com/carmencrincoli/ResiliencyDemo.git
cd ResiliencyDemo
```

### 2. Configure Parameters
**Important**: Create your own parameters file from the template:
```powershell
# Copy the template
Copy-Item template.bicepparam main.bicepparam

# Edit main.bicepparam with your environment details
```

Edit `main.bicepparam` with your specific values:
```bicep
param customLocationName = 'your-custom-location'
param logicalNetworkName = 'your-logical-network'
param azureLocalResourceGroup = 'your-azure-local-rg'
param vmImageName = 'ubuntu2404-lts-image-name'

param staticIPs = {
  loadBalancer: '192.168.x.20'
  dbPrimary: '192.168.x.21'
  dbReplica: '192.168.x.22'
  webapp1: '192.168.x.23'
  webapp2: '192.168.x.24'
}

param adminPassword = 'YourSecurePassword!'
param servicePassword = 'YourDatabasePassword!'

# OPTIONAL: Enable SSH key authentication (recommended for production)
# param sshPublicKey = loadTextContent('~/.ssh/id_rsa.pub')
```

> ⚠️ **Security Note**: The `main.bicepparam` file is in `.gitignore` and will NOT be committed to your repository. This keeps your passwords and configuration private. Always use the `template.bicepparam` as your starting point.

> 💡 **Tip**: For enhanced security, consider using SSH key authentication instead of passwords. See the [SSH Authentication Guide](documentation/SSH_AUTHENTICATION.md) for details.

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

## 📋 Documentation

Detailed documentation is organized into focused guides:

- **[Architecture & Application Stack](documentation/ARCHITECTURE.md)** - System architecture, component details, application stack, infrastructure as code, application features, and resiliency features
- **[Deployment Guide & Configuration](documentation/DEPLOYMENT.md)** - Step-by-step deployment, parameter configuration, environment variables, and customization options
- **[Network Security](documentation/NETWORK_SECURITY.md)** - Network Security Group configuration, security rules, best practices, and troubleshooting
- **[SSH Authentication](documentation/SSH_AUTHENTICATION.md)** - Configure SSH key-based authentication for secure VM access (recommended for production)
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
