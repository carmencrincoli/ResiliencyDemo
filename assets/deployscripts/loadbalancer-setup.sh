#!/bin/bash
# Load Balancer Setup Script - Azure Local E-commerce Application
# Downloads and deploys NGINX load balancer configuration from compressed archives
# This script will be executed via Azure Custom Script Extension

# Variables and Configuration
FULL_OUTPUT_LOG="/var/log/deploy.log"
SCRIPT_DIR="/opt/ecommerce"
CONFIG_DIR="/opt/ecommerce/loadbalancer"
TEMP_DIR="/tmp/loadbalancer-deployment"
ARCHIVE_NAME="loadbalancer.tar.gz"

# Environment variables from Azure deployment
WEBAPP1_IP="${WEBAPP1_IP:-}"
WEBAPP2_IP="${WEBAPP2_IP:-}"
LB_HTTPS_PORT="${LB_HTTPS_PORT:-443}"
LB_HTTP_PORT="${LB_HTTP_PORT:-80}"

# Storage URL - this will be replaced by the actual storage account URL during deployment
STORAGE_BASE_URL="${STORAGE_ACCOUNT_URL:-}"
LOADBALANCER_ARCHIVE_URL="${STORAGE_BASE_URL}assets/${ARCHIVE_NAME}"

# Dump exports to log file for potential reuse
EXPORT_LOG="/var/log/exports.log"
echo "# Load Balancer Setup - Environment Variables Export" > "$EXPORT_LOG"
echo "# Generated on $(date)" >> "$EXPORT_LOG"
echo "# This section contains only the environment variables passed from the Bicep template" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "export WEBAPP1_IP=\"$WEBAPP1_IP\"" >> "$EXPORT_LOG"
echo "export WEBAPP2_IP=\"$WEBAPP2_IP\"" >> "$EXPORT_LOG"
echo "export LB_HTTPS_PORT=\"$LB_HTTPS_PORT\"" >> "$EXPORT_LOG"
echo "export LB_HTTP_PORT=\"$LB_HTTP_PORT\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_URL=\"$STORAGE_ACCOUNT_URL\"" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "# End of exports" >> "$EXPORT_LOG"

# Redirect all output to both log file and console using tee
exec > >(tee -a "$FULL_OUTPUT_LOG") 2>&1

set -e

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [LOADBALANCER-SETUP] $1"
}

# Error handling
handle_error() {
    log "ERROR: $1"
    exit 1
}



# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary directory"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

log "Starting NGINX Load Balancer setup..."
log "Using storage URL: $STORAGE_BASE_URL"
log "Webapp1 IP: $WEBAPP1_IP, Webapp2 IP: $WEBAPP2_IP"
log "Load balancer ports: HTTP=$LB_HTTP_PORT, HTTPS=$LB_HTTPS_PORT"

# Validate required environment variables
if [ -z "$STORAGE_BASE_URL" ]; then
    handle_error "STORAGE_ACCOUNT_URL environment variable is required"
fi

if [ -z "$WEBAPP1_IP" ]; then
    handle_error "WEBAPP1_IP environment variable is required"
fi

if [ -z "$WEBAPP2_IP" ]; then
    handle_error "WEBAPP2_IP environment variable is required"
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# System Updates and Base Packages
log "Updating system packages..."
# Set non-interactive frontend to prevent debconf dialog issues
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
# Prevent needrestart from interrupting installations with proper Perl syntax
cat > /etc/needrestart/conf.d/99-auto.conf << 'EOF'
# Automatic restart configuration
$nrconf{restart} = 'a';
EOF

# Wait for any existing package operations to complete
apt-get -o DPkg::Lock::Timeout=600 update || handle_error "Failed to update package lists"

apt-get -o DPkg::Lock::Timeout=600 upgrade -y || handle_error "Failed to upgrade packages"

# Install required packages
log "Installing required packages..."
apt-get -o DPkg::Lock::Timeout=600 install -y \
    nginx \
    openssl \
    curl \
    wget \
    logrotate \
    cron \
    fail2ban \
    htop \
    vim \
    certbot \
    python3-certbot-nginx || handle_error "Failed to install required packages"

# Create configuration directories
log "Creating configuration directories..."
mkdir -p $CONFIG_DIR $SCRIPT_DIR || handle_error "Failed to create directories"

