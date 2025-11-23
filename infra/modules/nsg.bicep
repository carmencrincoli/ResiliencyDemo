// Network Security Group module for E-commerce Application on Azure Local
// This NSG secures all components: Load Balancer, Web Apps, and Database servers

@description('Name of the network security group')
param networkSecurityGroupName string

@description('Azure region for resource metadata')
param location string = resourceGroup().location

@description('Full resource ID of the Azure Local custom location')
param customLocationId string

@description('Tags for the network security group resource')
param tags object = {}

@description('Static IP addresses for all VMs to create precise security rules')
param staticIPs object

@description('Management subnet or IP range that should have SSH access (e.g., 192.168.2.0/24 or specific admin IP)')
param managementSourcePrefix string = '*'

// Create the Network Security Group
resource networkSecurityGroup 'Microsoft.AzureStackHCI/networkSecurityGroups@2025-09-01-preview' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {}
}

// Security Rules deployed as child resources
// Priority ranges: 100-199 (Inbound Internet), 200-299 (Internal services), 300-399 (Management), 4000+ (Deny rules)

// ============================================================================
// PUBLIC INTERNET ACCESS RULES (Priority 100-199)
// ============================================================================
// Note: Load balancer uses public IP - internet traffic rules managed at platform level

// ============================================================================
// INTERNAL SERVICE ACCESS RULES (Priority 200-299)
// ============================================================================

@description('Allow traffic to Web App servers on port 3000 (for native load balancer and health probes)')
resource allowToWebApps 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-to-webapps'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow traffic to Web App servers on port 3000 for native load balancer traffic and health probes'
    protocol: 'Tcp'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: [staticIPs.webapp1, staticIPs.webapp2]
    sourcePortRanges: ['*']
    destinationPortRanges: ['3000']
    access: 'Allow'
    priority: 200
    direction: 'Inbound'
  }
}

@description('Allow Web Apps to PostgreSQL Primary on port 5432')
resource allowWebAppsToPgPrimary 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-webapps-to-pg-primary'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow Web App servers to connect to PostgreSQL Primary on port 5432'
    protocol: 'Tcp'
    sourceAddressPrefixes: [staticIPs.webapp1, staticIPs.webapp2]
    destinationAddressPrefixes: [staticIPs.dbPrimary]
    sourcePortRanges: ['*']
    destinationPortRanges: ['5432']
    access: 'Allow'
    priority: 210
    direction: 'Inbound'
  }
}

@description('Allow Web Apps to PostgreSQL Replica on port 5432 (failover)')
resource allowWebAppsToPgReplica 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-webapps-to-pg-replica'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow Web App servers to connect to PostgreSQL Replica on port 5432 (for failover)'
    protocol: 'Tcp'
    sourceAddressPrefixes: [staticIPs.webapp1, staticIPs.webapp2]
    destinationAddressPrefixes: [staticIPs.dbReplica]
    sourcePortRanges: ['*']
    destinationPortRanges: ['5432']
    access: 'Allow'
    priority: 220
    direction: 'Inbound'
  }
}

@description('Allow PostgreSQL replication from Primary to Replica on port 5432')
resource allowPgReplication 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-pg-replication'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow PostgreSQL streaming replication from Primary to Replica on port 5432'
    protocol: 'Tcp'
    sourceAddressPrefixes: [staticIPs.dbReplica]
    destinationAddressPrefixes: [staticIPs.dbPrimary]
    sourcePortRanges: ['*']
    destinationPortRanges: ['5432']
    access: 'Allow'
    priority: 230
    direction: 'Inbound'
  }
}

// ============================================================================
// MANAGEMENT ACCESS RULES (Priority 300-399)
// ============================================================================

@description('Allow SSH access from management network to all VMs')
resource allowSshManagement 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-ssh-management'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow SSH (port 22) access from management network to all VMs for administration'
    protocol: 'Tcp'
    sourceAddressPrefixes: [managementSourcePrefix]
    destinationAddressPrefixes: [
      staticIPs.webapp1
      staticIPs.webapp2
      staticIPs.dbPrimary
      staticIPs.dbReplica
    ]
    sourcePortRanges: ['*']
    destinationPortRanges: ['22']
    access: 'Allow'
    priority: 300
    direction: 'Inbound'
  }
}

// ============================================================================
// OUTBOUND RULES
// ============================================================================

@description('Allow all outbound traffic (for updates, package downloads, etc.)')
resource allowAllOutbound 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-all-outbound'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow all outbound traffic for OS updates, package downloads, and external API calls'
    protocol: '*'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['*']
    sourcePortRanges: ['*']
    destinationPortRanges: ['*']
    access: 'Allow'
    priority: 100
    direction: 'Outbound'
  }
}

// ============================================================================
// DENY RULES (Priority 4000+)
// ============================================================================

@description('Deny all other inbound traffic not explicitly allowed')
resource denyAllInbound 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'deny-all-inbound'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Deny all other inbound traffic not explicitly allowed by higher priority rules'
    protocol: '*'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: ['*']
    sourcePortRanges: ['*']
    destinationPortRanges: ['*']
    access: 'Deny'
    priority: 4096
    direction: 'Inbound'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource ID of the created network security group')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('Name of the created network security group')
output networkSecurityGroupName string = networkSecurityGroup.name

@description('Provisioning state of the network security group')
output provisioningState string = networkSecurityGroup.properties.provisioningState

@description('Summary of security rules created')
output securityRulesSummary object = {
  inboundRules: [
    'Traffic → Web Apps (3000) for LB and health probes'
    'Web Apps → PostgreSQL Primary (5432)'
    'Web Apps → PostgreSQL Replica (5432)'
    'PostgreSQL Primary → Replica Replication (5432)'
    'SSH (22) → All VMs from Management Network'
  ]
  outboundRules: [
    'All outbound traffic allowed'
  ]
  denyRules: [
    'All other inbound traffic denied'
  ]
  note: 'Load balancer uses public IP - internet traffic rules managed at platform level'
}
