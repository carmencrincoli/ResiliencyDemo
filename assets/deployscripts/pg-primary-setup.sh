#!/bin/bash
# PostgreSQL Primary Database Setup Script - Azure Local E-commerce Application
# Downloads and deploys PostgreSQL configuration from compressed archives
# This script will be executed via Azure Custom Script Extension

set -e

# Variables and Configuration
FULL_OUTPUT_LOG="/var/log/deploy.log"
SCRIPT_DIR="/opt/ecommerce"
TEMP_DIR="/tmp/database-deployment"
POSTGRES_VERSION="16"

# Database configuration from environment variables
DB_NAME="${DB_NAME:-ecommerce}"
DB_USER="${DB_USER:-ecommerce_user}"
DB_PASSWORD="${DB_PASSWORD:-}"
REPLICATION_USER="replicator"
REPLICATION_PASSWORD="${DB_PASSWORD:-}"

# Storage URL - this will be replaced by the actual storage account URL during deployment
STORAGE_BASE_URL="${STORAGE_ACCOUNT_URL:-}"
DATABASE_ARCHIVE_URL="${STORAGE_BASE_URL}assets/database.tar.gz"

# Dump exports to log file for potential reuse
EXPORT_LOG="/var/log/exports.log"
echo "# PostgreSQL Primary Setup - Environment Variables Export" > "$EXPORT_LOG"
echo "# Generated on $(date)" >> "$EXPORT_LOG"
echo "# This section contains only the environment variables passed from the Bicep template" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "export DB_NAME=\"$DB_NAME\"" >> "$EXPORT_LOG"
echo "export DB_USER=\"$DB_USER\"" >> "$EXPORT_LOG"
echo "export DB_PASSWORD=\"$DB_PASSWORD\"" >> "$EXPORT_LOG"
echo "export DB_PORT=\"$DB_PORT\"" >> "$EXPORT_LOG"
echo "export REPLICA_IP=\"$REPLICA_IP\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_URL=\"$STORAGE_ACCOUNT_URL\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_NAME=\"$STORAGE_ACCOUNT_NAME\"" >> "$EXPORT_LOG"
echo "export STORAGE_ACCOUNT_KEY=\"$STORAGE_ACCOUNT_KEY\"" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "# End of exports" >> "$EXPORT_LOG"

# Redirect all output to both log file and console using tee
exec > >(tee -a "$FULL_OUTPUT_LOG") 2>&1

set -e

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PG-PRIMARY-SETUP] $1"
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

log "Starting PostgreSQL Primary Database setup..."
log "Using storage URL: $STORAGE_BASE_URL"
log "Database: $DB_NAME, User: $DB_USER"

# Validate required environment variables
if [ -z "$DB_PASSWORD" ]; then
    handle_error "DB_PASSWORD environment variable is required"
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

# Install PostgreSQL
log "Installing PostgreSQL $POSTGRES_VERSION..."
apt-get -o DPkg::Lock::Timeout=600 install -y wget ca-certificates gnupg || handle_error "Failed to install prerequisites"

# Add PostgreSQL official APT repository
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg || handle_error "Failed to add PostgreSQL GPG key"
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list || handle_error "Failed to add PostgreSQL repository"

# Configure debconf for non-interactive installation (only set selections that exist)
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

apt-get -o DPkg::Lock::Timeout=600 update || handle_error "Failed to update package lists after adding PostgreSQL repo"

apt-get -o DPkg::Lock::Timeout=600 install -y postgresql-$POSTGRES_VERSION postgresql-contrib-$POSTGRES_VERSION postgresql-client-$POSTGRES_VERSION postgresql-server-dev-$POSTGRES_VERSION || handle_error "Failed to install PostgreSQL"

# Install additional packages that might be needed
apt-get -o DPkg::Lock::Timeout=600 install -y postgresql-plpython3-$POSTGRES_VERSION postgresql-$POSTGRES_VERSION-postgis-3 2>/dev/null || log "Optional PostgreSQL extensions not available"

