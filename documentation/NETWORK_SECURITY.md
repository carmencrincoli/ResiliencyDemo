# Network Security Group (NSG) Configuration

## Overview

The e-commerce application deployment includes a comprehensive Network Security Group (NSG) that secures all components of the infrastructure. The NSG is specifically designed for Azure Local and uses the `Microsoft.AzureStackHCI/networkSecurityGroups` API with the `2025-06-01-preview` network interface API version that supports NSG associations.

**Note**: This implementation requires Azure Local with support for the `Microsoft.AzureStackHCI/networkInterfaces@2025-06-01-preview` API version. If your environment uses an older API version, you can implement these security rules using OS-level firewalls (UFW/iptables) as documented in [FIREWALL_CONFIGURATION.md](FIREWALL_CONFIGURATION.md).

## Architecture

The NSG protects all 5 VMs in the deployment:
- **Load Balancer** (NGINX)
- **Web Application Servers** (2x Next.js)
- **PostgreSQL Primary Database**
- **PostgreSQL Replica Database**

## Security Rules

### Inbound Rules (Priority 100-399)

#### Public Internet Access (Priority 100-199)

| Rule Name | Priority | Source | Destination | Port | Protocol | Purpose |
|-----------|----------|--------|-------------|------|----------|---------|
| `allow-http-to-lb` | 100 | Any | Load Balancer IP | 80 | TCP | HTTP traffic to Load Balancer |
| `allow-https-to-lb` | 110 | Any | Load Balancer IP | 443 | TCP | HTTPS traffic to Load Balancer |

#### Internal Application Traffic (Priority 200-299)

| Rule Name | Priority | Source | Destination | Port | Protocol | Purpose |
|-----------|----------|--------|-------------|------|----------|---------|
| `allow-lb-to-webapps` | 200 | Load Balancer IP | Web App IPs | 3000 | TCP | Load Balancer → Web Apps |
| `allow-webapps-to-pg-primary` | 210 | Web App IPs | DB Primary IP | 5432 | TCP | Web Apps → PostgreSQL Primary |
| `allow-webapps-to-pg-replica` | 220 | Web App IPs | DB Replica IP | 5432 | TCP | Web Apps → PostgreSQL Replica (failover) |
| `allow-pg-replication` | 230 | DB Replica IP | DB Primary IP | 5432 | TCP | PostgreSQL replication traffic |

#### Management Access (Priority 300-399)

| Rule Name | Priority | Source | Destination | Port | Protocol | Purpose |
|-----------|----------|--------|-------------|------|----------|---------|
| `allow-ssh-management` | 300 | Management Network | All VM IPs | 22 | TCP | SSH access for administration |

#### Deny Rules (Priority 4000+)

| Rule Name | Priority | Source | Destination | Port | Protocol | Purpose |
|-----------|----------|--------|-------------|------|----------|---------|
| `deny-all-inbound` | 4096 | Any | Any | Any | All | Deny all other inbound traffic |

### Outbound Rules

| Rule Name | Priority | Source | Destination | Port | Protocol | Purpose |
|-----------|----------|--------|-------------|------|----------|---------|
| `allow-all-outbound` | 100 | Any | Any | Any | All | Allow OS updates, package downloads |

## Configuration

### Management Source Prefix

The `managementSourcePrefix` parameter controls SSH access to VMs. Configure this in `template.bicepparam`:

```bicep
// Default: Allow SSH from anywhere (not recommended for production)
param managementSourcePrefix = '*'

// Recommended: Restrict to specific management subnet
param managementSourcePrefix = '192.168.1.0/24'

// Most restrictive: Allow only from specific admin workstation
param managementSourcePrefix = '10.0.0.100/32'
```

### Static IP Requirements

The NSG uses static IPs to create precise security rules. All IP addresses must be defined in the `staticIPs` parameter:

```bicep
param staticIPs = {
  loadBalancer: '192.168.2.111'
  dbPrimary: '192.168.2.112'
  dbReplica: '192.168.2.113'
  webapp1: '192.168.2.114'
  webapp2: '192.168.2.115'
}
```

## Security Best Practices

### 1. Restrict SSH Access

**Production environments should restrict SSH access:**

```bicep
// ❌ NOT RECOMMENDED for production
param managementSourcePrefix = '*'

// ✅ RECOMMENDED for production
param managementSourcePrefix = '10.0.0.0/24'  // Management subnet
```

### 2. Traffic Flow Diagram

```
Internet
  │
  │ (HTTP/HTTPS: 80, 443)
  ↓
Load Balancer (192.168.2.111)
  │
  │ (TCP: 3000)
  ↓
Web Apps (192.168.2.114, 192.168.2.115)
  │
  │ (TCP: 5432)
  ↓
PostgreSQL Primary (192.168.2.112) ←──────→ PostgreSQL Replica (192.168.2.113)
                                   (Replication: 5432)
```

