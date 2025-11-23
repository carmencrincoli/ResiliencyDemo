# Architecture & Application Stack

## 🏗️ Architecture

The application consists of 4 virtual machines and a native Azure Local load balancer:

```
                                    ┌─────────────────┐
                                    │  Load Balancer  │
                                    │  (Azure Local)  │
                                    │  192.168.2.111  │
                                    └────────┬────────┘
                                             │
                         ┌───────────────────┴───────────────────┐
                         │                                       │
                    ┌────▼────┐                            ┌────▼────┐
                    │ WebApp1 │                            │ WebApp2 │
                    │(Next.js)│                            │(Next.js)│
                    │192.168  │                            │192.168  │
                    │  .2.114 │                            │  .2.115 │
                    └────┬────┘                            └────┬────┘
                         │                                       │
                         └───────────────────┬───────────────────┘
                                             │
                         ┌───────────────────┴───────────────────┐
                         │                                       │
                    ┌────▼────┐                            ┌────▼────┐
                    │PostgreSQL│                           │PostgreSQL│
                    │ Primary  │──────Replication─────────▶│ Replica  │
                    │192.168   │                           │192.168   │
                    │  .2.112  │                           │  .2.113  │
                    └──────────┘                           └──────────┘
```

### Component Details

| Component | Count | Purpose | Resources |
|-----------|-------|---------|-----------|  
| **Azure Local Load Balancer** | 1 | Native L4 load balancer for HTTP/HTTPS traffic distribution | Managed service |
| **Next.js Web Apps** | 2 VMs | Full-stack web application servers | 4 vCPU, 6GB RAM each |
| **PostgreSQL Primary** | 1 VM | Primary database (read/write) | 4 vCPU, 8GB RAM |
| **PostgreSQL Replica** | 1 VM | Standby database (read-only) | 4 vCPU, 8GB RAM |### Availability Zone Distribution

The deployment leverages Azure Local availability zones to ensure high availability and fault tolerance by distributing VMs across multiple zones. This configuration protects against zone-level failures.

**Default Zone Assignments:**

| VM | Zone | Rationale |
|----|------|-----------|  
| **PostgreSQL Primary** | Zone 1 | Primary database in zone 1 |
| **PostgreSQL Replica** | Zone 2 | Replica in separate zone for database HA |
| **Web App 1** | Zone 1 | First web server in zone 1 |
| **Web App 2** | Zone 2 | Second web server in separate zone for application HA |

**Note:** The native Azure Local load balancer is a managed service and doesn't require zone assignment.**Key Benefits:**
- **Database High Availability**: Primary and replica databases are in different zones, ensuring database availability even if one zone fails
- **Application Redundancy**: Web application servers are distributed across zones, providing continuous service during zone outages
- **Automatic Failover**: If a zone becomes unavailable, the application can continue serving traffic from VMs in the remaining zone(s)

**Configuration:**

Zone assignments are defined in the `placementZones` parameter in your `.bicepparam` file:

```bicep
param placementZones = {
  dbPrimary: '1'      // Database primary in zone 1
  dbReplica: '2'      // Database replica in zone 2
  webapp1: '1'        // Web app 1 in zone 1
  webapp2: '2'        // Web app 2 in zone 2
}
```

**Customization:**
- Zone values can be '1', '2', '3', or other zones supported by your Azure Local instance
- Set zone to empty string `''` to disable zone placement for a specific VM
- `strictPlacementPolicy: true` ensures VMs remain in their designated zones (no automatic failover to other zones)

**Requirements:**
- Azure Local instance must support availability zones
- VMs use the `Microsoft.AzureStackHCI/virtualMachineInstances` API version `2025-04-01-preview` or later
- The `placementProfile` property controls zone placement with `zone` and `strictPlacementPolicy` settings

## 🚀 Application Stack

### Frontend & Backend: Next.js 14 Full-Stack Application

Located in: `/assets/archives/webapp/`

**Technology Stack:**
- **Framework**: Next.js 14 (React 18)
- **Language**: TypeScript
- **Styling**: Tailwind CSS
- **Process Manager**: PM2 for production deployment
- **Security**: Helmet, rate limiting, input validation
- **Logging**: Winston for structured logging

**Key Features:**
- Server-side rendering (SSR) for optimal performance
- API routes for backend logic (`/api/products`, `/api/health`)
- Real-time server information display
- Responsive product catalog with shopping cart
- Database failover support (primary → replica)
- Health check endpoints for load balancer monitoring

**Application Structure:**
```
webapp/
├── src/
│   ├── app/                    # Next.js App Router
│   │   ├── page.tsx           # Main e-commerce page
│   │   ├── layout.tsx         # App layout wrapper
│   │   └── api/               # Backend API routes
│   │       ├── products/      # Product catalog API
│   │       ├── health/        # Health check endpoint
│   │       └── server-info/   # Server metadata
│   ├── components/            # React components
│   │   ├── ProductGrid.tsx    # Product listing
│   │   ├── ProductCard.tsx    # Individual product
│   │   ├── Cart.tsx          # Shopping cart
│   │   └── ServerInfoDisplay.tsx  # Infrastructure info
│   ├── lib/                   # Utility libraries
│   │   ├── database.ts       # PostgreSQL connection pool
│   │   ├── logger.ts         # Winston logging config
│   │   └── server-utils.ts   # Server metadata utilities
│   └── types/                 # TypeScript type definitions
├── ecosystem.config.js        # PM2 configuration
└── package.json              # Dependencies
```

### Database: PostgreSQL 16

Located in: `/assets/archives/database/`

