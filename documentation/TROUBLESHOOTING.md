# Troubleshooting Guide

## Common Issues and Solutions

### Database Connection Failures

#### Symptom: "Primary database is not available for write operations"

**Error Message:**
```json
{
  "success": false,
  "data": {
    "primary": {
      "status": "error",
      "error": "Primary database is not available for write operations"
    },
    "replica": {
      "status": "error", 
      "error": "No database connections available"
    }
  }
}
```

**Cause:** PM2 is not loading environment variables from the `.env.production` file.

**Solution:**

1. **Verify environment variables exist:**
   ```bash
   ssh azureuser@<webapp-ip> "sudo cat /opt/webapp/.env.production"
   ```

2. **Check PM2 environment:**
   ```bash
   ssh azureuser@<webapp-ip> "sudo -u webapp pm2 env 0 | grep DB_"
   ```

3. **If DB variables are missing, restart PM2 with updated config:**
   ```bash
   ssh azureuser@<webapp-ip>
   cd /opt/webapp
   sudo -u webapp pm2 stop ecommerce-webapp
   sudo -u webapp pm2 delete ecommerce-webapp
   sudo -u webapp pm2 start ecosystem.config.js
   sudo -u webapp pm2 save
   ```

4. **Verify the fix:**
   ```bash
   curl http://localhost:3000/api/db-test
   ```

#### Symptom: "password authentication failed for user \"ecommerce_user\""

**Cause:** Database password is incorrect or not being passed correctly.

**Solution:**

1. **Verify the password in the environment file:**
   ```bash
   ssh azureuser@<webapp-ip> "sudo cat /opt/webapp/.env.production | grep DB_PASSWORD"
   ```

2. **Test database connection manually:**
   ```bash
   ssh azureuser@<webapp-ip>
   PGPASSWORD='<your-password>' psql -h <db-primary-ip> -p 5432 -U ecommerce_user -d ecommerce -c 'SELECT 1;'
   ```

3. **Check pg_hba.conf on database server:**
   ```bash
   ssh azureuser@<db-primary-ip> "sudo cat /etc/postgresql/16/main/pg_hba.conf | grep ecommerce"
   ```

4. **Ensure web server IP is allowed in pg_hba.conf:**
   ```
   host    ecommerce    ecommerce_user    <webapp-ip>/32    scram-sha-256
   ```

### Network Connectivity Issues

#### Symptom: Cannot reach database server

**Diagnosis:**
```bash
# Test network connectivity
ssh azureuser@<webapp-ip> "nc -zv <db-ip> 5432"

# Check firewall rules on database server
ssh azureuser@<db-ip> "sudo ufw status"
```

**Solution:**
```bash
# On database server, ensure port 5432 is open
ssh azureuser@<db-ip>
sudo ufw allow from <webapp-ip> to any port 5432
```

### PM2 Process Issues

#### Symptom: Application not starting

**Diagnosis:**
```bash
# Check PM2 status
ssh azureuser@<webapp-ip> "sudo -u webapp pm2 status"

# View PM2 logs
ssh azureuser@<webapp-ip> "sudo -u webapp pm2 logs ecommerce-webapp --lines 50"
```

**Common Fixes:**

1. **Restart PM2:**
   ```bash
   ssh azureuser@<webapp-ip>
   cd /opt/webapp
   sudo -u webapp pm2 restart ecommerce-webapp
   ```

2. **Rebuild if needed:**
   ```bash
   ssh azureuser@<webapp-ip>
   cd /opt/webapp
   sudo -u webapp npm run build
   sudo -u webapp pm2 restart ecommerce-webapp
   ```

3. **Check for port conflicts:**
   ```bash
   ssh azureuser@<webapp-ip> "sudo netstat -tulpn | grep :3000"
   ```

### Load Balancer Issues

#### Symptom: Load balancer not distributing traffic

**Diagnosis:**
```bash
# Check NGINX status
ssh azureuser@<lb-ip> "sudo systemctl status nginx"

# View NGINX error logs
ssh azureuser@<lb-ip> "sudo tail -n 50 /var/log/nginx/error.log"

# Check backend health
ssh azureuser@<lb-ip> "curl http://<webapp1-ip>:3000/api/health"
ssh azureuser@<lb-ip> "curl http://<webapp2-ip>:3000/api/health"
```