# Create application directories
log "Creating application directories..."
mkdir -p "$SCRIPT_DIR" || handle_error "Failed to create script directory"
mkdir -p "$SCRIPT_DIR/backups" || handle_error "Failed to create backups directory"
mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION/main/archive" || handle_error "Failed to create archive directory"

# Download and extract database configuration archive
log "Downloading database configuration archive..."
if [ -n "$STORAGE_BASE_URL" ]; then
    log "Downloading from: $DATABASE_ARCHIVE_URL"
    # Parse storage account name from URL
    STORAGE_ACCOUNT=$(echo "$STORAGE_BASE_URL" | sed -n 's/.*\/\/\([^.]*\).*/\1/p')
    CONTAINER_NAME="assets"
    BLOB_NAME="database.tar.gz"
    
    log "Storage Account: $STORAGE_ACCOUNT, Container: $CONTAINER_NAME, Blob: $BLOB_NAME"
    az storage blob download \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER_NAME" \
        --name "$BLOB_NAME" \
        --file "database.tar.gz" \
        --account-key "$STORAGE_ACCOUNT_KEY" || handle_error "Failed to download database archive"
    
    # Verify archive was downloaded
    if [ ! -f "database.tar.gz" ]; then
        handle_error "Database archive not found after download"
    fi
    
    # Get archive size for verification
    archive_size=$(stat -c%s "database.tar.gz")
    log "Downloaded archive size: $archive_size bytes"
    
    # Extract archive to temporary directory
    log "Extracting database configuration..."
    tar -xzf database.tar.gz -C "$TEMP_DIR" || handle_error "Failed to extract database archive"
    
    # Verify extraction
    if [ ! -f "postgresql.conf" ]; then
        handle_error "PostgreSQL configuration not found after extraction"
    fi
    
    log "Database configuration extracted successfully"
else
    handle_error "Storage account URL not provided"
fi

# Stop PostgreSQL service for configuration
log "Stopping PostgreSQL for configuration..."
systemctl stop postgresql 2>/dev/null || log "PostgreSQL service not running"

# Completely remove all cluster metadata and data
log "Performing complete PostgreSQL cluster cleanup..."
pg_dropcluster --stop-server $POSTGRES_VERSION main 2>/dev/null || log "No cluster to drop"

# Remove all PostgreSQL cluster configuration and metadata
rm -rf "/etc/postgresql/$POSTGRES_VERSION" 2>/dev/null || log "No configuration directory to remove"
rm -rf "/var/lib/postgresql/$POSTGRES_VERSION" 2>/dev/null || log "No data directory to remove"
rm -rf "/var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log" 2>/dev/null || log "No log file to remove"

# Clear any cluster registry entries
if [ -f "/etc/postgresql-common/createcluster.d/50-remove_datadirectory.sh" ]; then
    rm -f "/etc/postgresql-common/createcluster.d/50-remove_datadirectory.sh" 2>/dev/null || log "No createcluster config to remove"
fi

# Ensure PostgreSQL user exists
id postgres >/dev/null 2>&1 || useradd -r -s /bin/bash postgres

# Create fresh directory structure
log "Creating fresh PostgreSQL directory structure..."
mkdir -p "/etc/postgresql/$POSTGRES_VERSION/main"
mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION/main"
mkdir -p "/var/log/postgresql"

# Set proper ownership
chown -R postgres:postgres "/etc/postgresql/$POSTGRES_VERSION"
chown -R postgres:postgres "/var/lib/postgresql/$POSTGRES_VERSION"
chown postgres:postgres "/var/log/postgresql"

# Create the cluster with basic settings
log "Creating new PostgreSQL cluster..."
# First, try to create cluster normally
if pg_createcluster --start-conf=auto --port=5432 $POSTGRES_VERSION main; then
    log "PostgreSQL cluster created successfully"
else
    log "Standard cluster creation failed, attempting manual initialization..."
    
    # Ensure data directory exists and has correct ownership
    DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
    mkdir -p "$DATA_DIR"
    chown -R postgres:postgres "$DATA_DIR"
    chmod 700 "$DATA_DIR"
    
    # Initialize database cluster manually
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/initdb -D "$DATA_DIR" --auth-local=peer --auth-host=scram-sha-256 --locale=en_US.UTF-8 --encoding=UTF8 || handle_error "Failed to initialize database cluster manually"
    
    # Create minimal configuration files
    cat > "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" << EOF
