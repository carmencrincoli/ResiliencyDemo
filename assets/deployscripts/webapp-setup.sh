#!/bin/bash
# Next.js Web Application Setup Script - Azure Local E-commerce Application
# Downloads and deploys Next.js full-stack application from compressed archives
# This script will be executed via Azure Custom Script Extension

# Variables and Configuration
FULL_OUTPUT_LOG="/var/log/deploy.log"
SCRIPT_DIR="/opt/ecommerce"
TEMP_DIR="/tmp/webapp-deployment"
APP_NAME="ecommerce-webapp"
APP_USER="webapp"
APP_DIR="/opt/webapp"
LOG_DIR="/var/log/webapp"
ARCHIVE_NAME="webapp.tar.gz"
NODE_VERSION="${NODE_VERSION:-18}"

# Environment variables from Azure deployment
VM_NAME="${VM_NAME:-$(hostname)}"
DB_PRIMARY_HOST="${DB_PRIMARY_HOST:-localhost}"
DB_REPLICA_HOST="${DB_REPLICA_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-ecommerce}"
DB_USER="${DB_USER:-ecommerce_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
PORT="${PORT:-3000}"

# Storage URL - this will be replaced by the actual storage account URL during deployment
STORAGE_BASE_URL="${STORAGE_ACCOUNT_URL:-}"
WEBAPP_ARCHIVE_URL="${STORAGE_BASE_URL}assets/${ARCHIVE_NAME}"

# Dump exports to log file for potential reuse
EXPORT_LOG="/var/log/exports.log"
echo "# Next.js Web Application Setup - Environment Variables Export" > "$EXPORT_LOG"
echo "# Generated on $(date)" >> "$EXPORT_LOG"
echo "# Cut and paste these exports if you need to recreate the environment" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "export DB_PRIMARY_HOST=\"$DB_PRIMARY_HOST\"" >> "$EXPORT_LOG"
echo "export DB_REPLICA_HOST=\"$DB_REPLICA_HOST\"" >> "$EXPORT_LOG"
echo "export DB_PASSWORD=\"$DB_PASSWORD\"" >> "$EXPORT_LOG"
echo "export NODE_VERSION=\"$NODE_VERSION\"" >> "$EXPORT_LOG"
echo "export PORT=\"$PORT\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_URL=\"$STORAGE_ACCOUNT_URL\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_NAME=\"$STORAGE_ACCOUNT_NAME\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_KEY=\"$STORAGE_ACCOUNT_KEY\"" >> "$EXPORT_LOG"
echo "export HTTP_PROXY=\"$HTTP_PROXY\"" >> "$EXPORT_LOG"
echo "export HTTPS_PROXY=\"$HTTPS_PROXY\"" >> "$EXPORT_LOG"
echo "export NO_PROXY=\"$NO_PROXY\"" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "# End of exports" >> "$EXPORT_LOG"

# Redirect all output to both log file and console using tee
exec > >(tee -a "$FULL_OUTPUT_LOG") 2>&1

set -e

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WEBAPP-SETUP] $1"
}

# Error handling
handle_error() {
    log "ERROR: $1"
    exit 1
}

# ==============================================================================
# SHELL CONFIGURATION AND SYSTEM PREPARATION
# ==============================================================================
log "Starting system preparation and shell configuration..."

# Disable automatic updates to prevent package lock conflicts during deployment
log "Stopping and disabling unattended-upgrades to prevent lock conflicts..."
systemctl stop unattended-upgrades 2>/dev/null || log "unattended-upgrades not running"
systemctl disable unattended-upgrades 2>/dev/null || log "unattended-upgrades not installed"

# Stop apt-daily services that can cause lock conflicts
log "Stopping apt-daily services..."
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service 2>/dev/null || true
systemctl stop apt-daily-upgrade.service 2>/dev/null || true

# Configure bash as default shell
log "Configuring bash as default shell..."
export SHELL="/bin/bash"

# Add bash to shells if not present
if [[ ! -f "/etc/shells" ]] || ! grep -q "^/bin/bash$" /etc/shells 2>/dev/null; then
    echo "/bin/bash" >> /etc/shells 2>/dev/null || log "Could not update /etc/shells"
    log "Added /bin/bash to /etc/shells"
