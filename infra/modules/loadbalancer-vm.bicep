// Load Balancer VM module for NGINX deployment on Azure Local
@description('Name for the load balancer VM')
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

@description('Static IP address for this VM')
param staticIP string

@description('IP address of the first web application server')
param webapp1IP string

@description('IP address of the second web application server')
param webapp2IP string

@description('Base URL of the Azure Storage account for downloading archives')
param storageAccountUrl string

@description('Name of the storage account')
param storageAccountName string

@description('Storage account key for authentication')
@secure()
param storageAccountKey string

@description('VM administrator password')
@secure()
param adminPassword string

@description('SSH public key for admin user authentication (optional - adds SSH in addition to password)')
@secure()
param sshPublicKey string = ''

@description('Custom DNS servers for the VM (optional - leave empty to use LNET defaults)')
param dnsServers array = []

@description('Number of processors for the VM')
param processors int

@description('Memory in MB for the VM')
param memoryMB int

@description('Placement zone for the VM (optional - for distributing VMs across availability zones)')
param placementZone string = ''

@description('Resource ID of the Network Security Group to associate with the network interface')
param networkSecurityGroupId string = ''

@description('Load balancer configuration parameters')
param loadBalancerConfig object = {
  httpsPort: 443
  httpPort: 80
}

// Generate resource names
var nicName = '${vmName}-nic'
var customLocationId = vmConfig.customLocationId
var logicalNetworkId = vmConfig.logicalNetworkId
var imageId = vmConfig.imageId

// Load balancer environment variables for setup scripts
var loadBalancerEnvironment = {
  WEBAPP1_IP: webapp1IP
  WEBAPP2_IP: webapp2IP
  LB_HTTPS_PORT: string(loadBalancerConfig.httpsPort)
  LB_HTTP_PORT: string(loadBalancerConfig.httpPort)
  STORAGE_ACCOUNT_URL: storageAccountUrl
  STORAGE_ACCOUNT_NAME: storageAccountName
  STORAGE_ACCOUNT_KEY: storageAccountKey
  HTTP_PROXY: httpProxy
  HTTPS_PROXY: httpsProxy
  NO_PROXY: noProxy
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
resource networkInterface 'Microsoft.AzureStackHCI/networkInterfaces@2025-06-01-preview' = {
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
    dnsSettings: !empty(dnsServers) ? {
      dnsServers: dnsServers
    } : null
    networkSecurityGroup: !empty(networkSecurityGroupId) ? {
      id: networkSecurityGroupId
    } : null
  }
}

// Create the virtual machine instance
resource virtualMachine 'Microsoft.AzureStackHCI/virtualMachineInstances@2025-04-01-preview' = {
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
    // Placement profile for availability zone assignment
    placementProfile: !empty(placementZone) ? {
      zone: placementZone
      strictPlacementPolicy: true
    } : null
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

// Combined setup command using storage account key for authentication
var combinedSetupCommand = '${envExports} && echo "=== Phase 0: Configuring APT and Service Proxies ===" && if [ -n "$HTTP_PROXY" ]; then echo "Acquire::http::Proxy \\"$HTTP_PROXY\\";" > /etc/apt/apt.conf.d/95proxies && echo "Acquire::https::Proxy \\"$HTTPS_PROXY\\";" >> /etc/apt/apt.conf.d/95proxies && mkdir -p /etc/systemd/system/extd.service.d && printf "[Service]\\nEnvironment=\\"HTTP_PROXY=%s\\"\\nEnvironment=\\"HTTPS_PROXY=%s\\"\\nEnvironment=\\"NO_PROXY=%s\\"\\n" "$HTTP_PROXY" "$HTTPS_PROXY" "$NO_PROXY" > /etc/systemd/system/extd.service.d/http-proxy.conf && systemctl daemon-reload && systemctl restart extd; fi && echo "=== Phase 1: Installing Azure CLI ===" && curl -sL https://aka.ms/InstallAzureCLIDeb | bash && echo "=== Phase 2: Downloading Setup Script ===" && az storage blob download --account-name ${storageAccountName} --account-key "${storageAccountKey}" --container-name assets --name deployscripts/loadbalancer-setup.sh --file /tmp/loadbalancer-setup.sh && chmod +x /tmp/loadbalancer-setup.sh && sed -i "s/\r$//" /tmp/loadbalancer-setup.sh && echo "=== Phase 3: Setting up Load Balancer ===" && /bin/bash /tmp/loadbalancer-setup.sh && echo "=== All phases completed successfully ==="'

// Load balancer setup extension - runs first
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
  ]
}

// Azure AD SSH Login Extension for Entra ID authentication (optional, non-critical)
// Runs AFTER setup scripts complete
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
    loadBalancerSetupExtension
  ]
}

// Enable SSH access for Arc-enabled server (as soon as Arc machine is ready)
module sshConfiguration 'ssh-config.bicep' = {
  name: '${vmName}-ssh-config'
  params: {
    machineName: vmName
    sshPort: 22
  }
  dependsOn: [
    hybridComputeMachine
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
