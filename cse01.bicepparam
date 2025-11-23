using './infra/main.bicep'

// Basic configuration
param projectName = 'ecdemo'

// Azure Stack HCI configuration - Update these to match your Azure Local environment
// These 3 values should be the FULL resource ID of your custom location
param customLocationId = '/subscriptions/dded2b99-4218-4521-875b-3652a68bb91f/resourceGroups/cse01-ied7jmliy42i2-HostedResources-508D7E31/providers/Microsoft.ExtendedLocation/customLocations/cse01-ied7jmliy42i2-cstm-loc'
param logicalNetworkId = '/subscriptions/fca2e8ee-1179-48b8-9532-428ed0873a2e/resourceGroups/cc-lnet/providers/Microsoft.AzureStackHCI/logicalNetworks/cc-lnet-vlan750'
param vmImageId = '/subscriptions/fca2e8ee-1179-48b8-9532-428ed0873a2e/resourceGroups/cc-images/providers/Microsoft.AzureStackHCI/galleryImages/Ubuntu2404Min'

// This is just the name of the storage account itself
param scriptStorageAccount = '' // Leave empty to auto-generate, or specify existing storage account name

// Static IP assignments (update these to match your network range)
// All IPs must be in the same subnet
param staticIPs = {
  dbPrimary: '10.40.132.121'
  dbReplica: '10.40.132.122'
  webapp1: '10.40.132.123'
  webapp2: '10.40.132.124'
}

// DNS configuration (OPTIONAL) - Configure custom DNS servers for VMs
// Leave empty to use DNS servers from the Logical Network (LNET)
param dnsServers = ['10.251.37.6'] // Example: Azure DNS - param dnsServers = ['168.63.129.16']

// Proxy configuration (OPTIONAL) - Configure if VMs need to access internet through a proxy
// Leave these empty to disable proxy configuration
param httpProxy = 'http://10.251.37.6:3128' // Example: 'http://proxy.example.com:3128'
param httpsProxy = 'http://10.251.37.6:3128' // Example: 'http://proxy.example.com:3128'
param noProxy = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'
param proxyCertificate = '' // Certificate content or file path for proxy authentication


// Admin credentials - CHANGE THESE VALUES!
param adminUsername = 'azureuser'
param adminPassword = 'Microsoft#1' // REQUIRED - Change this to a secure password

// Service credentials - CHANGE THIS VALUE!
param servicePassword = 'Microsoft#1' // Used for database and other services

// SSH Authentication (OPTIONAL) - Adds SSH key authentication IN ADDITION to password
// Uncomment and update the path to your public key file:
// param sshPublicKey = loadTextContent('./.ssh/id_rsa.pub')

// Network Security Group Configuration (OPTIONAL)
// Restrict SSH access to specific management subnet/IP
// Default: '*' allows SSH from anywhere (restrict in production)
// Examples: '192.168.1.0/24' or '10.0.0.10/32' for specific subnet/IP
param managementSourcePrefix = '*' // CHANGE THIS in production to your management subnet
