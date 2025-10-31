// Main orchestrating template for E-commerce application deployment on Azure Local
// This template deploys all VMs in the correct sequence with dependencies

targetScope = 'resourceGroup'

@description('Base name for all resources. This will be used to generate unique names for VMs and other resources.')
param projectName string = 'ecommerce'

@description('Azure region for resource metadata')
param location string = resourceGroup().location

@description('Full resource ID of the Azure Local custom location (e.g., /subscriptions/.../resourceGroups/.../providers/Microsoft.ExtendedLocation/customLocations/...)')
param customLocationId string

@description('Full resource ID of the Azure Local logical network (e.g., /subscriptions/.../resourceGroups/.../providers/Microsoft.AzureStackHCI/logicalnetworks/...)')
param logicalNetworkId string

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

@description('Full resource ID of the VM image for Ubuntu 22.04 (e.g., /subscriptions/.../resourceGroups/.../providers/Microsoft.AzureStackHCI/galleryImages/...)')
param vmImageId string

@description('Name of the pre-created storage account containing deployment scripts')
param scriptStorageAccount string

@description('HTTP proxy server URL (optional - leave empty to disable proxy)')
@secure()
param httpProxy string = ''

@description('HTTPS proxy server URL (optional - leave empty to disable proxy)')
@secure()
param httpsProxy string = ''

@description('URLs that should bypass the proxy (optional - comma-separated list)')
param noProxy string = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'

@description('Certificate file path or content for proxy authentication (optional)')
param proxyCertificate string = ''

@description('Custom DNS servers for VMs (optional - leave empty to use LNET defaults)')
param dnsServers array = []

@description('Management subnet or IP range that should have SSH access (default: allow from anywhere - restrict in production)')
param managementSourcePrefix string = '*'

@description('Common VM configuration')
var vmConfig = {
  size: 'Custom'
  adminUsername: adminUsername
  imageId: vmImageId
  customLocationId: customLocationId
  logicalNetworkId: logicalNetworkId
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

@description('Static VM names for repeatable deployments')
var vmNames = {
  dbPrimary: '${projectName}-db-primary'
  dbReplica: '${projectName}-db-replica'
  webapp1: '${projectName}-webapp-01'
  webapp2: '${projectName}-webapp-02'
  loadBalancer: '${projectName}-nginx-lb'
}

@description('Static IP assignments for all VMs')
param staticIPs object

@description('Availability zone assignments for VMs (zone 1 and zone 2 distribution)')
param placementZones object = {
  dbPrimary: '1'      // PostgreSQL Primary in zone 1
  dbReplica: '2'      // PostgreSQL Replica in zone 2 (separate from primary)
  webapp1: '1'        // Web App 01 in zone 1
  webapp2: '2'        // Web App 02 in zone 2 (separate from webapp1)
  loadBalancer: '1'   // Load Balancer in zone 1
}

// Reference to existing storage account created in Step 1
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: scriptStorageAccount
}

// Script URLs from the existing storage account  
var blobEndpoint = existingStorageAccount.properties.primaryEndpoints.blob
var storageAccountKey = existingStorageAccount.listKeys().keys[0].value

// Deploy Network Security Group first (required by all VMs)
// API version 2025-06-01-preview supports NSG association with network interfaces
module nsg 'modules/nsg.bicep' = {
  name: 'deploy-nsg'
  params: {
    networkSecurityGroupName: '${projectName}-nsg'
    location: location
    customLocationId: customLocationId
    staticIPs: staticIPs
    managementSourcePrefix: managementSourcePrefix
    tags: {
      project: projectName
      component: 'security'
      deployment: 'ecommerce-resiliency-demo'
    }
  }
}

// Deploy PostgreSQL Primary VM first (foundation dependency)
module dbPrimaryVm 'modules/pg-primary-vm.bicep' = {
  name: 'deploy-${vmNames.dbPrimary}'
  params: {
    vmName: vmNames.dbPrimary
    location: location
    vmConfig: vmConfig
    httpProxy: httpProxy
    httpsProxy: httpsProxy
    noProxy: noProxy
    proxyCertificate: proxyCertificate
    staticIP: staticIPs.dbPrimary
    replicaIP: staticIPs.dbReplica
    storageAccountUrl: blobEndpoint
    storageAccountName: scriptStorageAccount
    storageAccountKey: storageAccountKey
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    processors: vmResources.database.processors
    memoryMB: vmResources.database.memoryMB
    placementZone: placementZones.dbPrimary
    networkSecurityGroupId: nsg.outputs.networkSecurityGroupId
  }
}