# Minimal PostgreSQL configuration for initial startup
data_directory = '$DATA_DIR'
hba_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf'
ident_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf'
external_pid_file = '/var/run/postgresql/$POSTGRES_VERSION-main.pid'
port = 5432
max_connections = 100
shared_buffers = 128MB
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 10MB
EOF
    
    # Create basic pg_hba.conf
    cat > "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" << EOF
# Basic authentication configuration
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
EOF
    
    # Set proper ownership
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"
    chmod 640 "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"
    
    log "Manual cluster initialization completed"
fi

# Verify cluster was created and get status
log "Verifying PostgreSQL cluster..."
if pg_lsclusters 2>/dev/null | grep -q "$POSTGRES_VERSION.*main"; then
    log "PostgreSQL cluster verified successfully"
else
    log "Cluster verification failed, but continuing with configuration..."
fi

# Backup original configuration files (if they exist)
log "Backing up original configuration files..."
cp "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf.backup" 2>/dev/null || log "No existing postgresql.conf to backup"
cp "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf.backup" 2>/dev/null || log "No existing pg_hba.conf to backup"

# Install PostgreSQL configuration from archive
log "Installing PostgreSQL configuration from archive..."
if [ -f "postgresql.conf" ]; then
    # Process postgresql.conf with environment variable substitution if needed
    sed \
        -e "s/POSTGRES_VERSION_PLACEHOLDER/$POSTGRES_VERSION/g" \
        postgresql.conf > "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to install postgresql.conf"
    
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to set ownership on postgresql.conf"
    chmod 644 "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to set permissions on postgresql.conf"
    log "PostgreSQL configuration installed successfully"
else
    log "⚠ postgresql.conf not found in extracted archive, using default configuration"
fi

# Install pg_hba.conf from archive
if [ -f "pg_hba.conf" ]; then
    cp "pg_hba.conf" "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to install pg_hba.conf"
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to set ownership on pg_hba.conf"
    chmod 640 "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to set permissions on pg_hba.conf"
    log "pg_hba.conf installed successfully"
else
    log "⚠ pg_hba.conf not found in extracted archive, using default configuration"
fi

# Ensure archive directory exists with proper permissions
mkdir -p "/var/lib/postgresql/$POSTGRES_VERSION/main/archive"
chown -R postgres:postgres "/var/lib/postgresql/$POSTGRES_VERSION/main/archive" || handle_error "Failed to set archive directory ownership"
chmod 750 "/var/lib/postgresql/$POSTGRES_VERSION/main/archive" || handle_error "Failed to set archive directory permissions"

