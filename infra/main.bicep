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
}

@description('Static VM names for repeatable deployments')
var vmNames = {
  dbPrimary: '${projectName}-db-primary'
  dbReplica: '${projectName}-db-replica'
  webapp1: '${projectName}-webapp-01'
  webapp2: '${projectName}-webapp-02'
}

@description('Load balancer name')
var loadBalancerName = '${projectName}-lb'

@description('Public IP name for load balancer')
var publicIPName = '${projectName}-lb-publicip'

@description('Static IP assignments for all VMs')
param staticIPs object

@description('Availability zone assignments for VMs (zone 1 and zone 2 distribution)')
param placementZones object = {
  dbPrimary: '1'      // PostgreSQL Primary in zone 1
  dbReplica: '2'      // PostgreSQL Replica in zone 2 (separate from primary)
  webapp1: '1'        // Web App 01 in zone 1
  webapp2: '2'        // Web App 02 in zone 2 (separate from webapp1)
}

// Reference to existing storage account created in Step 1
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: scriptStorageAccount
}

// Script URLs from the existing storage account  
var blobEndpoint = existingStorageAccount.properties.primaryEndpoints.blob
var storageAccountKey = existingStorageAccount.listKeys().keys[0].value

// Deploy Public IP for Load Balancer
module publicIP 'modules/publicip.bicep' = {
  name: 'deploy-${publicIPName}'
  params: {
    publicIPAddressName: publicIPName
    location: location
    customLocationId: customLocationId
    logicalNetworkId: logicalNetworkId
    tags: {
      project: projectName
      component: 'load-balancer'
      deployment: 'ecommerce-resiliency-demo'
    }
  }
}

// Deploy Network Security Group first (required by all VMs)
// API version 2025-06-01-preview supports NSG association with network interfaces
// TEMPORARILY DISABLED FOR TROUBLESHOOTING
/*
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
*/

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
    // networkSecurityGroupId: nsg.outputs.networkSecurityGroupId  // TEMPORARILY DISABLED
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
    // networkSecurityGroupId: nsg.outputs.networkSecurityGroupId  // TEMPORARILY DISABLED
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
    // networkSecurityGroupId: nsg.outputs.networkSecurityGroupId  // TEMPORARILY DISABLED
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
    // networkSecurityGroupId: nsg.outputs.networkSecurityGroupId  // TEMPORARILY DISABLED
  }
}

// Deploy Native Azure Local Load Balancer (depends on webapp VMs for backend pool)
module loadBalancer 'modules/loadbalancer.bicep' = {
  name: 'deploy-${loadBalancerName}'
  params: {
    loadBalancerName: loadBalancerName
    location: location
    customLocationId: customLocationId
    logicalNetworkId: logicalNetworkId
    publicIPAddressId: publicIP.outputs.publicIPAddressId
    backendNicIPConfigs: [
      '${webapp1Vm.outputs.nicResourceId}/ipConfigurations/ipconfig1'
      '${webapp2Vm.outputs.nicResourceId}/ipConfigurations/ipconfig1'
    ]
    httpPort: 80
    httpsPort: 443
    backendHttpPort: 3000
    backendHttpsPort: 3000
    healthProbeProtocol: 'Http'
    healthProbePort: 3000
    healthProbeRequestPath: '/api/health'
    healthProbeIntervalInSeconds: 15
    healthProbeNumberOfProbes: 2
    loadDistribution: 'Default'
    idleTimeoutInMinutes: 4
    tags: {
      project: projectName
      component: 'load-balancer'
      deployment: 'ecommerce-resiliency-demo'
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Connection information for the deployed e-commerce application')
output applicationEndpoints object = {
  loadBalancerPublicIPId: publicIP.outputs.publicIPAddressId
  loadBalancerPublicIPName: publicIP.outputs.publicIPAddressName
  note: 'Get the public IP address using: az resource show --ids <publicIPId> --query properties.ipAddress -o tsv'
  databasePrimaryIP: staticIPs.dbPrimary
}

@description('VM resource IDs for all deployed virtual machines')
output vmResourceIds object = {
  databasePrimary: dbPrimaryVm.outputs.vmResourceId
  databaseReplica: dbReplicaVm.outputs.vmResourceId
  webapp1: webapp1Vm.outputs.vmResourceId
  webapp2: webapp2Vm.outputs.vmResourceId
}

@description('Load balancer resource information')
output loadBalancerInfo object = {
  resourceId: loadBalancer.outputs.loadBalancerId
  name: loadBalancer.outputs.loadBalancerName
  provisioningState: loadBalancer.outputs.provisioningState
  publicIPAddressId: publicIP.outputs.publicIPAddressId
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
}

// TEMPORARILY DISABLED FOR TROUBLESHOOTING
/*
@description('Network Security Group information')
output networkSecurityGroup object = {
  resourceId: nsg.outputs.networkSecurityGroupId
  name: nsg.outputs.networkSecurityGroupName
  provisioningState: nsg.outputs.provisioningState
  securityRulesSummary: nsg.outputs.securityRulesSummary
}
*/
