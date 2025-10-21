# Proxy Configuration Changes Summary

## Overview
This document describes the changes made to enable proxy support throughout the ResiliencyDemo project. The modifications allow HTTP and HTTPS proxy settings to be passed from Bicep templates to setup scripts and configured system-wide on all VMs.

## Changes Made

### 1. Bicep Template Updates

#### Main Template (`infra/main.bicep`)
- Already had proxy parameters defined:
  - `httpProxy` (secure parameter)
  - `httpsProxy` (secure parameter)
  - `noProxy` (comma-separated list)
  - `proxyCertificate` (optional certificate content)

#### VM Module Updates
Updated all four VM module files to pass proxy values to setup scripts:

**Files Modified:**
- `infra/modules/loadbalancer-vm.bicep`
- `infra/modules/webapp-vm.bicep`
- `infra/modules/pg-primary-vm.bicep`
- `infra/modules/pg-replica-vm.bicep`

**Changes:**
Added three new environment variables to each module's environment configuration object:
```bicep
HTTP_PROXY: httpProxy
HTTPS_PROXY: httpsProxy
NO_PROXY: noProxy
```

These variables are now exported and passed to the setup scripts via the CustomScript extension.

### 2. Setup Script Updates

Updated all four setup scripts to configure system-wide proxy settings:

**Files Modified:**
- `assets/deployscripts/loadbalancer-setup.sh`
- `assets/deployscripts/webapp-setup.sh`
- `assets/deployscripts/pg-primary-setup.sh`
- `assets/deployscripts/pg-replica-setup.sh`

**Changes for Each Script:**

#### A. Export Log Updates
Added proxy variables to the `/var/log/exports.log` file:
```bash
export HTTP_PROXY="$HTTP_PROXY"
export HTTPS_PROXY="$HTTPS_PROXY"
export NO_PROXY="$NO_PROXY"
```

#### B. New Proxy Configuration Section
Added a new section after shell configuration that:

1. **Reads proxy environment variables** from Bicep deployment
2. **Configures system-wide environment** (`/etc/environment`)
   - Sets `http_proxy`, `HTTP_PROXY`
   - Sets `https_proxy`, `HTTPS_PROXY`
   - Sets `no_proxy`, `NO_PROXY`

3. **Exports proxy for current session**
   - Ensures immediate availability during script execution

4. **Configures APT proxy** (`/etc/apt/apt.conf.d/95proxies`)
   - Enables package installation through proxy
   - Configures both HTTP and HTTPS acquisition

5. **Configures curl** (`/root/.curlrc`)
   - Sets proxy and noproxy settings
   - Permissions set to 600 for security

6. **Configures wget** (`/root/.wgetrc`)
   - Sets http_proxy, https_proxy, no_proxy
   - Enables proxy usage
   - Permissions set to 600 for security

7. **Configures npm** (webapp-setup.sh only)
   - Creates `/root/.npmrc` with proxy settings
   - Includes noproxy configuration
   - Sets `strict-ssl=false` for corporate proxies

## How to Use

### 1. Configure Proxy in Parameters File

Edit `template.bicepparam` to set proxy values:

```bicep
// Proxy configuration (OPTIONAL)
param httpProxy = 'http://proxy.example.com:3128'
param httpsProxy = 'http://proxy.example.com:3128'
param noProxy = 'localhost,127.0.0.1,.svc,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.0.0.0/8'
param proxyCertificate = '' // Optional: Certificate content for proxy authentication
```

### 2. Deploy Infrastructure

When you deploy the Bicep template:

```powershell
az deployment group create `
  --resource-group <your-rg> `
  --template-file ./infra/main.bicep `
  --parameters ./template.bicepparam
```

### 3. Automatic Configuration

The proxy settings will be automatically:
- Passed from Bicep to VM modules
- Exported as environment variables in CustomScript extensions
- Configured system-wide in each VM during setup
- Applied to all outbound communications (apt, curl, wget, npm, etc.)

## Proxy Configuration Scope

### System-Wide Configuration
- `/etc/environment` - System-wide environment variables (persistent across reboots)
- Applies to all users and processes

### Tool-Specific Configuration
- **APT** - Package manager for Ubuntu/Debian
- **curl** - Command-line HTTP client
- **wget** - File download utility
- **npm** - Node.js package manager (webapp VMs only)

### Network Traffic Covered
- Package installations (`apt update`, `apt install`)
- File downloads (`curl`, `wget`)
- Node.js package installations (`npm install`)
- Azure CLI commands (inherits from environment)
- Custom application HTTP/HTTPS requests (via environment variables)

## Disabling Proxy

To deploy without proxy:
1. Leave proxy parameters empty in `template.bicepparam`:
   ```bicep
   param httpProxy = ''
   param httpsProxy = ''
   ```

2. The setup scripts will detect empty values and skip proxy configuration:
   ```bash
   log "No proxy configuration provided - skipping proxy setup"
   ```

## Verification

After deployment, you can verify proxy configuration on any VM:

```bash
# Check environment variables
cat /etc/environment | grep -i proxy

# Check APT configuration
cat /etc/apt/apt.conf.d/95proxies

# Check curl configuration
cat /root/.curlrc

# Check wget configuration
cat /root/.wgetrc

# Test proxy with curl
curl -v https://www.microsoft.com

# View deployment logs
cat /var/log/deploy.log | grep -i proxy
```

## Security Considerations

1. **Secure Parameters**: `httpProxy` and `httpsProxy` are marked as `@secure()` in Bicep
2. **File Permissions**: Proxy configuration files (`.curlrc`, `.wgetrc`, `.npmrc`) are set to 600 (owner read/write only)
3. **No Proxy List**: Internal addresses are excluded via `NO_PROXY` to avoid unnecessary proxy overhead
4. **Certificate Support**: Optional `proxyCertificate` parameter for proxy authentication

## Troubleshooting

### Issue: Package installations fail
**Solution**: Check APT proxy configuration:
```bash
cat /etc/apt/apt.conf.d/95proxies
```

### Issue: curl/wget downloads fail
**Solution**: Verify proxy environment variables:
```bash
echo $HTTP_PROXY
echo $HTTPS_PROXY
```

### Issue: npm install fails (webapp VMs)
**Solution**: Check npm proxy configuration:
```bash
cat /root/.npmrc
npm config list
```

### Issue: Proxy not working after reboot
**Solution**: Verify `/etc/environment` contains proxy settings:
```bash
cat /etc/environment
```

## Notes

- Proxy configuration is **optional** - VMs work fine without it
- Proxy settings are applied **early** in the setup process, before package installations
- The `NO_PROXY` variable uses a sensible default for private networks
- All proxy configuration is **logged** to `/var/log/deploy.log` for debugging

## Related Documentation

- [Main Architecture Documentation](./documentation/ARCHITECTURE.md)
- [Proxy Configuration Guide](./documentation/PROXY_CONFIGURATION.md)
- [Deployment Guide](./documentation/DEPLOYMENT.md)
- [Troubleshooting Guide](./documentation/TROUBLESHOOTING.md)
