// Main orchestrating template for E-commerce application deployment on Azure Local
// This template deploys all VMs in the correct sequence with dependencies

targetScope = 'resourceGroup'

@description('Base name for all resources. This will be used to generate unique names for VMs and other resources.')
param projectName string = 'ecommerce'

@description('Azure region for resource metadata')
param location string = resourceGroup().location

@description('Name of the Azure Local custom location')
param customLocationName string

@description('Name of the Azure Local logical network')
param logicalNetworkName string

@description('Resource group name where the custom location and logical network are located')
param azureLocalResourceGroup string

@description('VM administrator username')
param adminUsername string

@description('VM administrator password')
@secure()
param adminPassword string

@description('SSH public key for admin user authentication (optional - adds SSH key authentication in addition to password)')
@secure()
param sshPublicKey string = ''

@description('Service password for databases, Redis, etc. (shared across all services)')
@secure()
param servicePassword string

@description('VM image name for Ubuntu 22.04 (used for all VMs)')
param vmImageName string

@description('Name of the pre-created storage account containing deployment scripts')
param scriptStorageAccount string

@description('Timestamp parameter for additional randomization')
param timestamp string = utcNow()

@description('Resource token for unique naming - combines multiple entropy sources for better randomization')
var resourceToken = substring(uniqueString(resourceGroup().id, deployment().name, timestamp), 0, 6)

@description('Common VM configuration')
var vmConfig = {
  size: 'Custom'
  adminUsername: adminUsername
  imageName: vmImageName
  customLocationName: customLocationName
  logicalNetworkName: logicalNetworkName
  azureLocalResourceGroup: azureLocalResourceGroup
}

@description('VM resource allocations optimized for demo environment with minimal resource usage')
var vmResources = {
  database: {
    processors: 4
    memoryMB: 8192    // 8GB - PostgreSQL needs moderate resources
  }
  webapp: {
    processors: 4
    memoryMB: 6144    // 6GB - Next.js full-stack web application
  }
  loadBalancer: {
    processors: 2
    memoryMB: 2048    // 2GB - NGINX reverse proxy
  }
}

@description('Generate unique VM names')
var vmNames = {
  dbPrimary: '${projectName}-db-primary-${resourceToken}'
  dbReplica: '${projectName}-db-replica-${resourceToken}'
  webapp1: '${projectName}-webapp-01-${resourceToken}'
  webapp2: '${projectName}-webapp-02-${resourceToken}'
  loadBalancer: '${projectName}-nginx-lb-${resourceToken}'
}

@description('Static IP assignments for all VMs')
param staticIPs object

// Reference to existing storage account created in Step 1
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: scriptStorageAccount
}

// Script URLs from the existing storage account  
// Format: https://account.blob.core.windows.net/container/blob-path
var blobEndpoint = existingStorageAccount.properties.primaryEndpoints.blob
var scriptUrls = {
  postgresqlPrimary: '${blobEndpoint}assets/deployscripts/pg-primary-setup.sh'
  postgresqlReplica: '${blobEndpoint}assets/deployscripts/pg-replica-setup.sh'
  webapp: '${blobEndpoint}assets/deployscripts/webapp-setup.sh'
  loadbalancer: '${blobEndpoint}assets/deployscripts/loadbalancer-setup.sh'
  bashinstaller: '${blobEndpoint}assets/deployscripts/bash-installer.sh'
}

// Deploy PostgreSQL Primary VM first (foundation dependency)
module dbPrimaryVm 'modules/pg-primary-vm.bicep' = {
  name: 'deploy-${vmNames.dbPrimary}'
  params: {
    vmName: vmNames.dbPrimary
    location: location
    vmConfig: vmConfig
    staticIP: staticIPs.dbPrimary
    replicaIP: staticIPs.dbReplica
    scriptUrl: scriptUrls.postgresqlPrimary
    bashInstallerUrl: scriptUrls.bashinstaller
    storageAccountUrl: blobEndpoint
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.database.processors
    memoryMB: vmResources.database.memoryMB
  }
}

