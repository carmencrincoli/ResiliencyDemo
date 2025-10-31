# OS-Level Firewall Configuration (UFW)

## Overview

Until Azure Local supports NSG-to-NIC associations, use OS-level firewalls to secure the VMs. This guide provides UFW (Uncomplicated Firewall) configuration for each component.

## Quick Setup

### Load Balancer VM (192.168.2.111)

```bash
# Allow HTTP/HTTPS from Internet, SSH from management
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

### Web Application VMs (192.168.2.114, 192.168.2.115)

```bash
# Allow port 3000 from Load Balancer only, SSH from management
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.2.111 to any port 3000 proto tcp
sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

### PostgreSQL Primary VM (192.168.2.112)

```bash
# Allow PostgreSQL from Web Apps and Replica, SSH from management
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.2.114 to any port 5432 proto tcp  # Web App 1
sudo ufw allow from 192.168.2.115 to any port 5432 proto tcp  # Web App 2
sudo ufw allow from 192.168.2.113 to any port 5432 proto tcp  # Replica
sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

### PostgreSQL Replica VM (192.168.2.113)

```bash
# Allow PostgreSQL from Web Apps (failover), SSH from management
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.2.114 to any port 5432 proto tcp  # Web App 1
sudo ufw allow from 192.168.2.115 to any port 5432 proto tcp  # Web App 2
sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp
sudo ufw enable
sudo ufw status verbose
```

## Deployment Script

Create a script to apply firewall rules after VM deployment:

```bash
#!/bin/bash
# configure-firewalls.sh

# Load Balancer
ssh azureuser@192.168.2.111 'sudo ufw --force reset && \
  sudo ufw default deny incoming && \
  sudo ufw default allow outgoing && \
  sudo ufw allow 80/tcp && \
  sudo ufw allow 443/tcp && \
  sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp && \
  sudo ufw --force enable'

# Web App 1
ssh azureuser@192.168.2.114 'sudo ufw --force reset && \
  sudo ufw default deny incoming && \
  sudo ufw default allow outgoing && \
  sudo ufw allow from 192.168.2.111 to any port 3000 proto tcp && \
  sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp && \
  sudo ufw --force enable'

# Web App 2
ssh azureuser@192.168.2.115 'sudo ufw --force reset && \
  sudo ufw default deny incoming && \
  sudo ufw default allow outgoing && \
  sudo ufw allow from 192.168.2.111 to any port 3000 proto tcp && \
  sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp && \
  sudo ufw --force enable'

# DB Primary
ssh azureuser@192.168.2.112 'sudo ufw --force reset && \
  sudo ufw default deny incoming && \
  sudo ufw default allow outgoing && \
  sudo ufw allow from 192.168.2.114 to any port 5432 proto tcp && \
  sudo ufw allow from 192.168.2.115 to any port 5432 proto tcp && \
  sudo ufw allow from 192.168.2.113 to any port 5432 proto tcp && \
  sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp && \
  sudo ufw --force enable'

# DB Replica
ssh azureuser@192.168.2.113 'sudo ufw --force reset && \
  sudo ufw default deny incoming && \
  sudo ufw default allow outgoing && \
  sudo ufw allow from 192.168.2.114 to any port 5432 proto tcp && \
  sudo ufw allow from 192.168.2.115 to any port 5432 proto tcp && \
  sudo ufw allow from 192.168.2.0/24 to any port 22 proto tcp && \
  sudo ufw --force enable'

echo "Firewall configuration complete!"
```

## Management Commands

### Check UFW Status
```bash
sudo ufw status verbose
sudo ufw status numbered
```

### View Active Rules
```bash
sudo ufw show listening
```

### Temporarily Disable (for troubleshooting)
```bash
sudo ufw disable
```

### Re-enable
```bash
sudo ufw enable
```

### Delete a Rule
```bash
# By rule number
sudo ufw status numbered
sudo ufw delete [number]

# By rule specification
sudo ufw delete allow from 192.168.2.111 to any port 3000 proto tcp
```

### Reset All Rules
```bash
sudo ufw --force reset
```

## Troubleshooting

### Cannot Connect After Enabling UFW

1. **Check UFW status:**
   ```bash
   sudo ufw status verbose
   ```

2. **Verify your IP is in allowed range:**
   ```bash
   # If connecting from 192.168.2.50, ensure rules allow 192.168.2.0/24
   ```

3. **Temporarily disable to test:**
   ```bash
   sudo ufw disable
   # Test connection
   sudo ufw enable
   ```

### Application Not Working

1. **Check specific service ports:**
   ```bash
   sudo ufw status | grep [port]
   ```

2. **Test connectivity:**
   ```bash
   # From Load Balancer to Web App
   nc -zv 192.168.2.114 3000
   
   # From Web App to Database
   nc -zv 192.168.2.112 5432
   ```

3. **Review UFW logs:**
   ```bash
   sudo tail -f /var/log/ufw.log
   ```

### Enable Logging

```bash
# Enable logging
sudo ufw logging on

# Set log level
sudo ufw logging medium  # or: low, high, full

# View logs
sudo tail -f /var/log/ufw.log
```

## Security Best Practices

✅ **DO:**
- Always test connectivity after applying rules
- Document any custom rules you add
- Use specific IP addresses instead of broad ranges when possible
- Enable UFW logging for troubleshooting
- Keep UFW enabled at all times

❌ **DON'T:**
- Use `allow from any` rules unnecessarily
- Disable UFW without documenting why
- Forget to re-enable UFW after troubleshooting
- Apply rules without testing in a non-production environment first

## Migrating to NSG

When Azure Local adds NSG support:

1. Deploy the NSG module (uncomment in `main.bicep`)
2. Verify NSG rules are working
3. Disable UFW on each VM:
   ```bash
   sudo ufw disable
   ```
4. Test all connectivity
5. Document the migration

## Additional Resources

- [UFW Documentation](https://help.ubuntu.com/community/UFW)
- [Network Security Guide](NETWORK_SECURITY.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
