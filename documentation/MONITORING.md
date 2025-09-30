# Monitoring & Troubleshooting

## 📊 Monitoring & Operations

### Health Checks

#### Application Health
Check the overall application health through the load balancer:

```bash
curl http://<load-balancer-ip>/api/health
```

**Expected Response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-09-30T12:00:00.000Z",
  "database": "connected",
  "server": "ecomm-webapp-01-abc123"
}
```

**Status Values:**
- `healthy`: All systems operational
- `degraded`: Some components failing but service available
- `unhealthy`: Service unavailable

#### Direct Web App Health
Check individual web application servers:

```bash
# Web App 1
curl http://192.168.x.114:3000/api/health

# Web App 2
curl http://192.168.x.115:3000/api/health
```

#### Database Health

**Primary Database Status:**
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT version();'"
```

**Replica Database Status:**
```bash
ssh azureuser@<replica-ip> "sudo -u postgres psql -c 'SELECT version();'"
```

**Check Database Connectivity:**
```bash
# From web app server
ssh azureuser@<webapp-ip> "curl http://localhost:3000/api/db-test"
```

### Database Replication Monitoring

#### Check Replication Status (Primary)
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"
```

**Key Metrics:**
- `state`: Should be "streaming"
- `sent_lsn` vs `write_lsn`: Replication lag
- `sync_state`: "async" expected

#### Check Replication Status (Replica)
```bash
ssh azureuser@<replica-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"
```

**Key Metrics:**
- `status`: Should be "streaming"
- `received_lsn`: Last received WAL position
- `last_msg_receipt_time`: Should be recent

#### Monitor Replication Lag
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -c \"SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, sync_state FROM pg_stat_replication;\""
```

### PM2 Process Management

PM2 manages the Next.js applications on web servers.

#### Check Process Status
```bash
ssh azureuser@<webapp-ip> "pm2 status"
```

**Expected Output:**
```
┌─────┬──────────────────┬─────────┬─────────┬──────────┬────────┐
│ id  │ name             │ status  │ restart │ uptime   │ memory │
├─────┼──────────────────┼─────────┼─────────┼──────────┼────────┤
│ 0   │ ecommerce-webapp │ online  │ 0       │ 2h       │ 350 MB │
└─────┴──────────────────┴─────────┴─────────┴──────────┴────────┘
```

#### View Application Logs
```bash
# Real-time logs
ssh azureuser@<webapp-ip> "pm2 logs"

# Last 100 lines
ssh azureuser@<webapp-ip> "pm2 logs --lines 100"

# Error logs only
ssh azureuser@<webapp-ip> "pm2 logs --err"
```

#### Real-time Process Monitoring
```bash
ssh azureuser@<webapp-ip> "pm2 monit"
```

Shows live CPU, memory, and log output.

#### Restart Application
```bash
# Restart specific app
ssh azureuser@<webapp-ip> "pm2 restart ecommerce-webapp"

# Restart all apps
ssh azureuser@<webapp-ip> "pm2 restart all"

# Reload with zero-downtime
ssh azureuser@<webapp-ip> "pm2 reload ecommerce-webapp"
```

#### Stop/Start Application
```bash
# Stop
ssh azureuser@<webapp-ip> "pm2 stop ecommerce-webapp"

# Start
ssh azureuser@<webapp-ip> "pm2 start ecommerce-webapp"

# Delete from PM2
ssh azureuser@<webapp-ip> "pm2 delete ecommerce-webapp"
```

### NGINX Monitoring

#### Check NGINX Status
```bash
ssh azureuser@<lb-ip> "sudo systemctl status nginx"
```

#### Test NGINX Configuration
```bash
ssh azureuser@<lb-ip> "sudo nginx -t"
```

#### Reload NGINX Configuration
```bash
ssh azureuser@<lb-ip> "sudo systemctl reload nginx"
```

#### Monitor Active Connections
```bash
ssh azureuser@<lb-ip> "sudo ss -tlnp | grep nginx"
```

### Log Locations and Management

#### Application Logs

| Component | Log Path | Description |
|-----------|----------|-------------|
| Web App | `/var/log/webapp/app.log` | Application logs |
| Web App | `/var/log/webapp/error.log` | Application errors |
| Web App | `/var/log/webapp/pm2.log` | PM2 process logs |
| PostgreSQL | `/var/log/postgresql/postgresql-16-main.log` | Database logs |
| NGINX | `/var/log/nginx/access.log` | HTTP access logs |
| NGINX | `/var/log/nginx/error.log` | NGINX errors |
| Deployment | `/var/log/deploy.log` | Setup script output |
| Environment | `/var/log/exports.log` | Environment variables |

