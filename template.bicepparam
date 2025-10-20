using './infra/main.bicep'

// Basic configuration
param projectName = 'ecommdemo'

// Azure Stack HCI configuration - Update these to match your Azure Local environment
// These 3 values should be the FULL resource ID of your custom location
param customLocationId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/your-azure-local-rg/providers/Microsoft.ExtendedLocation/customLocations/your-custom-location'
param logicalNetworkId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/your-network-resource-group/providers/Microsoft.AzureStackHCI/logicalnetworks/your-logical-network-name'
param vmImageId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/your-image-resource-group/providers/Microsoft.AzureStackHCI/galleryImages/ubuntu2404-lts-image-name'

// This is just the name of the storage account itself
param scriptStorageAccount = '' // Leave empty to auto-generate, or specify existing storage account name

// Static IP assignments (update these to match your network range)
// All IPs must be in the same subnet
param staticIPs = {
  loadBalancer: '192.168.x.20'
  dbPrimary: '192.168.x.21'
  dbReplica: '192.168.x.22'
  webapp1: '192.168.x.23'
  webapp2: '192.168.x.24'
}

// Admin credentials - CHANGE THESE VALUES!
param adminUsername = 'azureuser'
param adminPassword = 'ChangeThisPassword123!' // REQUIRED - Change this to a secure password

// Service credentials - CHANGE THIS VALUE!
param servicePassword = 'ChangeThisServicePassword123!' // Used for database and other services

// Proxy configuration (OPTIONAL) - Configure if VMs need to access internet through a proxy
// Leave these empty to disable proxy configuration
param httpProxy = '' // Example: 'http://proxy.example.com:3128'
param httpsProxy = '' // Example: 'http://proxy.example.com:3128'
param noProxy = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'
param proxyCertificate = '' // Certificate content or file path for proxy authentication

// SSH Authentication (OPTIONAL) - Adds SSH key authentication IN ADDITION to password
// Uncomment and update the path to your public key file:
// param sshPublicKey = loadTextContent('./.ssh/id_rsa.pub')
