using './infra/main.bicep'

// Basic configuration
param projectName = 'ecommdemo'

// Azure Stack HCI configuration - Update these to match your Azure Local environment
param customLocationName = 'your-custom-location-name'
param logicalNetworkName = 'your-logical-network-name'
param azureLocalResourceGroup = 'your-azure-local-resource-group'
param vmImageName = 'ubuntu2404-lts-image-name'
param scriptStorageAccount = '' // Leave empty to auto-generate, or specify existing storage account name

// Static IP assignments (update these to match your network range)
// IMPORTANT: Must be in a /24 subnet (255.255.255.0)
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

// SSH Authentication (OPTIONAL) - Adds SSH key authentication IN ADDITION to password
// Uncomment and update the path to your public key file:
// param sshPublicKey = loadTextContent('./.ssh/id_rsa.pub')

// Service credentials - CHANGE THIS VALUE!
param servicePassword = 'ChangeThisServicePassword123!' // Used for database and other services