#### View Recent Logs

**Web Application:**
```bash
ssh azureuser@<webapp-ip> "tail -f /var/log/webapp/app.log"
```

**Database:**
```bash
ssh azureuser@<db-ip> "sudo tail -f /var/log/postgresql/postgresql-16-main.log"
```

**NGINX Access:**
```bash
ssh azureuser@<lb-ip> "sudo tail -f /var/log/nginx/access.log"
```

**NGINX Errors:**
```bash
ssh azureuser@<lb-ip> "sudo tail -f /var/log/nginx/error.log"
```

#### Search Logs for Errors

```bash
# Search for errors in last 1000 lines
ssh azureuser@<webapp-ip> "tail -1000 /var/log/webapp/app.log | grep -i error"

# Search database logs
ssh azureuser@<db-ip> "sudo grep -i 'error\|fatal' /var/log/postgresql/postgresql-16-main.log | tail -50"

# Search NGINX logs for 5xx errors
ssh azureuser@<lb-ip> "sudo grep ' 5[0-9][0-9] ' /var/log/nginx/access.log | tail -20"
```

### Database Operations

#### Backup Database
```bash
ssh azureuser@<primary-ip>
sudo -u postgres /opt/ecommerce/database/backup-db.sh
```

Backups stored in: `/var/lib/postgresql/16/backups/`

#### Check Database Size
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -d ecommerce -c 'SELECT pg_size_pretty(pg_database_size(current_database()));'"
```

#### List Database Connections
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT pid, usename, application_name, client_addr, state FROM pg_stat_activity;'"
```

#### Kill Idle Connections
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle' AND state_change < NOW() - INTERVAL '1 hour';\""
```

#### Vacuum Database
```bash
ssh azureuser@<primary-ip> "sudo -u postgres psql -d ecommerce -c 'VACUUM VERBOSE ANALYZE;'"
```

### System Resource Monitoring

#### Check CPU and Memory Usage
```bash
ssh azureuser@<vm-ip> "top -bn1 | head -20"
```

#### Check Disk Usage
```bash
ssh azureuser@<vm-ip> "df -h"
```

#### Check Network Connections
```bash
ssh azureuser@<vm-ip> "ss -tunap | grep ESTABLISHED"
```

#### Monitor PostgreSQL Resources
```bash
ssh azureuser@<db-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_database WHERE datname = '\''ecommerce'\'';'"
```

### Failover Operations

#### Promote Replica to Primary
In case primary database fails:

```bash
ssh azureuser@<replica-ip>
sudo -u postgres /opt/ecommerce/database/promote-replica.sh
```

This will:
1. Stop replication
2. Promote replica to standalone primary
3. Allow read-write operations

#### Rebuild Replication
After fixing original primary:

```bash
ssh azureuser@<old-primary-ip>
# Follow replica setup procedure
# Point to new primary
```

## 🔍 Troubleshooting

### Common Issues

#### 1. Application Not Loading

**Symptoms:** 
- Browser shows connection refused or timeout
- Error: "This site can't be reached"

**Diagnosis:**
```bash
# Test load balancer
curl http://<load-balancer-ip>/api/health

# Check NGINX status
ssh azureuser@<lb-ip> "sudo systemctl status nginx"

# Check NGINX error logs
ssh azureuser@<lb-ip> "sudo tail -50 /var/log/nginx/error.log"

# Check if NGINX is listening
ssh azureuser@<lb-ip> "sudo ss -tlnp | grep nginx"

# Test backend servers directly
curl http://192.168.x.114:3000/api/health
curl http://192.168.x.115:3000/api/health

# Check web app status
ssh azureuser@<webapp-ip> "pm2 status"
```

**Solutions:**

**If NGINX is down:**
```bash
ssh azureuser@<lb-ip> "sudo systemctl restart nginx"
```

**If web apps are down:**
```bash
ssh azureuser@<webapp-ip> "pm2 restart all"
```

**If configuration is invalid:**
```bash
ssh azureuser@<lb-ip> "sudo nginx -t"
# Fix errors, then:
ssh azureuser@<lb-ip> "sudo systemctl restart nginx"
```

**Check firewall:**
```bash
ssh azureuser@<lb-ip> "sudo iptables -L -n"
```

#### 2. Database Connection Errors

**Symptoms:**
- Application shows "Database connection failed"
- 500 errors on product pages

**Diagnosis:**
```bash
# Test database connectivity from web app
ssh azureuser@<webapp-ip> "psql -h <db-primary-ip> -U ecommerce_user -d ecommerce -c 'SELECT 1;'"

