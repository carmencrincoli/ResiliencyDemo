// Native Azure Local Load Balancer module for E-commerce application
// Replaces the previous NGINX-based VM load balancer with Azure Local's native load balancer

@description('Name of the load balancer')
param loadBalancerName string

@description('Azure region for resource metadata')
param location string

@description('Full resource ID of the Azure Local custom location')
param customLocationId string

@description('Full resource ID of the Azure Local logical network')
param logicalNetworkId string

@description('Resource ID of public IP for the load balancer frontend (required for external load balancer)')
param publicIPAddressId string

@description('Array of backend web application VM network interface IP configuration resource IDs')
param backendNicIPConfigs array

@description('Frontend port for HTTP traffic (default: 80)')
param httpPort int = 80

@description('Backend port for HTTP traffic on web apps (default: 3000)')
param backendHttpPort int = 3000

@description('Frontend port for HTTPS traffic (default: 443)')
param httpsPort int = 443

@description('Backend port for HTTPS traffic on web apps (default: 3000)')
param backendHttpsPort int = 3000

@description('Health probe protocol (Http or Tcp)')
param healthProbeProtocol string = 'Http'

@description('Health probe port')
param healthProbePort int = 3000

@description('Health probe request path (required for HTTP probes)')
param healthProbeRequestPath string = '/api/health'

@description('Health probe interval in seconds')
param healthProbeIntervalInSeconds int = 15

@description('Number of probes for health check')
param healthProbeNumberOfProbes int = 2

@description('Load distribution mode (Default, SourceIP, or SourceIPProtocol)')
param loadDistribution string = 'Default'

@description('Idle timeout in minutes for TCP connections')
param idleTimeoutInMinutes int = 4

@description('Tags for the load balancer')
param tags object = {}

// Frontend IP configuration with public IP
var frontendIPConfigurations = [
  {
    name: 'web-frontend'
    properties: {
      publicIPAddress: {
        resourceId: publicIPAddressId
      }
    }
  }
]

// Backend address pool with web application VMs
var loadBalancerBackendAddresses = [for (nicIPConfig, i) in backendNicIPConfigs: {
  name: 'webapp-${i + 1}'
  properties: {
    networkInterfaceIPConfiguration: {
      resourceId: nicIPConfig
    }
    adminState: 'Up'
  }
}]

var backendAddressPools = [
  {
    name: 'web-backend-pool'
    properties: {
      logicalNetwork: {
        id: logicalNetworkId
      }
      loadBalancerBackendAddresses: loadBalancerBackendAddresses
    }
  }
]

// Health probe for web application health check
var probes = [
  {
    name: 'webapp-health-probe'
    properties: {
      protocol: healthProbeProtocol
      port: healthProbePort
      requestPath: healthProbeProtocol == 'Http' ? healthProbeRequestPath : null
      intervalInSeconds: healthProbeIntervalInSeconds
      numberOfProbes: healthProbeNumberOfProbes
    }
  }
]

// Load balancing rules for HTTP and HTTPS traffic
var loadBalancingRules = [
  {
    name: 'http-rule'
    properties: {
      frontendIPConfiguration: {
        name: 'web-frontend'
      }
      backendAddressPool: {
        name: 'web-backend-pool'
      }
      probe: {
        name: 'webapp-health-probe'
      }
      protocol: 'Tcp'
      frontendPort: httpPort
      backendPort: backendHttpPort
      loadDistribution: loadDistribution
      idleTimeoutInMinutes: idleTimeoutInMinutes
    }
  }
  {
    name: 'https-rule'
    properties: {
      frontendIPConfiguration: {
        name: 'web-frontend'
      }
      backendAddressPool: {
        name: 'web-backend-pool'
      }
      probe: {
        name: 'webapp-health-probe'
      }
      protocol: 'Tcp'
      frontendPort: httpsPort
      backendPort: backendHttpsPort
      loadDistribution: loadDistribution
      idleTimeoutInMinutes: idleTimeoutInMinutes
    }
  }
]

// Deploy Azure Local Load Balancer
resource loadBalancer 'Microsoft.AzureStackHCI/loadBalancers@2025-09-01-preview' = {
  name: loadBalancerName
  location: location
  tags: tags
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    frontendIPConfigurations: frontendIPConfigurations
    backendAddressPools: backendAddressPools
    probes: probes
    loadBalancingRules: loadBalancingRules
  }
}

@description('Resource ID of the load balancer')
output loadBalancerId string = loadBalancer.id

@description('Name of the load balancer')
output loadBalancerName string = loadBalancer.name

@description('Provisioning state of the load balancer')
output provisioningState string = loadBalancer.properties.provisioningState

@description('Public IP address resource ID')
output publicIPAddressId string = publicIPAddressId