### 3. Principle of Least Privilege

The NSG implements least privilege access:
- Only Load Balancer is accessible from the Internet
- Web Apps only accept traffic from Load Balancer
- Database servers only accept traffic from Web Apps and each other
- All VMs require authentication for SSH access

### 4. Defense in Depth

The NSG is one layer in a comprehensive security strategy:
1. **NSG Layer**: Network-level filtering (this document)
2. **OS Firewall**: UFW/iptables on each VM
3. **Application Security**: NGINX rate limiting, input validation
4. **Database Security**: Authentication, encrypted connections
5. **Monitoring**: Application and infrastructure logging

## Deployment

The NSG is automatically deployed as part of the main infrastructure template:

```bash
# Deploy with NSG
az deployment group create \
  --resource-group your-rg \
  --template-file infra/main.bicep \
  --parameters template.bicepparam \
  --deny-settings-mode none
```

The NSG will be created and automatically associated with all VM network interfaces during deployment.

### Alternative: OS-Level Firewalls

If your Azure Local environment doesn't support the `2025-06-01-preview` network interface API, you can implement these security rules using UFW on each VM as documented in [FIREWALL_CONFIGURATION.md](FIREWALL_CONFIGURATION.md).

## Verification

After deployment, verify NSG configuration:

```bash
# View NSG resource
az network nsg show \
  --resource-group your-rg \
  --name ecommdemo-nsg

# List all security rules
az network nsg rule list \
  --resource-group your-rg \
  --nsg-name ecommdemo-nsg \
  --output table
```

## Troubleshooting

### Connection Issues

If you experience connectivity problems:

1. **Verify NSG is attached to NICs:**
   ```bash
   az network nic show \
     --resource-group your-rg \
     --name vm-name-nic \
     --query networkSecurityGroup
   ```

2. **Check effective security rules:**
   ```bash
   az network nic list-effective-nsg \
     --resource-group your-rg \
     --name vm-name-nic
   ```

3. **Test connectivity from management network:**
   ```bash
   # SSH test
   ssh -v azureuser@192.168.2.111
   
   # HTTP test
   curl -v http://192.168.2.111/health
   ```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Cannot SSH to VM | `managementSourcePrefix` doesn't include your IP | Update parameter to include your management network |
| HTTP/HTTPS not working | Load Balancer IP incorrect | Verify `staticIPs.loadBalancer` matches actual IP |
| Web App can't reach database | Database IPs incorrect | Verify `staticIPs.dbPrimary` and `dbReplica` |
| Replication not working | NSG blocking replication traffic | Verify rule `allow-pg-replication` is present |

## Customization

### Adding Custom Rules

To add custom security rules, edit `infra/modules/nsg.bicep`:

```bicep
@description('Allow custom application traffic')
resource allowCustomApp 'Microsoft.AzureStackHCI/networkSecurityGroups/securityRules@2025-09-01-preview' = {
  name: 'allow-custom-app'
  parent: networkSecurityGroup
  extendedLocation: {
    name: customLocationId
    type: 'CustomLocation'
  }
  properties: {
    description: 'Allow custom application on port 8080'
    protocol: 'Tcp'
    sourceAddressPrefixes: ['*']
    destinationAddressPrefixes: [staticIPs.webapp1, staticIPs.webapp2]
    sourcePortRanges: ['*']
    destinationPortRanges: ['8080']
    access: 'Allow'
    priority: 250
    direction: 'Inbound'
  }
}
```

### Disabling Outbound Restrictions

By default, all outbound traffic is allowed. To restrict outbound traffic, modify the `allow-all-outbound` rule or add specific deny rules.

## Compliance & Auditing

### Rule Priority Strategy

- **100-199**: Public Internet access (minimal surface area)
- **200-299**: Internal application communication
- **300-399**: Management and administrative access
- **4000-4096**: Explicit deny rules

### Security Documentation

All security rules include:
- Descriptive name following naming convention
- Detailed description explaining purpose
- Specific source/destination IPs (no wildcards except for Internet-facing services)
- Explicit protocol and port definitions

## Additional Resources

- [Azure Local Network Security Groups Documentation](https://learn.microsoft.com/azure-stack/hci/manage/manage-network-security-groups)
- [Network Security Best Practices](https://learn.microsoft.com/azure/security/fundamentals/network-best-practices)
- [Azure Local Security Baseline](https://learn.microsoft.com/security/benchmark/azure/baselines/azure-stack-hci-security-baseline)