# Check PostgreSQL status
ssh azureuser@<db-ip> "sudo systemctl status postgresql"

# Review database logs
ssh azureuser@<db-ip> "sudo tail -f /var/log/postgresql/postgresql-16-main.log"

# Check if PostgreSQL is listening
ssh azureuser@<db-ip> "sudo ss -tlnp | grep postgres"

# Check pg_hba.conf for access rules
ssh azureuser@<db-ip> "sudo cat /etc/postgresql/16/main/pg_hba.conf | grep -v '^#'"

# Test from web app server
ssh azureuser@<webapp-ip> "curl http://localhost:3000/api/db-test"
```

**Solutions:**

**If PostgreSQL is stopped:**
```bash
ssh azureuser@<db-ip> "sudo systemctl start postgresql"
```

**If connection denied:**
Check pg_hba.conf has entries for web app IPs:
```bash
ssh azureuser@<db-ip> "sudo nano /etc/postgresql/16/main/pg_hba.conf"
# Add: host ecommerce ecommerce_user <webapp-ip>/32 scram-sha-256
ssh azureuser@<db-ip> "sudo systemctl reload postgresql"
```

**If password mismatch:**
Reset database password:
```bash
ssh azureuser@<db-ip> "sudo -u postgres psql -c \"ALTER USER ecommerce_user WITH PASSWORD 'new-password';\""
```

Then update web app environment and restart:
```bash
ssh azureuser@<webapp-ip> "pm2 restart all"
```

**If network issue:**
```bash
# Ping test
ssh azureuser@<webapp-ip> "ping -c 4 <db-primary-ip>"

# Telnet test
ssh azureuser@<webapp-ip> "telnet <db-primary-ip> 5432"
```

#### 3. Replication Not Working

**Symptoms:**
- Replica lag increasing
- Replication status shows "down"
- Replica logs show connection errors

**Diagnosis:**
```bash
# On primary - check replication status
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# On replica - check receiver status
ssh azureuser@<replica-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"

# Check replica logs
ssh azureuser@<replica-ip> "sudo tail -100 /var/log/postgresql/postgresql-16-main.log"

# Check network connectivity
ssh azureuser@<replica-ip> "ping -c 4 <primary-ip>"
ssh azureuser@<replica-ip> "telnet <primary-ip> 5432"

# Check replication slot on primary
ssh azureuser@<primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_replication_slots;'"
```

**Solutions:**

**If replication connection dropped:**
```bash
# Restart replica PostgreSQL
ssh azureuser@<replica-ip> "sudo systemctl restart postgresql"
```

**If replication slot missing:**
```bash
# On primary
ssh azureuser@<primary-ip> "sudo -u postgres psql -c \"SELECT * FROM pg_create_physical_replication_slot('replica_1');\""
```

**If replica is too far behind:**
```bash
# May need to rebuild replica
ssh azureuser@<replica-ip>
sudo systemctl stop postgresql
# Re-run pg-replica-setup.sh script
```

**If pg_hba.conf blocks replication:**
```bash
ssh azureuser@<primary-ip> "sudo cat /etc/postgresql/16/main/pg_hba.conf | grep replication"
# Should see: host replication replicator <replica-ip>/32 scram-sha-256
```

#### 4. Deployment Failures

**Symptoms:**
- VM deployment succeeds but application not working
- Custom Script Extension shows failures

**Diagnosis:**
```bash
# Check deployment logs
ssh azureuser@<vm-ip> "cat /var/log/deploy.log"

# Check if scripts were downloaded
ssh azureuser@<vm-ip> "ls -la /opt/ecommerce/"

# Test storage account access
curl -I <storage-account-url>/assets/deployscripts/webapp-setup.sh

# Check Azure Custom Script Extension status
az vm extension list --resource-group <rg-name> --vm-name <vm-name>
```

**Solutions:**

**If script download failed:**
- Verify storage account has public access or valid SAS token
- Check VM has internet connectivity

**If script execution failed:**
```bash
# Re-run setup script manually
ssh azureuser@<vm-ip>
source /var/log/exports.log
sudo bash /opt/ecommerce/<component>-setup.sh
```

**If missing dependencies:**
```bash
# For web apps
ssh azureuser@<webapp-ip> "which node"
ssh azureuser@<webapp-ip> "which pm2"