// Deploy PostgreSQL Replica VM (no dependency - will retry connection to primary)
module dbReplicaVm 'modules/pg-replica-vm.bicep' = {
  name: 'deploy-${vmNames.dbReplica}'
  params: {
    vmName: vmNames.dbReplica
    location: location
    vmConfig: vmConfig
    staticIP: staticIPs.dbReplica
    primaryIP: staticIPs.dbPrimary
    scriptUrl: scriptUrls.postgresqlReplica
    bashInstallerUrl: scriptUrls.bashinstaller
    storageAccountUrl: blobEndpoint
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.database.processors
    memoryMB: vmResources.database.memoryMB
  }
}

// Deploy Web Application VMs (no dependency - can handle database connectivity gracefully)
module webapp1Vm 'modules/webapp-vm.bicep' = {
  name: 'deploy-${vmNames.webapp1}'
  params: {
    vmName: vmNames.webapp1
    location: location
    vmConfig: vmConfig
    staticIP: staticIPs.webapp1
    databasePrimaryIP: staticIPs.dbPrimary
    databaseReplicaIP: staticIPs.dbReplica
    scriptUrl: scriptUrls.webapp
    bashInstallerUrl: scriptUrls.bashinstaller
    storageAccountUrl: blobEndpoint
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.webapp.processors
    memoryMB: vmResources.webapp.memoryMB
  }
}

module webapp2Vm 'modules/webapp-vm.bicep' = {
  name: 'deploy-${vmNames.webapp2}'
  params: {
    vmName: vmNames.webapp2
    location: location
    vmConfig: vmConfig
    staticIP: staticIPs.webapp2
    databasePrimaryIP: staticIPs.dbPrimary
    databaseReplicaIP: staticIPs.dbReplica
    scriptUrl: scriptUrls.webapp
    bashInstallerUrl: scriptUrls.bashinstaller
    storageAccountUrl: blobEndpoint
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.webapp.processors
    memoryMB: vmResources.webapp.memoryMB
  }
}

// Deploy Load Balancer VM (no dependency - can handle backend connectivity gracefully)
module loadBalancerVm 'modules/loadbalancer-vm.bicep' = {
  name: 'deploy-${vmNames.loadBalancer}'
  params: {
    vmName: vmNames.loadBalancer
    location: location
    vmConfig: vmConfig
    staticIP: staticIPs.loadBalancer
    webapp1IP: staticIPs.webapp1
    webapp2IP: staticIPs.webapp2
    scriptUrl: scriptUrls.loadbalancer
    bashInstallerUrl: scriptUrls.bashinstaller
    storageAccountUrl: blobEndpoint
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.loadBalancer.processors
    memoryMB: vmResources.loadBalancer.memoryMB
  }
}

// Outputs for verification and connection information
@description('Connection information for the deployed e-commerce application')
output applicationEndpoints object = {
  loadBalancerIP: staticIPs.loadBalancer
  loadBalancerHttps: 'https://${staticIPs.loadBalancer}'
  loadBalancerHttp: 'http://${staticIPs.loadBalancer}'
  databasePrimaryIP: staticIPs.dbPrimary
}

@description('VM deployment status and resource IDs')
output vmResourceIds object = {
  databasePrimary: dbPrimaryVm.outputs.vmResourceId
  databaseReplica: dbReplicaVm.outputs.vmResourceId
  webapp1: webapp1Vm.outputs.vmResourceId
  webapp2: webapp2Vm.outputs.vmResourceId
  loadBalancer: loadBalancerVm.outputs.vmResourceId
}

@description('Database connection information for applications')
output databaseConnectionInfo object = {
  host: staticIPs.dbPrimary
  port: 5432
  database: 'ecommerce'
  username: 'ecommerce_user'
}

@description('SSH connection information for all VMs')
output sshConnectionInfo object = {
  databasePrimary: dbPrimaryVm.outputs.connectionInfo.sshCommand
  databaseReplica: dbReplicaVm.outputs.connectionInfo.sshCommand
  webapp1: webapp1Vm.outputs.connectionInfo.sshCommand
  webapp2: webapp2Vm.outputs.connectionInfo.sshCommand
  loadBalancer: loadBalancerVm.outputs.connectionInfo.sshCommand
}