# Generate SSL certificates if not present (for production)
if [ ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
    log "Generating SSL certificates for PostgreSQL..."
    make-ssl-cert generate-default-snakeoil --force-overwrite
fi

# Set proper SSL certificate permissions
chmod 644 /etc/ssl/certs/ssl-cert-snakeoil.pem
chmod 600 /etc/ssl/private/ssl-cert-snakeoil.key
chown postgres:postgres /etc/ssl/private/ssl-cert-snakeoil.key

# Start PostgreSQL service
log "Starting PostgreSQL service..."

# Display cluster information for debugging
log "Current cluster information:"
pg_lsclusters || log "Failed to list clusters"

# Try to start the cluster using cluster management first
log "Starting PostgreSQL cluster $POSTGRES_VERSION/main..."
if pg_ctlcluster $POSTGRES_VERSION main start 2>/dev/null; then
    log "✓ Cluster started successfully with pg_ctlcluster"
else
    log "pg_ctlcluster failed, trying direct PostgreSQL startup..."
    # If cluster management fails, try direct startup
    sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_ctl -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -l "/var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log" start || handle_error "Failed to start PostgreSQL"
fi

# Enable PostgreSQL service for system startup
systemctl enable postgresql || handle_error "Failed to enable PostgreSQL service"

# Wait for PostgreSQL to be ready
log "Waiting for PostgreSQL to be ready..."
sleep 15

# Check if PostgreSQL cluster is running with detailed verification
log "Verifying PostgreSQL cluster status..."
if pg_lsclusters 2>/dev/null | grep -q "$POSTGRES_VERSION.*main.*online" || sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/pg_isready -d postgres; then
    log "✓ PostgreSQL cluster is online and accepting connections"
    
    # Now enable archiving since cluster is stable
    log "Enabling WAL archiving..."
    sudo -u postgres psql -c "ALTER SYSTEM SET archive_mode = on;" || log "Failed to enable archive mode"
    sudo -u postgres psql -c "ALTER SYSTEM SET archive_command = 'cp %p /var/lib/postgresql/$POSTGRES_VERSION/main/archive/%f';" || log "Failed to set archive command"
    
    # Reload configuration
    sudo -u postgres psql -c "SELECT pg_reload_conf();" || log "Failed to reload configuration"
    log "WAL archiving enabled successfully"
else
    log "Cluster status details:"
    pg_lsclusters 2>/dev/null || log "pg_lsclusters not available"
    log "PostgreSQL service status:"
    systemctl status postgresql --no-pager --lines=10 || log "systemctl status not available"
    log "PostgreSQL logs:"
    tail -20 /var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log 2>/dev/null || log "No PostgreSQL logs available"
    log "Process status:"
    ps aux | grep postgres || log "No postgres processes found"
    handle_error "PostgreSQL cluster failed to start properly"
fi

# Create database and users
log "Creating database and users..."
if [ -f "database-schema.sql" ]; then
    # Process database schema with environment variables
    sed \
        -e "s/ecommerce_user/$DB_USER/g" \
        -e "s/SERVICE_PASSWORD_PLACEHOLDER/$DB_PASSWORD/g" \
        -e "s/ecommerce/$DB_NAME/g" \
        database-schema.sql > processed-schema.sql || handle_error "Failed to process database schema"
    
    # Execute database schema
    sudo -u postgres psql -f processed-schema.sql || handle_error "Failed to execute database schema"
    
    # Create pg_stat_statements extension for performance monitoring
    sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;" || log "pg_stat_statements extension may already exist"
    
    log "Database schema applied successfully"
else
    handle_error "database-schema.sql not found in extracted archive"
fi

# Configure firewall with improved security
log "Configuring firewall with security hardening..."
ufw --force enable || log "UFW already enabled"
ufw default deny incoming || log "Default deny already set"
ufw default allow outgoing || log "Default allow outgoing already set"
ufw allow 22/tcp comment 'SSH' || log "SSH port already allowed"
ufw allow 5432/tcp comment 'PostgreSQL' || log "PostgreSQL port already allowed"

# Limit SSH connections to prevent brute force
ufw limit 22/tcp || log "SSH rate limiting already configured"

# Install backup script from archive
log "Installing backup script..."
if [ -f "backup-db.sh" ]; then
    cp "backup-db.sh" "$SCRIPT_DIR/backup-db.sh" || handle_error "Failed to copy backup script"
    chmod +x "$SCRIPT_DIR/backup-db.sh" || handle_error "Failed to make backup script executable"
    
    # Set environment variables in backup script
    sed -i "s/\${DB_NAME:-ecommerce}/$DB_NAME/g" "$SCRIPT_DIR/backup-db.sh" || log "DB_NAME substitution in backup script"
    log "Backup script installed from archive"
else
    handle_error "backup-db.sh not found in extracted archive"
fi

# Install monitoring script from archive
log "Installing monitoring script..."
if [ -f "monitor-db.sh" ]; then
    cp "monitor-db.sh" "$SCRIPT_DIR/monitor-db.sh" || handle_error "Failed to copy monitoring script"
    chmod +x "$SCRIPT_DIR/monitor-db.sh" || handle_error "Failed to make monitoring script executable"
    
    # Set environment variables in monitoring script
    sed -i "s/\${DB_NAME:-ecommerce}/$DB_NAME/g" "$SCRIPT_DIR/monitor-db.sh" || log "DB_NAME substitution in monitoring script"
    log "Monitoring script installed from archive"
else
    handle_error "monitor-db.sh not found in extracted archive"
fi

# Set up log rotation configuration
log "Setting up log rotation..."
if [ -f "logrotate.conf" ]; then
    cp "logrotate.conf" "/etc/logrotate.d/ecommerce-database" || handle_error "Failed to copy logrotate configuration"
    chmod 644 "/etc/logrotate.d/ecommerce-database" || handle_error "Failed to set logrotate permissions"
    log "Log rotation configuration installed from archive"
else
    handle_error "logrotate.conf not found in extracted archive"
fi

# Test log rotation
logrotate -t /etc/logrotate.d/ecommerce-database || log "Log rotation test completed with warnings"

# Set up cron jobs for backup and monitoring
log "Setting up cron jobs..."
(crontab -l 2>/dev/null; echo "0 2 * * * $SCRIPT_DIR/backup-db.sh >> /var/log/db-backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/monitor-db.sh") | crontab -

# Final verification and status
log "Performing final verification..."

# Test database connectivity
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log "✓ Database connectivity test passed"
else
    handle_error "Database connectivity test failed"
fi

# Test application user connection
if sudo -u postgres psql -d "$DB_NAME" -U "$DB_USER" -c "SELECT 1;" > /dev/null 2>&1; then
    log "✓ Application user connection test passed"
else
    log "⚠ Application user connection test failed - may need password authentication"
fi

# Check replication user
if sudo -u postgres psql -c "SELECT 1 FROM pg_roles WHERE rolname='$REPLICATION_USER';" | grep -q "1"; then
    log "✓ Replication user created successfully"
else
    log "⚠ Replication user creation failed"
fi

# Display final status
log "PostgreSQL Primary Database setup completed successfully!"
log "PostgreSQL Primary ready - Database: $DB_NAME, User: $DB_USER"
log "Replication configured for user: $REPLICATION_USER"
log "Backup and monitoring scripts installed"
log "Configuration files extracted from archive"

# Display useful information
log "=== Deployment Summary ==="
log "PostgreSQL Version: $POSTGRES_VERSION"
log "Database Name: $DB_NAME"
log "Application User: $DB_USER"
log "Replication User: $REPLICATION_USER"
log "Configuration: /etc/postgresql/$POSTGRES_VERSION/main/"
log "Data Directory: /var/lib/postgresql/$POSTGRES_VERSION/main/"
log "Archive Directory: /var/lib/postgresql/$POSTGRES_VERSION/main/archive/"
log "Backup Script: $SCRIPT_DIR/backup-db.sh"
log "Monitor Script: $SCRIPT_DIR/monitor-db.sh"
log "Backup Directory: $SCRIPT_DIR/backups"

# Display connection information
log "=== Connection Information ==="
log "Local Connection: psql -d $DB_NAME -U $DB_USER"
log "Network Connection: psql -h $(hostname -I | awk '{print $1}') -d $DB_NAME -U $DB_USER"
log "Replication Connection: psql -h $(hostname -I | awk '{print $1}') -U $REPLICATION_USER"

# Show PostgreSQL status
systemctl status postgresql --no-pager --lines=5 || log "PostgreSQL status unavailable"

# Display table count
TABLE_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
if [ -n "$TABLE_COUNT" ]; then
    log "Database tables created: $TABLE_COUNT"
fi

# Display product count
PRODUCT_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT count(*) FROM products;" 2>/dev/null | tr -d ' ')
if [ -n "$PRODUCT_COUNT" ]; then
    log "Sample products inserted: $PRODUCT_COUNT"
fi

# Disable cloud-init to prevent network configuration conflicts on future boots
log "Disabling cloud-init to prevent network configuration issues..."
touch /etc/cloud/cloud-init.disabled 2>/dev/null || log "Warning: Could not disable cloud-init"

# Ensure all background processes complete and file handles are closed
log "Finalizing deployment and closing all processes..."
sync  # Force filesystem sync

# Final completion signal
echo "DEPLOYMENT_COMPLETE: $(date)" >> "$FULL_OUTPUT_LOG"
log "Setup completed successfully. PostgreSQL Primary deployment finished."

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
log "PostgreSQL Primary deployment fully completed"

exit 0