**Solutions:**

1. **Restart NGINX:**
   ```bash
   ssh azureuser@<lb-ip> "sudo systemctl restart nginx"
   ```

2. **Test NGINX configuration:**
   ```bash
   ssh azureuser@<lb-ip> "sudo nginx -t"
   ```

3. **Verify backend servers are responsive:**
   ```bash
   # Test each backend individually
   curl http://<webapp1-ip>:3000/api/health
   curl http://<webapp2-ip>:3000/api/health
   ```

### Database Replication Issues

#### Symptom: Replica lag or replication stopped

**Diagnosis:**
```bash
# On primary - check replication status
ssh azureuser@<db-primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'"

# On replica - check receiver status
ssh azureuser@<db-replica-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_wal_receiver;'"

# Check replication lag
ssh azureuser@<db-replica-ip> "sudo -u postgres psql -c 'SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;'"
```

**Solutions:**

1. **Restart replication on replica:**
   ```bash
   ssh azureuser@<db-replica-ip>
   sudo systemctl restart postgresql
   ```

2. **If replication is broken, rebuild replica:**
   ```bash
   # This requires re-running the replica setup script
   ssh azureuser@<db-replica-ip>
   sudo /opt/ecommerce/database/pg-replica-setup.sh
   ```

## Useful Diagnostic Commands

### View All Environment Variables
```bash
ssh azureuser@<webapp-ip> "cat /var/log/exports.log"
```

### View Deployment Logs
```bash
ssh azureuser@<any-ip> "tail -n 100 /var/log/deploy.log"
```

### Test Full Application Stack
```bash
# Test through load balancer
curl http://<lb-ip>/api/db-test

# Check server distribution
for i in {1..10}; do 
  curl -s http://<lb-ip>/api/server-info | jq -r '.serverInfo.webapp.hostname'
done
```

### Monitor Application Performance
```bash
# PM2 monitoring
ssh azureuser@<webapp-ip> "sudo -u webapp pm2 monit"

# Database connections
ssh azureuser@<db-primary-ip> "sudo -u postgres psql -c 'SELECT * FROM pg_stat_activity WHERE datname = '\''ecommerce'\'';'"
```

## Emergency Recovery

### Restart All Web Applications
```bash
# Web server 1
ssh azureuser@<webapp1-ip> "cd /opt/webapp && sudo -u webapp pm2 restart ecommerce-webapp"

# Web server 2
ssh azureuser@<webapp2-ip> "cd /opt/webapp && sudo -u webapp pm2 restart ecommerce-webapp"
```

### Restart Database Primary
```bash
ssh azureuser@<db-primary-ip> "sudo systemctl restart postgresql"
```

### Restart Entire Stack
```bash
# In order: Database, Web Apps, Load Balancer
ssh azureuser@<db-primary-ip> "sudo systemctl restart postgresql"
sleep 10
ssh azureuser@<db-replica-ip> "sudo systemctl restart postgresql"
sleep 10
ssh azureuser@<webapp1-ip> "sudo -u webapp pm2 restart ecommerce-webapp"
ssh azureuser@<webapp2-ip> "sudo -u webapp pm2 restart ecommerce-webapp"
sleep 5
ssh azureuser@<lb-ip> "sudo systemctl restart nginx"
```

## Getting Help

If issues persist:

1. Collect all logs:
   ```bash
   # Create a log bundle
   mkdir -p ~/logs
   ssh azureuser@<webapp-ip> "sudo tar -czf /tmp/webapp-logs.tar.gz /var/log/webapp/ /var/log/deploy.log /var/log/exports.log"
   scp azureuser@<webapp-ip>:/tmp/webapp-logs.tar.gz ~/logs/
   ```

2. Check the architecture documentation: `documentation/ARCHITECTURE.md`
3. Review deployment documentation: `documentation/DEPLOYMENT.md`
4. Check monitoring documentation: `documentation/MONITORING.md`
