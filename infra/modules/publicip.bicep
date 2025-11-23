// Public IP Address module for Azure Local Load Balancer

@description('Name of the public IP address')
param publicIPAddressName string

@description('Azure region for resource metadata')
param location string

@description('Full resource ID of the Azure Local custom location')
param customLocationId string

@description('Full resource ID of the Azure Local logical network (subnet)')
param logicalNetworkId string

@description('Tags for the public IP address')
param tags object = {}

@description('IP address version (IPv4 or IPv6)')
param publicIPAddressVersion string = 'IPv4'

// Create Public IP Address for load balancer
resource publicIPAddress 'Microsoft.AzureStackHCI/publicIPAddresses@2025-09-01-preview' = {
  name: publicIPAddressName
  location: location
  tags: tags
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    publicIPAddressVersion: publicIPAddressVersion
    ipAllocationScope: logicalNetworkId
  }
}

@description('Resource ID of the public IP address')
output publicIPAddressId string = publicIPAddress.id

@description('Name of the public IP address')
output publicIPAddressName string = publicIPAddress.name

@description('Provisioning state of the public IP address')
output provisioningState string = publicIPAddress.properties.provisioningState
