// SSH Configuration module for Azure Arc-enabled VMs
// This module automatically enables SSH access on port 22 for Arc-enabled servers

@description('Name of the Arc-enabled machine')
param machineName string

@description('SSH port to enable (default 22)')
param sshPort int = 22

// Reference to the existing Azure Arc machine
resource arcMachine 'Microsoft.HybridCompute/machines@2023-10-03-preview' existing = {
  name: machineName
}

// Create the default connectivity endpoint
resource connectivityEndpoint 'Microsoft.HybridConnectivity/endpoints@2023-03-15' = {
  name: 'default'
  scope: arcMachine
  properties: {
    type: 'default'
  }
}

// Configure SSH service on the connectivity endpoint
resource sshServiceConfiguration 'Microsoft.HybridConnectivity/endpoints/serviceConfigurations@2023-03-15' = {
  name: 'SSH'
  parent: connectivityEndpoint
  properties: {
    serviceName: 'SSH'
    port: sshPort
  }
}

@description('SSH service configuration resource ID')
output sshConfigurationId string = sshServiceConfiguration.id

@description('Connectivity endpoint resource ID')
output connectivityEndpointId string = connectivityEndpoint.id

@description('SSH connection information')
output sshConnectionInfo object = {
  machineName: machineName
  sshPort: sshPort
  sshCommand: 'az ssh arc --resource-group ${resourceGroup().name} --vm-name ${machineName}'
}
