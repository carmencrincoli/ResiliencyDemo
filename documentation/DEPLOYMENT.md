# Deployment Guide & Configuration

## 📖 Deployment Guide

### Step-by-Step Deployment

#### Phase 1: Prepare Storage Account
The `Prepare-Deployment.ps1` script handles:
- Storage account creation/validation
- Blob container creation (`assets`)
- Upload of deployment scripts from `/assets/deployscripts/`
- Upload of application archives from `/assets/archives/`
- Parameter file update with storage account name

**Generated Storage Structure:**
```
assets/
├── deployscripts/
│   ├── bash-installer.sh
│   ├── pg-primary-setup.sh
│   ├── pg-replica-setup.sh
│   ├── webapp-setup.sh
│   └── loadbalancer-setup.sh
├── database.tar.gz        # PostgreSQL configs
├── webapp.tar.gz          # Next.js application
└── loadbalancer.tar.gz    # NGINX configs
```

**Run the preparation script:**
```powershell
.\Prepare-Deployment.ps1 `
    -ResourceGroupName "rg-ecommerce-demo" `
    -Location "eastus"
```

**What happens:**
1. Reads `main.bicepparam` for existing storage account name
2. If blank or unavailable, generates unique name
3. Creates storage account if needed
4. Uploads all scripts and archives to blob storage
5. Updates parameter file with storage account name

#### Phase 2: Deploy VMs
The Bicep deployment creates VMs in order:

**1. PostgreSQL Primary** (5-7 minutes)
- VM creation and network configuration
- PostgreSQL 16 installation
- Database initialization
- Replication user setup

**2. PostgreSQL Replica** (5-7 minutes)
- VM creation and network configuration
- PostgreSQL 16 installation
- Base backup from primary
- Streaming replication setup

**3. Web Applications** (6-8 minutes each, parallel)
- VM creation and network configuration
- Node.js 18 installation
- Application deployment
- PM2 process manager setup
- Database connection configuration

**4. Load Balancer** (3-5 minutes)
- VM creation and network configuration
- NGINX installation
- Backend pool configuration
- SSL certificate generation (self-signed)

**Deploy with Azure CLI:**
```powershell
# Create resource group
az group create --name rg-ecommerce-demo --location eastus

# Deploy the Bicep template
az deployment group create `
    --resource-group rg-ecommerce-demo `
    --template-file ./infra/main.bicep `
    --parameters ./main.bicepparam
```

**Total deployment time:** Approximately 15-20 minutes

#### Phase 3: Verification

Check deployment outputs:
```powershell
az deployment group show `
    --resource-group rg-ecommerce-demo `
    --name main `
    --query properties.outputs
```

**Expected Outputs:**
- `applicationEndpoints`: URLs to access the application
- `vmResourceIds`: Azure resource IDs for all VMs
- `databaseConnectionInfo`: Database connection details
- `sshConnectionInfo`: SSH commands for each VM

### Manual Verification

**1. Load Balancer Health:**
```bash
curl http://192.168.x.111/api/health
```

**2. Web App Status:**
```bash
ssh azureuser@192.168.x.114 "pm2 status"
ssh azureuser@192.168.x.115 "pm2 status"
```

**3. Database Primary:**
```bash
ssh azureuser@192.168.x.112 "sudo -u postgres psql -c '\l'"
```

**4. Database Replica:**
```bash
ssh azureuser@192.168.x.113 "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"
```

### Post-Deployment Steps

**1. Test Application:**
- Open browser to `http://<load-balancer-ip>`
- Verify product catalog loads
- Test shopping cart functionality
- Check server info display

**2. Verify Database Replication:**
```bash
# On primary
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# On replica
ssh azureuser@<replica-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"
```

**3. Test Failover:**
```bash
# Stop one web app server
ssh azureuser@192.168.x.114 "pm2 stop all"

# Application should still work via second server
curl http://<load-balancer-ip>/api/health

# Restart stopped server
ssh azureuser@192.168.x.114 "pm2 start all"
```

## ⚙️ Configuration

### Parameter File Configuration

Edit `main.bicepparam` before deployment:

```bicep
using './infra/main.bicep'

// Basic configuration
param projectName = 'ecomm'

// Azure Stack HCI configuration - Update these to match your Azure Local environment
param customLocationName = 'your-custom-location'
param logicalNetworkName = 'your-logical-network'
param azureLocalResourceGroup = 'your-azure-local-rg'
param vmImageName = 'ubuntu2404-lts-image-name'
param scriptStorageAccount = '' // Leave empty to create a new one

// Static IP assignments (update these to match your network range)
// IMPORTANT: Must be in a /24 subnet (255.255.255.0)
param staticIPs = {
  loadBalancer: '192.168.x.111'
  dbPrimary: '192.168.x.112'
  dbReplica: '192.168.x.113'
  webapp1: '192.168.x.114'
  webapp2: '192.168.x.115'
}

// Admin credentials - CHANGE THESE VALUES!
param adminUsername = 'azureuser'
param adminPassword = 'YourSecurePassword!' // Change this to a secure password

// Service credentials - CHANGE THIS VALUE!
param servicePassword = 'YourDatabasePassword!' // Used for database and services
```

### Environment Variables (Web Apps)

Variables are set during deployment via Bicep templates:

```bash
DB_PRIMARY_HOST=192.168.x.112
DB_REPLICA_HOST=192.168.x.113
DB_NAME=ecommerce
DB_USER=ecommerce_user
DB_PASSWORD=<from servicePassword>
DB_PORT=5432
NODE_VERSION=18
PORT=3000
```