fi

# Configure default shell for new users
if [[ -f "/etc/default/useradd" ]]; then
    if grep -q "^SHELL=" /etc/default/useradd 2>/dev/null; then
        sed -i 's|^SHELL=.*|SHELL=/bin/bash|' /etc/default/useradd 2>/dev/null || log "Could not update useradd default shell"
    else
        echo "SHELL=/bin/bash" >> /etc/default/useradd 2>/dev/null || log "Could not add default shell to useradd"
    fi
else
    echo "SHELL=/bin/bash" > /etc/default/useradd 2>/dev/null || log "Could not create useradd configuration"
fi

# Update root shell
if command -v usermod &>/dev/null; then
    usermod -s /bin/bash root || log "Could not update root shell via usermod"
    log "Set bash as default shell for root"
fi

# Update ubuntu user shell if exists
if id ubuntu &>/dev/null && command -v usermod &>/dev/null; then
    usermod -s /bin/bash ubuntu || log "Could not update ubuntu shell via usermod"
    log "Set bash as default shell for ubuntu user"
fi

log "System preparation and shell configuration completed"

# ==============================================================================
# PROXY CONFIGURATION
# ==============================================================================
log "Configuring proxy settings..."

# Get proxy environment variables from Bicep deployment
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"

# Configure system-wide proxy if proxy values are provided
if [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
    log "Proxy configuration detected - setting up system-wide proxy settings"
    
    # Configure environment-wide proxy in /etc/environment
    log "Configuring /etc/environment for system-wide proxy..."
    {
        echo "# Proxy configuration added by deployment script"
        [ -n "$HTTP_PROXY" ] && echo "http_proxy=\"$HTTP_PROXY\""
        [ -n "$HTTP_PROXY" ] && echo "HTTP_PROXY=\"$HTTP_PROXY\""
        [ -n "$HTTPS_PROXY" ] && echo "https_proxy=\"$HTTPS_PROXY\""
        [ -n "$HTTPS_PROXY" ] && echo "HTTPS_PROXY=\"$HTTPS_PROXY\""
        [ -n "$NO_PROXY" ] && echo "no_proxy=\"$NO_PROXY\""
        [ -n "$NO_PROXY" ] && echo "NO_PROXY=\"$NO_PROXY\""
    } >> /etc/environment
    
    # Export proxy for current session
    [ -n "$HTTP_PROXY" ] && export http_proxy="$HTTP_PROXY"
    [ -n "$HTTP_PROXY" ] && export HTTP_PROXY="$HTTP_PROXY"
    [ -n "$HTTPS_PROXY" ] && export https_proxy="$HTTPS_PROXY"
    [ -n "$HTTPS_PROXY" ] && export HTTPS_PROXY="$HTTPS_PROXY"
    [ -n "$NO_PROXY" ] && export no_proxy="$NO_PROXY"
    [ -n "$NO_PROXY" ] && export NO_PROXY="$NO_PROXY"
    
    # Configure APT proxy
    log "Configuring APT to use proxy..."
    cat > /etc/apt/apt.conf.d/95proxies << EOF
# Proxy configuration for APT
Acquire::http::Proxy "$HTTP_PROXY";
Acquire::https::Proxy "$HTTPS_PROXY";
EOF
    
    # Configure npm proxy if npm is installed or will be installed
    log "Configuring npm proxy settings..."
    mkdir -p /root/.npm
    cat > /root/.npmrc << EOF
# Proxy configuration for npm
proxy=$HTTP_PROXY
https-proxy=$HTTPS_PROXY
noproxy=$NO_PROXY
strict-ssl=false
EOF
    chmod 600 /root/.npmrc
    
    log "Proxy configuration completed: HTTP_PROXY=$HTTP_PROXY, HTTPS_PROXY=$HTTPS_PROXY, NO_PROXY=$NO_PROXY"
else
    log "No proxy configuration provided - skipping proxy setup"
fi

# ==============================================================================
# MAIN DEPLOYMENT SECTION
# ==============================================================================

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary directory"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

log "Starting Next.js Web Application setup..."
log "Using storage URL: $STORAGE_BASE_URL"
log "Primary DB: $DB_PRIMARY_HOST, Replica DB: $DB_REPLICA_HOST"
log "Application will run on port: $PORT"

# Validate required environment variables
if [ -z "$DB_PASSWORD" ]; then
    handle_error "DB_PASSWORD environment variable is required"
fi

if [ -z "$DB_PRIMARY_HOST" ] || [ "$DB_PRIMARY_HOST" = "localhost" ]; then
    handle_error "Valid DB_PRIMARY_HOST environment variable is required"
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

# Install essential packages that may be missing in minimal Ubuntu images
log "Installing essential system packages..."
apt-get -o DPkg::Lock::Timeout=600 install -y \
    ufw \
    cron \
    lsof \
    logrotate \
    locales \
    lsb-release || handle_error "Failed to install essential packages"

# Configure locale
log "Configuring en_US.UTF-8 locale..."
locale-gen en_US.UTF-8 || handle_error "Failed to generate en_US.UTF-8 locale"
update-locale LANG=en_US.UTF-8 || handle_error "Failed to update locale"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
log "Locale configuration completed"

# Install required packages
log "Installing required packages..."
apt-get -o DPkg::Lock::Timeout=600 install -y \
    curl \
    wget \
    unzip \
    nginx \
    postgresql-client \
    fail2ban \
    netstat-nat \
    htop \
    vim \
    git || handle_error "Failed to install required packages"

# Install Node.js
log "Installing Node.js version $NODE_VERSION..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - || handle_error "Failed to setup Node.js repository"

apt-get -o DPkg::Lock::Timeout=600 install -y nodejs || handle_error "Failed to install Node.js"

# Verify Node.js installation
node_version=$(node --version)
npm_version=$(npm --version)
log "Node.js installed: $node_version, npm: $npm_version"

# Install PM2 globally
log "Installing PM2 process manager..."
npm install -g pm2 || handle_error "Failed to install PM2"

# Create application user
log "Creating application user: $APP_USER"
if ! id "$APP_USER" &>/dev/null; then
    useradd -r -s /bin/bash -d $APP_DIR $APP_USER || handle_error "Failed to create application user"
fi

# Create application directories
log "Creating application directories..."
mkdir -p $APP_DIR $LOG_DIR $SCRIPT_DIR || handle_error "Failed to create directories"
chown -R $APP_USER:$APP_USER $APP_DIR $LOG_DIR || handle_error "Failed to set directory ownership"

# Download and extract web application archive
log "Downloading web application archive..."
if [ -n "$STORAGE_BASE_URL" ]; then
    log "Downloading from: $WEBAPP_ARCHIVE_URL"
    # Parse storage account name from URL
    STORAGE_ACCOUNT=$(echo "$STORAGE_BASE_URL" | sed -n 's/.*\/\/\([^.]*\).*/\1/p')
    CONTAINER_NAME="assets"
    BLOB_NAME="webapp.tar.gz"
    
    log "Storage Account: $STORAGE_ACCOUNT, Container: $CONTAINER_NAME, Blob: $BLOB_NAME"
    az storage blob download \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER_NAME" \
        --name "$BLOB_NAME" \
        --file "webapp.tar.gz" \
        --account-key "$STORAGE_ACCOUNT_KEY" || handle_error "Failed to download webapp archive"
    
    # Verify archive was downloaded
    if [ ! -f "webapp.tar.gz" ]; then
        handle_error "Webapp archive not found after download"
    fi
    
    # Get archive size for verification
    archive_size=$(stat -c%s "webapp.tar.gz")
    log "Downloaded archive size: $archive_size bytes"
    
    # Extract archive to temp directory
    log "Extracting webapp application..."
    tar -xzf webapp.tar.gz -C $TEMP_DIR --strip-components=1 || handle_error "Failed to extract webapp archive"
    
    # Copy only application files to app directory (exclude config files)
    log "Copying application files to app directory..."
    # Copy source code and package files
    if [ -d "$TEMP_DIR/src" ]; then
        cp -r "$TEMP_DIR/src" "$APP_DIR/" || handle_error "Failed to copy src directory"
    fi
    
    # Copy essential Node.js files
    for file in package.json tsconfig.json next.config.js postcss.config.js tailwind.config.js; do
        if [ -f "$TEMP_DIR/$file" ]; then
            cp "$TEMP_DIR/$file" "$APP_DIR/" || log "Warning: Could not copy $file"
        fi
    done
    
    # Copy any other directories that should be in the app (but not config files)
    for dir in public components pages styles lib utils; do
        if [ -d "$TEMP_DIR/$dir" ]; then
            cp -r "$TEMP_DIR/$dir" "$APP_DIR/" || log "Warning: Could not copy $dir directory"
        fi
    done
    
    # Verify extraction
    if [ ! -f "$APP_DIR/package.json" ]; then
        handle_error "package.json not found after extraction - invalid webapp archive"
    fi
    
    chown -R $APP_USER:$APP_USER $APP_DIR || handle_error "Failed to set application directory ownership"
    log "Webapp application extracted successfully"
else
    handle_error "Storage account URL not provided"
fi

# Create environment file
log "Creating environment configuration..."
SERVER_IP=$(hostname -I | awk '{print $1}' | tr -d ' ')
SERVER_HOSTNAME=$(hostname)

cat > $APP_DIR/.env.production << EOF
NODE_ENV=production
PORT=$PORT
SERVER_IP=$SERVER_IP
SERVER_HOSTNAME=$SERVER_HOSTNAME
DB_PRIMARY_HOST=$DB_PRIMARY_HOST
DB_REPLICA_HOST=$DB_REPLICA_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_SSL=false
EOF

chown $APP_USER:$APP_USER $APP_DIR/.env.production || handle_error "Failed to set .env.production ownership"
chmod 600 $APP_DIR/.env.production || handle_error "Failed to set .env.production permissions"

# Install dependencies
log "Installing application dependencies..."
cd $APP_DIR
if [ -f package.json ]; then
    sudo -u $APP_USER npm ci --only=production 2>/dev/null || sudo -u $APP_USER npm install || handle_error "Failed to install npm dependencies"
    
    # Build the application if build script exists
    if grep -q '"build"' package.json; then
        log "Building application..."
        sudo -u $APP_USER npm run build || handle_error "Failed to build application"
    fi
else
    handle_error "package.json not found in application directory"
fi

# Install PM2 ecosystem file from archive
log "Setting up PM2 configuration..."
if [ ! -f "$TEMP_DIR/ecosystem.config.js" ]; then
    handle_error "PM2 configuration file (ecosystem.config.js) not found in archive"
fi

log "Installing PM2 configuration from archive..."
cp "$TEMP_DIR/ecosystem.config.js" "$APP_DIR/ecosystem.config.js" || handle_error "Failed to copy PM2 config from archive"

# Substitute environment variables in PM2 config
# These placeholders are replaced with actual values for PM2 to use
sed -i "s/\${PORT}/$PORT/g" "$APP_DIR/ecosystem.config.js" || log "PORT substitution in PM2 config"
sed -i "s/\${APP_NAME}/$APP_NAME/g" "$APP_DIR/ecosystem.config.js" || log "APP_NAME substitution in PM2 config"
sed -i "s/\${LOG_DIR}/$LOG_DIR/g" "$APP_DIR/ecosystem.config.js" || log "LOG_DIR substitution in PM2 config"
sed -i "s/\${SERVER_IP}/$SERVER_IP/g" "$APP_DIR/ecosystem.config.js" || log "SERVER_IP substitution in PM2 config"
sed -i "s/\${SERVER_HOSTNAME}/$SERVER_HOSTNAME/g" "$APP_DIR/ecosystem.config.js" || log "SERVER_HOSTNAME substitution in PM2 config"
sed -i "s/\${DB_PRIMARY_HOST}/$DB_PRIMARY_HOST/g" "$APP_DIR/ecosystem.config.js" || log "DB_PRIMARY_HOST substitution in PM2 config"
sed -i "s/\${DB_REPLICA_HOST}/$DB_REPLICA_HOST/g" "$APP_DIR/ecosystem.config.js" || log "DB_REPLICA_HOST substitution in PM2 config"
sed -i "s/\${DB_PORT}/$DB_PORT/g" "$APP_DIR/ecosystem.config.js" || log "DB_PORT substitution in PM2 config"
sed -i "s/\${DB_NAME}/$DB_NAME/g" "$APP_DIR/ecosystem.config.js" || log "DB_NAME substitution in PM2 config"
sed -i "s/\${DB_USER}/$DB_USER/g" "$APP_DIR/ecosystem.config.js" || log "DB_USER substitution in PM2 config"
# Special handling for DB_PASSWORD to escape special characters
DB_PASSWORD_ESCAPED=$(echo "$DB_PASSWORD" | sed 's/[&/\]/\\&/g')
sed -i "s/\${DB_PASSWORD}/$DB_PASSWORD_ESCAPED/g" "$APP_DIR/ecosystem.config.js" || log "DB_PASSWORD substitution in PM2 config"
sed -i "s/\${DB_SSL}/false/g" "$APP_DIR/ecosystem.config.js" || log "DB_SSL substitution in PM2 config"

chown $APP_USER:$APP_USER $APP_DIR/ecosystem.config.js || handle_error "Failed to set PM2 config ownership"

# Set up log rotation configuration
log "Setting up log rotation..."
if [ ! -f "$TEMP_DIR/logrotate.conf" ]; then
    handle_error "Log rotation configuration file (logrotate.conf) not found in archive"
fi

cp "$TEMP_DIR/logrotate.conf" "/etc/logrotate.d/webapp" || handle_error "Failed to copy logrotate configuration from archive"
chmod 644 "/etc/logrotate.d/webapp" || handle_error "Failed to set logrotate permissions"
log "Log rotation configuration installed from archive"

# Test log rotation
logrotate -t /etc/logrotate.d/webapp || log "Log rotation test completed with warnings"

# Start the application with PM2
log "Starting web application with PM2..."
cd $APP_DIR
sudo -u $APP_USER bash -c "
    cd $APP_DIR
    pm2 start ecosystem.config.js || exit 1
    pm2 save
" || handle_error "Failed to start application with PM2"

# Setup PM2 to start on boot
log "Configuring PM2 for automatic startup..."
PM2_STARTUP_SCRIPT=$(sudo -u $APP_USER pm2 startup systemd -u $APP_USER --hp $APP_DIR 2>/dev/null | tail -1)
if [ -n "$PM2_STARTUP_SCRIPT" ]; then
    eval "$PM2_STARTUP_SCRIPT" || log "Warning: PM2 startup configuration may need manual setup"
    log "PM2 startup configuration completed"
else
    log "Warning: PM2 startup command not generated"
fi

# Create systemd service for PM2
log "Creating systemd service..."
pm2 install pm2-logrotate

# Start PM2 as the app user
log "Starting web application with PM2..."
sudo -u $APP_USER bash -c "
    cd $APP_DIR
    pm2 start ecosystem.config.js
    pm2 save
"

# Create PM2 systemd startup script
env_path=$(sudo -u $APP_USER pm2 startup | grep -o 'env PATH.*' | head -1) || true
if [ -n "$env_path" ]; then
    startup_command=$(sudo -u $APP_USER pm2 startup systemd -u $APP_USER --hp $APP_DIR | tail -1)
    eval "$startup_command" || log "Warning: PM2 startup configuration may need manual setup"
fi

# Configure firewall with security hardening
log "Configuring firewall with security hardening..."
ufw --force enable || log "UFW already enabled"
ufw default deny incoming || log "Default deny already set"
ufw default allow outgoing || log "Default allow outgoing already set"
ufw allow 22/tcp comment 'SSH' || log "SSH port already allowed"
ufw allow $PORT/tcp comment 'Next.js Application' || log "Application port already allowed"

# Limit SSH connections to prevent brute force
ufw limit 22/tcp || log "SSH rate limiting already configured"

# Install health check script from archive
log "Installing health check script..."
if [ ! -f "$TEMP_DIR/health-check.sh" ]; then
    handle_error "Health check script (health-check.sh) not found in archive"
fi

cp "$TEMP_DIR/health-check.sh" "$SCRIPT_DIR/webapp-health-check.sh" || handle_error "Failed to copy health check script from archive"
chmod +x "$SCRIPT_DIR/webapp-health-check.sh" || handle_error "Failed to make health check script executable"

# Set environment variables in health check script
sed -i "s/\${PORT}/$PORT/g" "$SCRIPT_DIR/webapp-health-check.sh" || log "PORT substitution in health check script"
log "Health check script installed from archive"

# Set up health check cron job
log "Setting up health check cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/webapp-health-check.sh") | crontab -