**Configuration:**
- **Version**: PostgreSQL 16 on Ubuntu 24.04 LTS
- **Replication**: Streaming replication (async)
- **Connection Pooling**: Built into application layer
- **Database**: `ecommerce`
- **User**: `ecommerce_user`

**Database Schema:**
```sql
- products          # Product catalog (id, name, description, price, stock)
- users             # User accounts (with security features)
- orders            # Order records
- order_items       # Order line items
- sessions          # Session management
- audit_log         # Security audit trail
```

**Key Features:**
- UUID support with `uuid-ossp` extension
- Cryptographic functions via `pgcrypto`
- Performance monitoring with `pg_stat_statements`
- Streaming replication for high availability
- Automated backup and monitoring scripts
- Log rotation configured

### Load Balancer: Native Azure Local Load Balancer

**Type:** Azure Stack HCI native load balancer (Microsoft.AzureStackHCI/loadBalancers)

**Configuration:**
- **Type**: Layer 4 (TCP) load balancer
- **Algorithm**: Default (5-tuple hash) distribution
- **Health Probes**: HTTP health checks every 15 seconds (2 probes)
- **Ports**: HTTP (80 → 3000), HTTPS (443 → 3000)
- **Backend Pool**: 2 web application servers

**Features:**
- Native integration with Azure Local infrastructure
- Automatic health monitoring with HTTP probes
- Configurable load distribution modes (Default, SourceIP, SourceIPProtocol)
- Direct backend pool integration with VM network interfaces
- Health check endpoint: `/api/health` on port 3000
- No VM overhead - fully managed service

## 🔧 Infrastructure as Code

Located in: `/infra/`

### Bicep Template Structure

```
infra/
├── main.bicep                      # Orchestration template
└── modules/
    ├── pg-primary-vm.bicep        # PostgreSQL primary VM
    ├── pg-replica-vm.bicep        # PostgreSQL replica VM
    ├── webapp-vm.bicep            # Next.js web app VM
    ├── loadbalancer.bicep         # Native Azure Local load balancer
    ├── nsg.bicep                  # Network Security Group
    └── ssh-config.bicep           # SSH key configuration
```

### Key Features

**1. Zero-Touch VM Deployment**
- Automated VM provisioning on Azure Local
- Static IP assignment for predictable networking (all IPs in same subnet)
- Custom Script Extension for automated software installation
- Arc-enabled VMs for Azure portal management

> **⚠️ Network Requirement**: All 5 static IP addresses must be assigned from the same subnet.

**2. Intelligent Dependency Management**
```bicep
Deployment Order:
1. Network Security Group (NSG)
2. PostgreSQL Primary (foundation)
3. PostgreSQL Replica (no direct dependency on primary)
4. Web Apps 1 & 2 (parallel, no direct dependencies)
5. Native Load Balancer (depends on Web Apps for backend pool)
```

**3. Parameterized Configuration**
- All settings configurable via `main.bicepparam`
- Support for multiple Azure Local environments
- Customizable resource allocation
- Secure password management
- Separate frontend IP for native load balancer

**4. Script-Based Setup**
Each VM receives:
- Base installer script (`bash-installer.sh`)
- Component-specific setup script
- Configuration files from storage account
- Environment variables for configuration

### Deployment Scripts

Located in: `/assets/deployscripts/`

| Script | Purpose | VM Target |
|--------|---------|-----------|
| `bash-installer.sh` | Installs Bash on Ubuntu 24.04 | All VMs |
| `pg-primary-setup.sh` | PostgreSQL primary configuration | Database Primary |
| `pg-replica-setup.sh` | PostgreSQL replica setup | Database Replica |
| `webapp-setup.sh` | Next.js app deployment | Web App VMs |
| `loadbalancer-setup.sh` | NGINX configuration | Load Balancer |

## ✨ Application Features

### E-commerce Functionality
- **Product Catalog**: Browse products with images, descriptions, and pricing
- **Shopping Cart**: Add/remove items, update quantities
- **Real-time Inventory**: Stock levels from database
- **Server Information**: Display which servers are handling requests
- **Database Status**: Show primary/replica connection info

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/health` | GET | Health check for load balancer |
| `/api/products` | GET | Retrieve product catalog |
| `/api/server-info` | GET | Server and database metadata |
| `/api/db-test` | GET | Database connectivity test |

### User Interface
- **Responsive Design**: Mobile, tablet, and desktop optimized
- **Modern UI**: Tailwind CSS styling
- **Real-time Updates**: React state management
- **Error Handling**: User-friendly error messages
- **Loading States**: Skeleton screens and spinners

## 🛡️ Resiliency Features

### Application Layer
1. **Load Balancing**: 
   - Automatic traffic distribution
   - Health-based routing
   - Connection draining

2. **Database Failover**:
   - Primary connection with replica fallback
   - Automatic retry logic
   - Connection pool management

3. **Error Handling**:
   - Graceful degradation
   - Circuit breaker patterns
   - Comprehensive logging

### Infrastructure Layer
1. **VM Redundancy**:
   - Multiple web application servers
   - No single point of failure

2. **Database Replication**:
   - Continuous data synchronization
   - Read scalability
   - Disaster recovery ready

3. **Health Monitoring**:
   - NGINX health checks (5s interval)
   - Application health endpoints
   - PostgreSQL replication lag monitoring

### Observability
1. **Application Logs**: `/var/log/webapp/` on web servers
2. **Database Logs**: `/var/log/postgresql/` on DB servers
3. **NGINX Logs**: `/var/log/nginx/` on load balancer
4. **Deployment Logs**: `/var/log/deploy.log` on all VMs
5. **Environment Exports**: `/var/log/exports.log` on all VMs