# For database
ssh azureuser@<db-ip> "which psql"
```

**Re-run Custom Script Extension:**
```powershell
# Remove and re-add extension
az vm extension delete --resource-group <rg> --vm-name <vm> --name customScript
# Then redeploy
```

#### 5. High CPU or Memory Usage

**Symptoms:**
- Application slow to respond
- VM becomes unresponsive

**Diagnosis:**
```bash
# Check overall system resources
ssh azureuser@<vm-ip> "top -bn1 | head -30"

# Check PM2 process resources
ssh azureuser@<webapp-ip> "pm2 monit"

# Check PostgreSQL process
ssh azureuser@<db-ip> "ps aux | grep postgres"

# Check active database connections
ssh azureuser@<db-ip> "sudo -u postgres psql -c 'SELECT count(*) FROM pg_stat_activity;'"

# Check slow queries
ssh azureuser@<db-ip> "sudo -u postgres psql -c 'SELECT pid, now() - query_start as duration, query FROM pg_stat_activity WHERE state = '\''active'\'' ORDER BY duration DESC;'"
```

**Solutions:**

**Kill long-running queries:**
```bash
ssh azureuser@<db-ip> "sudo -u postgres psql -c 'SELECT pg_terminate_backend(<pid>);'"
```

**Restart application:**
```bash
ssh azureuser@<webapp-ip> "pm2 restart all"
```

**Clear database connections:**
```bash
ssh azureuser@<db-ip> "sudo -u postgres psql -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'ecommerce' AND pid <> pg_backend_pid();\""
```

#### 6. SSL/TLS Certificate Errors

**Symptoms:**
- Browser shows certificate warning
- HTTPS not working

**Diagnosis:**
```bash
# Check certificate
ssh azureuser@<lb-ip> "sudo openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -text -noout"

# Check NGINX SSL configuration
ssh azureuser@<lb-ip> "sudo grep -A 10 'ssl_certificate' /etc/nginx/nginx.conf"
```

**Solutions:**

**Regenerate self-signed certificate:**
```bash
ssh azureuser@<lb-ip>
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt
sudo systemctl reload nginx
```

**For production, use proper certificate:**
- Obtain certificate from Certificate Authority
- Copy to load balancer
- Update NGINX configuration

### Getting Additional Help

#### View Environment Variables
```bash
ssh azureuser@<vm-ip> "cat /var/log/exports.log"
```

#### Check Service Status
```bash
# All systemd services
ssh azureuser@<vm-ip> "systemctl list-units --type=service --state=running"

# Specific service
ssh azureuser@<vm-ip> "sudo journalctl -u postgresql -n 100"
```

#### Network Diagnostics
```bash
# Check routing
ssh azureuser@<vm-ip> "ip route"

# Check DNS
ssh azureuser@<vm-ip> "cat /etc/resolv.conf"

# Test connectivity to all VMs
ssh azureuser@<vm-ip> "ping -c 2 192.168.x.111 && ping -c 2 192.168.x.112 && ping -c 2 192.168.x.113"
```

#### Performance Testing
```bash
# Load test with Apache Bench
ab -n 1000 -c 10 http://<load-balancer-ip>/

# Database query performance
ssh azureuser@<db-ip> "sudo -u postgres psql -d ecommerce -c 'EXPLAIN ANALYZE SELECT * FROM products;'"
```

### Emergency Recovery Procedures

#### Complete Application Reset
```bash
# Stop all web apps
ssh azureuser@192.168.x.114 "pm2 stop all"
ssh azureuser@192.168.x.115 "pm2 stop all"

# Restart database
ssh azureuser@<primary-ip> "sudo systemctl restart postgresql"

# Wait 30 seconds
sleep 30

# Start web apps
ssh azureuser@192.168.x.114 "pm2 start all"
ssh azureuser@192.168.x.115 "pm2 start all"

# Restart load balancer
ssh azureuser@<lb-ip> "sudo systemctl restart nginx"
```

#### Database Emergency Procedures

**If primary database corrupted, promote replica:**
```bash
# Promote replica
ssh azureuser@<replica-ip> "sudo -u postgres /opt/ecommerce/database/promote-replica.sh"

# Update web apps to use new primary
# Edit environment variables and restart
ssh azureuser@<webapp-ip> "pm2 restart all"
```

**If replica too far behind, rebuild:**
```bash
# Stop replica
ssh azureuser@<replica-ip> "sudo systemctl stop postgresql"

# Clear data directory
ssh azureuser@<replica-ip> "sudo rm -rf /var/lib/postgresql/16/main/*"

# Re-run setup script
ssh azureuser@<replica-ip> "sudo bash /opt/ecommerce/deployscripts/pg-replica-setup.sh"
```