# Final verification and status
log "Performing final verification and collecting application status..."

# Wait for application to be fully started
log "Waiting for application to be fully started..."
sleep 10

# Check PM2 process status
PM2_STATUS=$(sudo -u $APP_USER pm2 jlist 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ "$PM2_STATUS" = "online" ]; then
    log "✓ Application process status: online"
else
    log "⚠ Application process status: ${PM2_STATUS:-unknown}"
fi

# Test local HTTP connectivity
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -q "200"; then
    log "✓ Local HTTP connectivity successful"
else
    log "⚠ Local HTTP connectivity failed"
fi

# Test database connectivity
log "Testing database connectivity..."
if command -v psql &> /dev/null; then
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_PRIMARY_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
        log "✓ Primary database connectivity verified"
    else
        log "⚠ Primary database connectivity failed"
    fi
    
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_REPLICA_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
        log "✓ Replica database connectivity verified" 
    else
        log "⚠ Replica database connectivity failed"
    fi
else
    log "PostgreSQL client not available for connectivity testing"
fi

# Display final status
log "Next.js Web Application setup completed successfully!"
log "Application ready at: http://localhost:$PORT"
log "PM2 process: $APP_NAME"
log "Database connections: Primary=$DB_PRIMARY_HOST, Replica=$DB_REPLICA_HOST"
log "Health monitoring and log rotation configured"

