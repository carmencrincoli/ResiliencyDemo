// Load Balancer VM module for NGINX deployment on Azure Local
@description('Name for the load balancer VM')
param vmName string

@description('Azure region for resource metadata')
param location string

@description('Common VM configuration object')
param vmConfig object

@description('Static IP address for this VM')
param staticIP string

@description('IP address of the first web application server')
param webapp1IP string

@description('IP address of the second web application server')
param webapp2IP string

@description('URL of the deployment script in Azure Storage')
param scriptUrl string

@description('URL of the bash installer script in Azure Storage')
param bashInstallerUrl string

@description('Base URL of the Azure Storage account for downloading archives')
param storageAccountUrl string

@description('VM administrator password')
@secure()
param adminPassword string

@description('Number of processors for the VM')
param processors int

@description('Memory in MB for the VM')
param memoryMB int

@description('Load balancer configuration parameters')
param loadBalancerConfig object = {
  httpsPort: 443
  httpPort: 80
}

// Generate resource names
var nicName = '${vmName}-nic'
var customLocationId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.ExtendedLocation/customLocations', vmConfig.customLocationName)
var logicalNetworkId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.AzureStackHCI/logicalnetworks', vmConfig.logicalNetworkName)
var imageId = resourceId(vmConfig.azureLocalResourceGroup, 'Microsoft.AzureStackHCI/galleryImages', vmConfig.imageName)

// Load balancer environment variables for setup scripts
var loadBalancerEnvironment = {
  WEBAPP1_IP: webapp1IP
  WEBAPP2_IP: webapp2IP
  LB_HTTPS_PORT: string(loadBalancerConfig.httpsPort)
  LB_HTTP_PORT: string(loadBalancerConfig.httpPort)
  STORAGE_ACCOUNT_URL: storageAccountUrl
}

// Convert environment variables to export commands for shell
var envExports = 'export ${join(map(items(loadBalancerEnvironment), item => '${item.key}="${item.value}"'), ' ')}'

// Create Arc Connected Machine for zero-touch onboarding
resource hybridComputeMachine 'Microsoft.HybridCompute/machines@2023-10-03-preview' = {
  name: vmName
  location: location
  kind: 'HCI'
  identity: {
    type: 'SystemAssigned'
  }
}

// Network interface with static IP
resource networkInterface 'Microsoft.AzureStackHCI/networkInterfaces@2024-01-01' = {
  name: nicName
  location: location
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
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
      }
    }
    storageProfile: {
      imageReference: {
        id: imageId
      }
    }
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

// Azure AD SSH Login Extension for Entra ID authentication (optional, non-critical)
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

// Combined setup command with bash installation, monitor, and load balancer setup
var combinedSetupCommand = 'echo "=== Phase 1: Installing Bash ===" && curl -sSL "${bashInstallerUrl}" -o /tmp/bash-installer.sh && chmod +x /tmp/bash-installer.sh && sed -i "s/\r$//" /tmp/bash-installer.sh && /bin/sh /tmp/bash-installer.sh && echo "=== Phase 2: Setting up Load Balancer ===" && curl -sSL "${scriptUrl}" -o /tmp/loadbalancer-setup.sh && chmod +x /tmp/loadbalancer-setup.sh && ${envExports} && /bin/bash /tmp/loadbalancer-setup.sh && echo "=== All phases completed successfully ==="'

// Load balancer setup extension (depends on bash installer module)
resource loadBalancerSetupExtension 'Microsoft.HybridCompute/machines/extensions@2023-10-03-preview' = {
  parent: hybridComputeMachine
  name: 'loadbalancer-setup'
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

// Enable SSH access for Arc-enabled server
module sshConfiguration 'ssh-config.bicep' = {
  name: '${vmName}-ssh-config'
  params: {
    machineName: vmName
    sshPort: 22
  }
  dependsOn: [
    hybridComputeMachine
    loadBalancerSetupExtension // Wait for setup to complete
  ]
}

// Output the VM resource ID for reference in main template
@description('Resource ID of the created VM')
output vmResourceId string = '${hybridComputeMachine.id}/providers/Microsoft.AzureStackHCI/virtualmachineinstances/default'

@description('Network interface resource ID')
output nicResourceId string = networkInterface.id

@description('VM connection information')
output connectionInfo object = {
  vmName: vmName
  assignedIP: staticIP
  role: 'load-balancer'
  httpsPort: loadBalancerConfig.httpsPort
  httpPort: loadBalancerConfig.httpPort
  sshCommand: sshConfiguration.outputs.sshConnectionInfo.sshCommand
}

@description('Assigned IP address of the VM')
output assignedIP string = staticIP
