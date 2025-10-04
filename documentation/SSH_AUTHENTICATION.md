# SSH Authentication Configuration

This deployment template supports flexible SSH authentication for all VMs. You can choose between password authentication and SSH key-based authentication.

## Authentication Options

The deployment template **always requires a password** for the admin user. You can optionally add SSH key authentication as an additional login method. Both authentication methods will work simultaneously.

### Option 1: Password Only (Default)

This is the traditional method using username and password only.

**Configuration in `main.bicepparam`:**
```bicep
param adminUsername = 'azureuser'
param adminPassword = 'YourSecurePassword123!'
// Do not set sshPublicKey parameter
```

**Deploy without SSH key:**
```powershell
az deployment group create `
    --resource-group rg-ecommerce-demo `
    --template-file ./infra/main.bicep `
    --parameters ./main.bicepparam
```

**SSH Connection:**
```bash
ssh azureuser@<vm-ip-address>
# Enter password when prompted
```

### Option 2: Password + SSH Key (Recommended for Production)

This provides both password and SSH key authentication methods. You can use either method to log in.

#### Method A: Hard-code in Parameters File

**Configuration in `main.bicepparam`:**
```bicep
param adminUsername = 'azureuser'
param adminPassword = 'YourSecurePassword123!' // Still needed as default
param sshPublicKey = loadTextContent('C:/Users/YourUsername/.ssh/id_rsa.pub')
```

#### Method B: Pass at Deployment Time (Most Flexible - RECOMMENDED)

**Keep `main.bicepparam` with just password:**
```bicep
param adminUsername = 'azureuser'
param adminPassword = 'YourSecurePassword123!'
// Don't set sshPublicKey here
```

**Deploy with SSH key when you want it:**
```powershell
$sshKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" -Raw

az deployment group create `
    --resource-group rg-ecommerce-demo `
    --template-file ./infra/main.bicep `
    --parameters ./main.bicepparam `
    --parameters sshPublicKey="$sshKey"
```

**SSH Connection:**
```bash
ssh -i ~/.ssh/id_rsa azureuser@<vm-ip-address>
# No password required
```

### Flexible Deployment Strategy

You can **keep the same parameters file** and add SSH key authentication at deployment time:

```powershell
# Deploy with password only:
az deployment group create --resource-group <rg> --template-file ./infra/main.bicep --parameters ./main.bicepparam

# Deploy with password + SSH key (both work):
$sshKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" -Raw
az deployment group create --resource-group <rg> --template-file ./infra/main.bicep --parameters ./main.bicepparam --parameters sshPublicKey="$sshKey"
```

This approach gives you maximum flexibility. When SSH key is added, you can use **either** authentication method to connect.

## Setting Up SSH Keys

### On Windows

#### Using PowerShell:
```powershell
# Generate a new SSH key pair (if you don't have one)
ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\id_rsa -N ""

# View your public key
Get-Content $env:USERPROFILE\.ssh\id_rsa.pub
```

#### Update `main.bicepparam`:
```bicep
param sshPublicKey = loadTextContent('C:/Users/YourUsername/.ssh/id_rsa.pub')
```

### On Linux/macOS

#### Using Terminal:
```bash
# Generate a new SSH key pair (if you don't have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# View your public key
cat ~/.ssh/id_rsa.pub
```

#### Update `main.bicepparam`:
```bicep
param sshPublicKey = loadTextContent('~/.ssh/id_rsa.pub')
```

## Examples

### Example 1: Using Default SSH Key Location

**Windows:**
```bicep
param sshPublicKey = loadTextContent('C:/Users/YourUsername/.ssh/id_rsa.pub')
```

**Linux/macOS:**
```bicep
param sshPublicKey = loadTextContent('~/.ssh/id_rsa.pub')
```

### Example 2: Using Custom Key Location

```bicep
param sshPublicKey = loadTextContent('/path/to/your/custom/key.pub')
```

### Example 3: Using a Specific Azure Deployment Key

```bicep
param sshPublicKey = loadTextContent('~/.ssh/azure_production_key.pub')
```

## How It Works

1. **Password authentication is ALWAYS enabled:**
   - You must always provide a valid `adminPassword`
   - You can always log in using username and password
   - This provides a fallback authentication method

2. **When SSH key is provided:**
   - SSH key authentication is **added** as an additional method
   - Password authentication **remains enabled**
   - The public key is added to `/home/<username>/.ssh/authorized_keys` on all VMs
   - All VMs in the deployment use the same SSH key
   - You can log in using **either** password or SSH key

3. **When SSH key is NOT provided:**
   - Only password authentication is available
   - Standard SSH with password login

## Security Best Practices

✅ **DO:**
- Use SSH keys for production deployments (in addition to password)
- Always use a strong password (it's required)
- Keep your private key secure and never share it
- Use different keys for different environments (dev, staging, prod)
- Set appropriate file permissions on your private key:
  - Linux/macOS: `chmod 600 ~/.ssh/id_rsa`
  - Windows: Only your user account should have access
- Consider SSH keys as your primary method and password as backup

❌ **DON'T:**
- Commit private keys to version control
- Share private keys via email or messaging
- Use the same key for all your deployments
- Use weak passwords (they're always enabled)

## Troubleshooting

### Permission Denied (publickey)

If you get this error when trying to connect:

```bash
# Ensure you're using the correct private key
ssh -i /path/to/your/private/key azureuser@<vm-ip>

# Check private key permissions (Linux/macOS)
chmod 600 ~/.ssh/id_rsa

# Enable verbose mode to see what's happening
ssh -v -i ~/.ssh/id_rsa azureuser@<vm-ip>
```

### Public Key Format Issues

Ensure your public key is in the correct format. It should look like:
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... user@hostname
```

### Loading Key File in Bicep

If `loadTextContent()` fails, verify:
- The file path is correct
- The file exists
- You have read permissions
- The path uses forward slashes (even on Windows)

## Connecting to VMs

### Direct SSH Connection

```bash
# Using SSH key
ssh -i ~/.ssh/id_rsa azureuser@192.168.1.21

# Using password
ssh azureuser@192.168.1.21
```

### Azure Arc SSH Connection

For Arc-enabled VMs, you can also use:

```bash
az ssh arc --resource-group <resource-group> --vm-name <vm-name>
```

This works regardless of whether you used SSH keys or passwords during deployment.

## Additional Resources

- [Azure Linux VM SSH Documentation](https://learn.microsoft.com/azure/virtual-machines/linux/ssh-from-windows)
- [SSH Key Management Best Practices](https://learn.microsoft.com/azure/virtual-machines/linux/create-ssh-keys-detailed)
- [Azure Arc SSH Connection](https://learn.microsoft.com/azure/azure-arc/servers/ssh-arc-troubleshoot)