// Deploy PostgreSQL Replica VM (no dependency - will retry connection to primary)
module dbReplicaVm 'modules/pg-replica-vm.bicep' = {
  name: 'deploy-${vmNames.dbReplica}'
  params: {
    vmName: vmNames.dbReplica
    location: location
    vmConfig: vmConfig
    httpProxy: httpProxy
    httpsProxy: httpsProxy
    noProxy: noProxy
    proxyCertificate: proxyCertificate
    staticIP: staticIPs.dbReplica
    primaryIP: staticIPs.dbPrimary
    storageAccountUrl: blobEndpoint
    storageAccountName: scriptStorageAccount
    storageAccountKey: storageAccountKey
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    dnsServers: dnsServers
    processors: vmResources.database.processors
    memoryMB: vmResources.database.memoryMB
    placementZone: placementZones.dbReplica
    networkSecurityGroupId: nsg.outputs.networkSecurityGroupId
  }
}

// Deploy Web Application VMs (no dependency - can handle database connectivity gracefully)
module webapp1Vm 'modules/webapp-vm.bicep' = {
  name: 'deploy-${vmNames.webapp1}'
  params: {
    vmName: vmNames.webapp1
    location: location
    vmConfig: vmConfig
    httpProxy: httpProxy
    httpsProxy: httpsProxy
    noProxy: noProxy
    proxyCertificate: proxyCertificate
    staticIP: staticIPs.webapp1
    databasePrimaryIP: staticIPs.dbPrimary
    databaseReplicaIP: staticIPs.dbReplica
    storageAccountUrl: blobEndpoint
    storageAccountName: scriptStorageAccount
    storageAccountKey: storageAccountKey
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    dnsServers: dnsServers
    processors: vmResources.webapp.processors
    memoryMB: vmResources.webapp.memoryMB
    placementZone: placementZones.webapp1
    networkSecurityGroupId: nsg.outputs.networkSecurityGroupId
  }
}

module webapp2Vm 'modules/webapp-vm.bicep' = {
  name: 'deploy-${vmNames.webapp2}'
  params: {
    vmName: vmNames.webapp2
    location: location
    vmConfig: vmConfig
    httpProxy: httpProxy
    httpsProxy: httpsProxy
    noProxy: noProxy
    proxyCertificate: proxyCertificate
    staticIP: staticIPs.webapp2
    databasePrimaryIP: staticIPs.dbPrimary
    databaseReplicaIP: staticIPs.dbReplica
    storageAccountUrl: blobEndpoint
    storageAccountName: scriptStorageAccount
    storageAccountKey: storageAccountKey
    servicePassword: servicePassword
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    dnsServers: dnsServers
    processors: vmResources.webapp.processors
    memoryMB: vmResources.webapp.memoryMB
    placementZone: placementZones.webapp2
    networkSecurityGroupId: nsg.outputs.networkSecurityGroupId
  }
}

// Deploy Load Balancer VM (no dependency - can handle backend connectivity gracefully)
module loadBalancerVm 'modules/loadbalancer-vm.bicep' = {
  name: 'deploy-${vmNames.loadBalancer}'
  params: {
    vmName: vmNames.loadBalancer
    location: location
    vmConfig: vmConfig
    httpProxy: httpProxy
    httpsProxy: httpsProxy
    noProxy: noProxy
    proxyCertificate: proxyCertificate
    staticIP: staticIPs.loadBalancer
    webapp1IP: staticIPs.webapp1
    webapp2IP: staticIPs.webapp2
    storageAccountUrl: blobEndpoint
    storageAccountName: scriptStorageAccount
    storageAccountKey: storageAccountKey
    adminPassword: adminPassword
    sshPublicKey: sshPublicKey
    dnsServers: dnsServers
    processors: vmResources.loadBalancer.processors
    memoryMB: vmResources.loadBalancer.memoryMB
    placementZone: placementZones.loadBalancer
    networkSecurityGroupId: nsg.outputs.networkSecurityGroupId
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

@description('Network Security Group information')
output networkSecurityGroup object = {
  resourceId: nsg.outputs.networkSecurityGroupId
  name: nsg.outputs.networkSecurityGroupName
  provisioningState: nsg.outputs.provisioningState
  securityRulesSummary: nsg.outputs.securityRulesSummary
}