**To view configured variables on a VM:**
```bash
ssh azureuser@<vm-ip> "cat /var/log/exports.log"
```

### Database Configuration

**Primary Database** (`/etc/postgresql/16/main/postgresql.conf`):
```properties
# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 8MB
maintenance_work_mem = 128MB

# Replication settings
wal_level = replica
max_wal_senders = 3
max_replication_slots = 3
wal_keep_size = 1GB
hot_standby = on
```

**Replica Database** (`/etc/postgresql/16/main/postgresql.conf`):
```properties
# All primary settings PLUS:
hot_standby_feedback = on
wal_receiver_status_interval = 10s
wal_retrieve_retry_interval = 5s
recovery_min_apply_delay = 0
max_standby_streaming_delay = 60s
```

**Access Control** (`/etc/postgresql/16/main/pg_hba.conf`):
```properties
# Allow replication connections
host    replication     replicator      <replica-ip>/32         scram-sha-256

# Allow application connections
host    ecommerce       ecommerce_user  <webapp1-ip>/32         scram-sha-256
host    ecommerce       ecommerce_user  <webapp2-ip>/32         scram-sha-256
```

### NGINX Configuration

**Main Configuration** (`/etc/nginx/nginx.conf`):
```nginx
# Backend pool with least connections algorithm
upstream webapp_pool {
    least_conn;
    server 192.168.x.114:3000 max_fails=3 fail_timeout=30s;
    server 192.168.x.115:3000 max_fails=3 fail_timeout=30s;
}

# Server block
server {
    listen 80;
    listen 443 ssl;
    
    # Health check location
    location /api/health {
        proxy_pass http://webapp_pool;
        proxy_next_upstream error timeout http_500 http_502 http_503;
        proxy_connect_timeout 3s;
        proxy_send_timeout 3s;
        proxy_read_timeout 3s;
    }
    
    # Application
    location / {
        proxy_pass http://webapp_pool;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Health Check Configuration:**
- **Endpoint**: `/api/health`
- **Interval**: 5 seconds (via proxy_connect_timeout)
- **Max failures**: 3
- **Fail timeout**: 30 seconds

### PM2 Configuration

**Process Configuration** (`ecosystem.config.js`):
```javascript
module.exports = {
  apps: [{
    name: 'ecommerce-webapp',
    script: 'node_modules/next/dist/bin/next',
    args: 'start -p 3000',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
```

### Resource Allocation

Modify VM resources in `infra/main.bicep`:

```bicep
var vmResources = {
  database: {
    processors: 4
    memoryMB: 8192    // 8GB
  }
  webapp: {
    processors: 4
    memoryMB: 6144    // 6GB
  }
  loadBalancer: {
    processors: 2
    memoryMB: 2048    // 2GB
  }
}
```

### Network Configuration

**Static IP Management:**
- All IPs defined in `main.bicepparam`
- Must be in same /24 subnet (255.255.255.0 subnet mask)
- Must be available in your network range
- DNS not required (IPs used directly)

> **⚠️ Important Network Requirement**: This project is designed exclusively for /24 virtual networks. Deploying to networks with different subnet masks (/16, /25, /26, etc.) is not supported and will require modifications to the Bicep templates, setup scripts, and network configurations throughout the codebase.

**Required Ports:**

| Component | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| Load Balancer | 80 | HTTP | Web traffic |
| Load Balancer | 443 | HTTPS | Secure web traffic |
| Web Apps | 3000 | HTTP | Next.js application |
| Database | 5432 | TCP | PostgreSQL connections |
| All VMs | 22 | SSH | Remote administration |

### Security Configuration

**1. Passwords:**
- Change default passwords in `main.bicepparam`
- Use strong passwords (min 12 characters)
- `adminPassword`: VM SSH access
- `servicePassword`: Database and application services

**2. SSH Access:**
- Password authentication enabled by default
- Consider using SSH keys for production
- Limit SSH access to specific IP ranges

**3. Database Security:**
- Passwords use scram-sha-256 encryption
- pg_hba.conf restricts access by IP
- No public internet access (local network only)

**4. NGINX Security:**
- Rate limiting configured (10 req/s)
- Server tokens disabled
- TLS 1.2/1.3 only
- Self-signed certificates (replace for production)

### Customization Options

**1. Change Project Name:**
In `main.bicepparam`:
```bicep
param projectName = 'myapp'  // Used in VM names
```

**2. Add More Web App Instances:**
In `infra/main.bicep`, duplicate webapp module:
```bicep
module webapp3Vm 'modules/webapp-vm.bicep' = {
  name: 'deploy-${vmNames.webapp3}'
  params: {
    // ... same as webapp1/webapp2
  }
}
```

**3. Adjust Database Settings:**
Edit `/assets/archives/database/postgresql.conf` before deployment

**4. Customize Application:**
Modify files in `/assets/archives/webapp/src/` before deployment

### Backup and Recovery Configuration

**Automated Backups:**
Script located at `/opt/ecommerce/database/backup-db.sh` on primary

**Manual Backup:**
```bash
ssh azureuser@<primary-ip>
sudo -u postgres /opt/ecommerce/database/backup-db.sh
```

**Recovery:**
Backups stored in `/var/lib/postgresql/16/backups/`

**Replica Promotion:**
```bash
ssh azureuser@<replica-ip>
sudo -u postgres /opt/ecommerce/database/promote-replica.sh
```
