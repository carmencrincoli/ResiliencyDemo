// PostgreSQL Primary VM module for Azure Local deployment
@description('Name for the PostgreSQL primary VM')
param vmName string

@description('Azure region for resource metadata')
param location string

@description('Common VM configuration object')
param vmConfig object

@description('HTTP proxy server URL (optional - leave empty to disable proxy)')
@secure()
param httpProxy string = ''

@description('HTTPS proxy server URL (optional - leave empty to disable proxy)')
@secure()
param httpsProxy string = ''

@description('URLs that should bypass the proxy (optional - comma-separated list)')
param noProxy string = ''

@description('Certificate file path or content for proxy authentication (optional)')
param proxyCertificate string = ''

@description('Static IP address for this PostgreSQL primary VM')
param staticIP string

@description('IP address of the PostgreSQL replica server')
param replicaIP string

@description('URL of the PostgreSQL primary setup script in Azure Storage')
param scriptUrl string

@description('URL of the bash installer script in Azure Storage')
param bashInstallerUrl string

@description('Base URL of the Azure Storage account for downloading archives')
param storageAccountUrl string

@description('Database password for PostgreSQL authentication')
@secure()
param servicePassword string

@description('VM administrator password')
@secure()
param adminPassword string

@description('SSH public key for admin user authentication (optional - adds SSH in addition to password)')
@secure()
param sshPublicKey string = ''

@description('Number of processors for the VM')
param processors int

@description('Memory in MB for the VM')
param memoryMB int

// Generate resource names
var nicName = '${vmName}-nic'
var customLocationId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.ExtendedLocation/customLocations', vmConfig.customLocationName)
var logicalNetworkId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.AzureStackHCI/logicalnetworks', vmConfig.logicalNetworkName)
var imageId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.AzureStackHCI/galleryImages', vmConfig.imageName)

// PostgreSQL primary configuration
var databaseConfig = {
  name: 'ecommerce'
  user: 'ecommerce_user'
  password: servicePassword
  port: 5432
}

// PostgreSQL primary database environment variables for setup scripts
var databaseEnvironment = {
  DB_NAME: databaseConfig.name
  DB_USER: databaseConfig.user
  DB_PASSWORD: databaseConfig.password
  DB_PORT: string(databaseConfig.port)
  REPLICA_IP: replicaIP
  STORAGE_ACCOUNT_URL: storageAccountUrl
}

// Convert environment variables to export commands for shell
var envExports = 'export ${join(map(items(databaseEnvironment), item => '${item.key}="${item.value}"'), ' ')}'

// Create Arc Connected Machine for zero-touch onboarding
resource hybridComputeMachine 'Microsoft.HybridCompute/machines@2023-10-03-preview' = {
  name: vmName
  location: location
  kind: 'HCI'
  identity: {
    type: 'SystemAssigned'
  }
}

// Create network interface with static IP
resource networkInterface 'Microsoft.AzureStackHCI/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAddress: staticIP
          subnet: {
            id: logicalNetworkId
          }
        }
      }
    ]
  }
}

// Create the virtual machine instance
resource virtualMachine 'Microsoft.AzureStackHCI/virtualMachineInstances@2024-01-01' = {
  name: 'default'
  properties: {
    hardwareProfile: {
      vmSize: vmConfig.size
      processors: processors
      memoryMB: memoryMB
    }
    osProfile: {
      adminUsername: vmConfig.adminUsername
      adminPassword: adminPassword
      computerName: vmName
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
        provisionVMConfigAgent: true
        ssh: !empty(sshPublicKey) ? {
          publicKeys: [
            {
              path: '/home/${vmConfig.adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        } : null
      }
    }
    storageProfile: {
      imageReference: {
        id: imageId
      }
    }
    // HTTP/HTTPS proxy configuration for the VM
    httpProxyConfig: !empty(httpProxy) || !empty(httpsProxy) ? {
      httpProxy: !empty(httpProxy) ? httpProxy : null
      httpsProxy: !empty(httpsProxy) ? httpsProxy : null
      noProxy: !empty(noProxy) ? split(noProxy, ',') : null
      trustedCa: !empty(proxyCertificate) ? proxyCertificate : null
    } : null
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
      }
    }
  }
  extendedLocation: {
    type: 'CustomLocation'
    name: customLocationId
  }
  scope: hybridComputeMachine
}

// Azure AD SSH Login Extension for Entra ID authentication
resource aadSSHLoginExtension 'Microsoft.HybridCompute/machines/extensions@2023-10-03-preview' = {
  parent: hybridComputeMachine
  name: 'AADSSHLoginForLinux'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADSSHLoginForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {}
  }
  dependsOn: [
    virtualMachine
  ]
}

// Enable SSH access for Arc-enabled server (immediately after AAD SSH extension)
module sshConfiguration 'ssh-config.bicep' = {
  name: '${vmName}-ssh-config'
  params: {
    machineName: vmName
    sshPort: 22
  }
  dependsOn: [
    hybridComputeMachine
    aadSSHLoginExtension
  ]
}

// Combined setup command with bash installation, monitor, and PostgreSQL primary setup
var combinedSetupCommand = 'echo "=== Phase 1: Installing Bash ===" && curl -sSL "${bashInstallerUrl}" -o /tmp/bash-installer.sh && chmod +x /tmp/bash-installer.sh && sed -i "s/\r$//" /tmp/bash-installer.sh && /bin/sh /tmp/bash-installer.sh && echo "=== Phase 2: Setting up PostgreSQL Primary ===" && curl -sSL "${scriptUrl}" -o /tmp/pg-primary-setup.sh && chmod +x /tmp/pg-primary-setup.sh && ${envExports} && /bin/bash /tmp/pg-primary-setup.sh && echo "=== All phases completed successfully ==="'

// PostgreSQL primary setup extension (depends on bash installer module)
resource postgresqlPrimarySetupExtension 'Microsoft.HybridCompute/machines/extensions@2023-10-03-preview' = {
  parent: hybridComputeMachine
  name: 'postgresql-primary-setup'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: combinedSetupCommand
      skipDos2Unix: false
    }
  }
  dependsOn: [
    virtualMachine
    aadSSHLoginExtension
  ]
}

// Output the VM resource ID for reference in main template
@description('Resource ID of the created PostgreSQL primary VM')
output vmResourceId string = '${hybridComputeMachine.id}/providers/Microsoft.AzureStackHCI/virtualmachineinstances/default'

@description('Network interface resource ID')
output nicResourceId string = networkInterface.id

@description('PostgreSQL primary VM connection information')
output connectionInfo object = {
  vmName: vmName
  assignedIP: staticIP
  role: 'postgresql-primary'
  databaseName: databaseConfig.name
  port: databaseConfig.port
  sshCommand: sshConfiguration.outputs.sshConnectionInfo.sshCommand
}

@description('Assigned IP address of the PostgreSQL primary VM')
output assignedIP string = staticIP
