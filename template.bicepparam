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

// Static IP assignments for VMs (update these to match your network range)
// All IPs must be in the same subnet
param staticIPs = {
  dbPrimary: '192.168.x.21'
  dbReplica: '192.168.x.22'
  webapp1: '192.168.x.23'
  webapp2: '192.168.x.24'
}

// Note: Load balancer uses a public IP address (automatically created)
// No private frontend IP configuration needed

// Availability zone assignments for VM placement
// Distributes VMs across zones for high availability
// Leave zone value as empty string '' to disable zone placement for a specific VM
param placementZones = {
  dbPrimary: '1'    // Database primary in zone 1
  dbReplica: '2'    // Database replica in zone 2
  webapp1: '1'      // Web app 1 in zone 1
  webapp2: '2'      // Web app 2 in zone 2
}

// DNS configuration (OPTIONAL) - Configure custom DNS servers for VMs
// Leave empty to use DNS servers from the Logical Network (LNET)
param dnsServers = [''] // Example: Azure DNS - param dnsServers = ['168.63.129.16']

// Proxy configuration (OPTIONAL) - Configure if VMs need to access internet through a proxy
// Leave these empty to disable proxy configuration
param httpProxy = '' // Example: 'http://proxy.example.com:3128'
param httpsProxy = '' // Example: 'http://proxy.example.com:3128'
param noProxy = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'
param proxyCertificate = '' // Certificate content or file path for proxy authentication


// Admin credentials - CHANGE THESE VALUES!
param adminUsername = 'azureuser'
param adminPassword = 'ChangeThisPassword123!' // REQUIRED - Change this to a secure password

// Service credentials - CHANGE THIS VALUE!
param servicePassword = 'ChangeThisServicePassword123!' // Used for database and other services

// SSH Authentication (OPTIONAL) - Adds SSH key authentication IN ADDITION to password
// Uncomment and update the path to your public key file:
// param sshPublicKey = loadTextContent('./.ssh/id_rsa.pub')

// Network Security Group Configuration (OPTIONAL)
// Restrict SSH access to specific management subnet/IP
// Default: '*' allows SSH from anywhere (restrict in production)
// Examples: '192.168.1.0/24' or '10.0.0.10/32' for specific subnet/IP
param managementSourcePrefix = '*' // CHANGE THIS in production to your management subnet