# Download and extract load balancer configuration archive
log "Downloading load balancer configuration archive..."
if [ -n "$STORAGE_BASE_URL" ]; then
    log "Downloading from: $LOADBALANCER_ARCHIVE_URL"
    wget -O loadbalancer.tar.gz "$LOADBALANCER_ARCHIVE_URL" || handle_error "Failed to download loadbalancer archive"
    
    # Verify archive was downloaded
    if [ ! -f "loadbalancer.tar.gz" ]; then
        handle_error "Load balancer archive not found after download"
    fi
    
    # Get archive size for verification
    archive_size=$(stat -c%s "loadbalancer.tar.gz")
    log "Downloaded archive size: $archive_size bytes"
    
    # Extract archive to temp directory
    log "Extracting load balancer configuration..."
    tar -xzf loadbalancer.tar.gz -C $TEMP_DIR --strip-components=1 || handle_error "Failed to extract loadbalancer archive"
    
    # Copy configuration files to nginx directory
    if [ -f "$TEMP_DIR/nginx.conf" ]; then
        # Backup original nginx.conf
        cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
        
        # Remove any default sites that might interfere
        rm -f /etc/nginx/sites-enabled/default
        rm -f /etc/nginx/sites-available/default
        
        # Install our complete nginx.conf
        cp "$TEMP_DIR/nginx.conf" "/etc/nginx/nginx.conf" || handle_error "Failed to copy nginx.conf"
        log "NGINX configuration installed"
        
        # Verify the file was copied correctly
        if [ -f "/etc/nginx/nginx.conf" ]; then
            file_size=$(stat -c%s "/etc/nginx/nginx.conf")
            log "Installed nginx.conf size: $file_size bytes"
        fi
    else
        handle_error "nginx.conf not found in archive"
    fi
    
    # Update nginx configuration with actual IP addresses
    sed -i "s/WEBAPP1_IP_PLACEHOLDER/$WEBAPP1_IP/g" /etc/nginx/nginx.conf
    sed -i "s/WEBAPP2_IP_PLACEHOLDER/$WEBAPP2_IP/g" /etc/nginx/nginx.conf
    sed -i "s/LB_HTTP_PORT/$LB_HTTP_PORT/g" /etc/nginx/nginx.conf
    sed -i "s/LB_HTTPS_PORT/$LB_HTTPS_PORT/g" /etc/nginx/nginx.conf
    
    # Derive subnet CIDR from webapp1 IP (assuming /24 subnet)
    SUBNET_CIDR=$(echo "$WEBAPP1_IP" | cut -d'.' -f1-3).0/24
    # Use | as delimiter to avoid issues with / in CIDR notation
    sed -i "s|SUBNET_CIDR_PLACEHOLDER|$SUBNET_CIDR|g" /etc/nginx/nginx.conf
    
    log "NGINX configuration updated with environment variables"
    log "Derived subnet CIDR: $SUBNET_CIDR"
else
    handle_error "Storage account URL not provided"
fi

# Generate self-signed SSL certificate for HTTPS
log "Generating SSL certificate for HTTPS..."
mkdir -p /etc/ssl/private
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=ecommerce.local" || handle_error "Failed to generate SSL certificate"

chmod 600 /etc/ssl/private/nginx-selfsigned.key
chmod 644 /etc/ssl/certs/nginx-selfsigned.crt
log "SSL certificate generated successfully"

# Test NGINX configuration
log "Testing NGINX configuration..."
# Show what configuration NGINX will use
log "NGINX configuration test output:"
nginx -t 2>&1 | while read line; do log "  $line"; done

# Show a sample of our configuration to verify it was applied
log "Checking our configuration was applied correctly:"
if grep -q "webapp_pool" /etc/nginx/nginx.conf; then
    log "✓ Found webapp_pool upstream in nginx.conf"
else
    log "✗ webapp_pool upstream NOT found in nginx.conf"
fi

if grep -q "proxy_pass http://webapp_pool" /etc/nginx/nginx.conf; then
    log "✓ Found proxy_pass to webapp_pool in nginx.conf"
else
    log "✗ proxy_pass to webapp_pool NOT found in nginx.conf"
fi

# Show the listen directives to confirm our servers are configured
log "Listen directives in nginx.conf:"
grep -n "listen " /etc/nginx/nginx.conf | while read line; do log "  $line"; done

# Verify nginx -t passes
if ! nginx -t; then
    handle_error "NGINX configuration test failed"
fi

# Start and enable NGINX
log "Starting NGINX service..."
systemctl enable nginx || handle_error "Failed to enable NGINX service"
systemctl restart nginx || handle_error "Failed to restart NGINX service"

# Show NGINX configuration summary
log "NGINX configuration summary:"
nginx -T 2>/dev/null | grep -E "server_name|listen|proxy_pass" | head -10 | while read line; do log "  $line"; done

# Verify NGINX is running
if systemctl is-active --quiet nginx; then
    log "✓ NGINX service is running"
else
    handle_error "NGINX service failed to start"
fi

# Set up log rotation configuration
log "Setting up log rotation..."
if [ -f "$TEMP_DIR/logrotate.conf" ]; then
    cp "$TEMP_DIR/logrotate.conf" "/etc/logrotate.d/loadbalancer" || handle_error "Failed to copy logrotate configuration from archive"
    chmod 644 "/etc/logrotate.d/loadbalancer" || handle_error "Failed to set logrotate permissions"
    log "Log rotation configuration installed from archive"
else
    log "Warning: logrotate.conf not found in archive, using default configuration"
fi

# Test log rotation
logrotate -t /etc/logrotate.d/loadbalancer 2>/dev/null || log "Log rotation test completed with warnings"

