# HTTP/HTTPS Proxy Configuration for Azure Local VMs

This document describes the HTTP and HTTPS proxy configuration that has been added to all VMs in the ResiliencyDemo project.

## Overview

All VMs in this deployment now support HTTP and HTTPS proxy configuration, which is essential for environments where VMs need to access the internet through a corporate proxy server. This configuration is applied during VM creation and affects the Azure Connected Machine agent onboarding process.

## Implementation Details

### Main Template Changes (`infra/main.bicep`)

Added the following new parameters:
- `httpProxy` (secure): HTTP proxy server URL (optional)
- `httpsProxy` (secure): HTTPS proxy server URL (optional) 
- `noProxy`: URLs that should bypass the proxy (comma-separated list)
- `proxyCertificate`: Certificate content or file path for proxy authentication (optional)

These parameters are passed to all VM modules individually to maintain proper security handling.

### VM Module Changes

All VM modules have been updated with:

1. **New Parameters**: Each module now accepts the four proxy configuration parameters
2. **httpProxyConfig Property**: Added to the `virtualMachineInstances` resource properties
3. **Conditional Logic**: Proxy configuration is only applied if either `httpProxy` or `httpsProxy` is provided

### Affected VM Modules

- `modules/webapp-vm.bicep` - Web application VMs
- `modules/pg-primary-vm.bicep` - PostgreSQL primary VM
- `modules/pg-replica-vm.bicep` - PostgreSQL replica VM  
- `modules/loadbalancer-vm.bicep` - Load balancer VM

## Configuration Examples

### Parameter File Configuration

Update your `.bicepparam` file with proxy settings:

```bicep
// Proxy configuration (OPTIONAL)
param httpProxy = 'http://proxy.example.com:3128'
param httpsProxy = 'http://proxy.example.com:3128'
param noProxy = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'
param proxyCertificate = '' // Leave empty unless proxy requires certificate authentication
```

### Proxy with Authentication

For proxies requiring username/password authentication, include credentials in the URL:

```bicep
param httpProxy = 'http://username:password@proxy.example.com:3128'
param httpsProxy = 'http://username:password@proxy.example.com:3128'
```

### Disable Proxy

To disable proxy configuration, leave the proxy parameters empty:

```bicep
param httpProxy = ''
param httpsProxy = ''
```

## Important Notes

1. **Security**: Proxy URLs are marked as secure parameters to protect credentials
2. **Scope**: Proxy configuration applies to the Azure Connected Machine agent onboarding process
3. **Application-Level**: Applications running on VMs may need additional proxy configuration
4. **Default noProxy**: Includes common local and private network ranges that should bypass proxy
5. **Certificate**: Only required if your proxy server uses a custom certificate for SSL/TLS

## Azure Local Requirements

This configuration follows the official Microsoft documentation for Azure Local VM proxy configuration:
- Uses the `httpProxyConfig` property on `virtualMachineInstances` resources
- Supports both HTTP and HTTPS proxy URLs
- Includes `noProxy` list for bypassing proxy for specific URLs
- Supports custom certificates via `trustedCa` property

## Deployment

When deploying with proxy configuration:

1. Update your parameter file with the appropriate proxy settings
2. Deploy using your normal deployment process (e.g., `az deployment group create`)
3. The proxy configuration will be applied during VM creation
4. VMs will use the proxy for Azure Connected Machine agent communication

## Troubleshooting

If VMs fail to connect or register:

1. Verify proxy URLs are accessible from the VM network
2. Check that required Azure endpoints are allowed through the proxy
3. Ensure proxy authentication credentials are correct
4. Review the `noProxy` list to ensure necessary local services can be reached directly

For additional troubleshooting, refer to the official Azure Local documentation for VM proxy configuration.