# Display useful information
log "=== Deployment Summary ==="
log "Application Name: $APP_NAME"
log "Node.js Version: $(node --version 2>/dev/null || echo 'unknown')"
log "Application Port: $PORT"
log "Application Directory: $APP_DIR"
log "Log Directory: $LOG_DIR"
log "Health Check Script: $SCRIPT_DIR/webapp-health-check.sh"

# Display application information
log "=== Application Information ==="
log "Framework: Next.js (Full-stack)"
log "Process Manager: PM2"
log "Environment: Production"
log "Database Integration: PostgreSQL with failover"

# Show PM2 status
sudo -u $APP_USER pm2 list 2>/dev/null || log "PM2 status unavailable"

# Disable cloud-init to prevent network configuration conflicts on future boots
log "Disabling cloud-init to prevent network configuration issues..."
touch /etc/cloud/cloud-init.disabled 2>/dev/null || log "Warning: Could not disable cloud-init"

# Ensure all background processes complete and file handles are closed
log "Finalizing deployment and closing all processes..."
sync  # Force filesystem sync

# Final completion signal
echo "DEPLOYMENT_COMPLETE: $(date)" >> "$FULL_OUTPUT_LOG"
log "Setup completed successfully. Web application deployment finished."

# ==============================================================================
# RE-ENABLE AUTOMATIC UPDATES
# ==============================================================================
log "Re-enabling automatic updates and apt-daily services..."

# Re-enable apt-daily services
systemctl enable apt-daily.timer 2>/dev/null || log "apt-daily.timer not available to enable"
systemctl enable apt-daily-upgrade.timer 2>/dev/null || log "apt-daily-upgrade.timer not available to enable"
systemctl start apt-daily.timer 2>/dev/null || log "apt-daily.timer not available to start"
systemctl start apt-daily-upgrade.timer 2>/dev/null || log "apt-daily-upgrade.timer not available to start"

# Re-enable unattended-upgrades
systemctl enable unattended-upgrades 2>/dev/null || log "unattended-upgrades not available to enable"
systemctl start unattended-upgrades 2>/dev/null || log "unattended-upgrades not available to start"

log "Automatic updates and services re-enabled"
log "Web application deployment fully completed"

exit 0