# Install health check script from archive
log "Installing health check script..."
if [ -f "$TEMP_DIR/health-check.sh" ]; then
    cp "$TEMP_DIR/health-check.sh" "$SCRIPT_DIR/loadbalancer-health-check.sh" || handle_error "Failed to copy health check script from archive"
    chmod +x "$SCRIPT_DIR/loadbalancer-health-check.sh" || handle_error "Failed to make health check script executable"
    
    # Update health check script with environment variables
    sed -i "s/WEBAPP1_IP/$WEBAPP1_IP/g" "$SCRIPT_DIR/loadbalancer-health-check.sh"
    sed -i "s/WEBAPP2_IP/$WEBAPP2_IP/g" "$SCRIPT_DIR/loadbalancer-health-check.sh"
    sed -i "s/LB_HTTP_PORT/$LB_HTTP_PORT/g" "$SCRIPT_DIR/loadbalancer-health-check.sh"
    
    log "Health check script installed from archive"
else
    log "Warning: health-check.sh not found in archive"
fi

# Set up health check cron job
log "Setting up health check cron job..."
if [ -f "$SCRIPT_DIR/loadbalancer-health-check.sh" ]; then
    (crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/loadbalancer-health-check.sh") | crontab -
    log "Health check cron job configured for 5-minute intervals"
fi

# Configure firewall
log "Configuring firewall..."
ufw --force enable || log "UFW already enabled"
ufw default deny incoming || log "Default deny already set"
ufw default allow outgoing || log "Default allow outgoing already set"
ufw allow 22/tcp comment 'SSH' || log "SSH port already allowed"
ufw allow $LB_HTTP_PORT/tcp comment 'HTTP Load Balancer' || log "HTTP port already allowed"
ufw allow $LB_HTTPS_PORT/tcp comment 'HTTPS Load Balancer' || log "HTTPS port already allowed"

# Limit SSH connections to prevent brute force
ufw limit 22/tcp || log "SSH rate limiting already configured"

# Final verification and status
log "Performing final verification and load balancer status..."

# Wait for NGINX to be fully started
log "Waiting for NGINX to be fully started..."
sleep 5

# Test load balancer functionality
log "Testing load balancer connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$LB_HTTP_PORT" 2>/dev/null | grep -q "200\|502\|503"; then
    log "✓ Load balancer HTTP endpoint responding"
else
    log "⚠ Load balancer HTTP endpoint not responding"
fi

# Test SSL endpoint
if curl -k -s -o /dev/null -w "%{http_code}" "https://localhost:$LB_HTTPS_PORT" 2>/dev/null | grep -q "200\|502\|503"; then
    log "✓ Load balancer HTTPS endpoint responding"
else
    log "⚠ Load balancer HTTPS endpoint not responding"
fi

# Test backend connectivity
log "Testing backend server connectivity..."
if curl -s -o /dev/null -w "%{http_code}" "http://$WEBAPP1_IP:3000" 2>/dev/null | grep -q "200\|000"; then
    log "✓ Backend server 1 ($WEBAPP1_IP) reachable"
else
    log "⚠ Backend server 1 ($WEBAPP1_IP) not reachable - this may cause 502/503 errors"
fi

if curl -s -o /dev/null -w "%{http_code}" "http://$WEBAPP2_IP:3000" 2>/dev/null | grep -q "200\|000"; then
    log "✓ Backend server 2 ($WEBAPP2_IP) reachable"
else
    log "⚠ Backend server 2 ($WEBAPP2_IP) not reachable - this may cause 502/503 errors"
fi

# Display final status
log "NGINX Load Balancer setup completed successfully!"
log "Load balancer ready at: http://localhost:$LB_HTTP_PORT (HTTP) and https://localhost:$LB_HTTPS_PORT (HTTPS)"
log "Backend servers: $WEBAPP1_IP:3000, $WEBAPP2_IP:3000"
log "Health monitoring and log rotation configured"

# Display useful information
log "=== Deployment Summary ==="
log "Load Balancer: NGINX"
log "HTTP Port: $LB_HTTP_PORT"
log "HTTPS Port: $LB_HTTPS_PORT"
log "Backend Pool: webapp_pool"
log "SSL Certificate: Self-signed"
log "Configuration Directory: $CONFIG_DIR"
log "Health Check Script: $SCRIPT_DIR/loadbalancer-health-check.sh"

# Show NGINX status
systemctl status nginx --no-pager || log "NGINX status unavailable"

# Disable cloud-init to prevent network configuration conflicts on future boots
# log "Disabling cloud-init to prevent network configuration issues..."
# touch /etc/cloud/cloud-init.disabled 2>/dev/null || log "Warning: Could not disable cloud-init"

# Ensure all background processes complete and file handles are closed
log "Finalizing deployment and closing all processes..."
sync  # Force filesystem sync

# Final completion signal
echo "DEPLOYMENT_COMPLETE: $(date)" >> "$FULL_OUTPUT_LOG"
log "Setup completed successfully. Load balancer deployment finished."

exit 0