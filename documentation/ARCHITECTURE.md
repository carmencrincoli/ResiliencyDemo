# Architecture & Application Stack

## 🏗️ Architecture

The application consists of 5 virtual machines deployed on Azure Local:

```
                                    ┌─────────────────┐
                                    │  Load Balancer  │
                                    │     (NGINX)     │
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

| Component | VM Count | Purpose | Resources |
|-----------|----------|---------|-----------|
| **NGINX Load Balancer** | 1 | HTTP/HTTPS traffic distribution | 2 vCPU, 2GB RAM |
| **Next.js Web Apps** | 2 | Full-stack web application servers | 4 vCPU, 6GB RAM each |
| **PostgreSQL Primary** | 1 | Primary database (read/write) | 4 vCPU, 8GB RAM |
| **PostgreSQL Replica** | 1 | Standby database (read-only) | 4 vCPU, 8GB RAM |

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

### Load Balancer: NGINX

Located in: `/assets/archives/loadbalancer/`

**Configuration:**
- **Algorithm**: Least connections
- **Health Checks**: Every 5 seconds with 3 max failures
- **Ports**: HTTP (80), HTTPS (443)
- **Backend Pool**: 2 web application servers

**Features:**
- SSL/TLS termination (TLS 1.2/1.3)
- Gzip compression for web assets
- Rate limiting (10 req/s per IP for API)
- Custom logging with request/response times
- Automatic failover to healthy backends
- Health check endpoint: `/api/health`

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
    ├── loadbalancer-vm.bicep      # NGINX load balancer VM
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
1. PostgreSQL Primary (foundation)
2. PostgreSQL Replica (depends on primary)
3. Web Apps 1 & 2 (parallel, depend on primary)
4. Load Balancer (parallel, depends on primary)
```

**3. Parameterized Configuration**
- All settings configurable via `main.bicepparam`
- Support for multiple Azure Local environments
- Customizable resource allocation
- Secure password management

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
