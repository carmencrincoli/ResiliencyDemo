#!/bin/bash
# PostgreSQL Replica Database Setup Script - Azure Local E-commerce Application
# Downloads and deploys PostgreSQL replica configuration from compressed archives
# This script will be executed via Azure Custom Script Extension

# Variables and Configuration
FULL_OUTPUT_LOG="/var/log/deploy.log"
SCRIPT_DIR="/opt/ecommerce"
TEMP_DIR="/tmp/database-replica-deployment"
POSTGRES_VERSION="16"

# Replica configuration from environment variables
PRIMARY_HOST="${PRIMARY_IP:-}"
REPLICATION_USER="replicator"
REPLICATION_PASSWORD="${DB_PASSWORD:-}"

# Storage URL - this will be replaced by the actual storage account URL during deployment
STORAGE_BASE_URL="${STORAGE_ACCOUNT_URL:-}"
DATABASE_ARCHIVE_URL="${STORAGE_BASE_URL}assets/database.tar.gz"

# Dump exports to log file for potential reuse
EXPORT_LOG="/var/log/exports.log"
echo "# PostgreSQL Replica Setup - Environment Variables Export" > "$EXPORT_LOG"
echo "# Generated on $(date)" >> "$EXPORT_LOG"
echo "# This section contains only the environment variables passed from the Bicep template" >> "$EXPORT_LOG"
echo "" >> "$EXPORT_LOG"
echo "export DB_NAME=\"$DB_NAME\"" >> "$EXPORT_LOG"
echo "export DB_USER=\"$DB_USER\"" >> "$EXPORT_LOG"
echo "export DB_PASSWORD=\"$DB_PASSWORD\"" >> "$EXPORT_LOG"
echo "export DB_PORT=\"$DB_PORT\"" >> "$EXPORT_LOG"
echo "export PRIMARY_IP=\"$PRIMARY_IP\"" >> "$EXPORT_LOG"
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') [PG-REPLICA-SETUP] $1"
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

log "Starting PostgreSQL Replica Database setup..."
log "Using storage URL: $STORAGE_BASE_URL"
log "Primary host: $PRIMARY_HOST"

# Validate required environment variables
if [ -z "$PRIMARY_HOST" ]; then
    handle_error "PRIMARY_IP environment variable is required"
fi

if [ -z "$REPLICATION_PASSWORD" ]; then
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
apt-get -o DPkg::Lock::Timeout=600 install -y wget ca-certificates gnupg bc || handle_error "Failed to install prerequisites"

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
    tar -xzf database.tar.gz || handle_error "Failed to extract database archive"
    
    # Verify extraction
    if [ ! -f "postgresql-replica.conf" ]; then
        handle_error "PostgreSQL replica configuration not found after extraction"
    fi
    
    log "Database configuration extracted successfully"
else
    handle_error "Storage account URL not provided"
fi

# Stop PostgreSQL service for configuration
log "Stopping PostgreSQL for configuration..."
systemctl stop postgresql || handle_error "Failed to stop PostgreSQL"

# Check if cluster exists and remove it for replica setup
log "Preparing PostgreSQL cluster for replica setup..."
if pg_lsclusters | grep -q "$POSTGRES_VERSION.*main"; then
    log "Removing existing PostgreSQL cluster for replica setup..."
    pg_dropcluster --stop-server $POSTGRES_VERSION main 2>/dev/null || log "Failed to drop existing cluster"
fi

# Ensure data directory is completely clean
DATA_DIR="/var/lib/postgresql/$POSTGRES_VERSION/main"
if [ -d "$DATA_DIR" ]; then
    log "Removing existing data directory: $DATA_DIR"
    rm -rf "$DATA_DIR"
fi

# Create data directory with proper permissions
log "Creating clean data directory..."
mkdir -p "$DATA_DIR"
chown postgres:postgres "$DATA_DIR"
chmod 700 "$DATA_DIR"

# Create .pgpass file for replication user
log "Setting up replication credentials..."
echo "$PRIMARY_HOST:5432:*:$REPLICATION_USER:$REPLICATION_PASSWORD" > /var/lib/postgresql/.pgpass || handle_error "Failed to create .pgpass file"
chown postgres:postgres /var/lib/postgresql/.pgpass || handle_error "Failed to set .pgpass ownership"
chmod 600 /var/lib/postgresql/.pgpass || handle_error "Failed to set .pgpass permissions"

# Function to test if primary is fully ready for replication
test_primary_ready() {
    local host="$1"
    
    # Step 1: Basic connectivity
    if ! pg_isready -h "$host" -p 5432 >/dev/null 2>&1; then
        return 1
    fi
    
    # Step 2: Test replication user exists and can connect
    if ! PGPASSWORD="$REPLICATION_PASSWORD" psql -h "$host" -p 5432 -U "$REPLICATION_USER" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
        return 1
    fi
    
    # Step 3: Test replication user has proper privileges (check if user has REPLICATION role)
    if ! PGPASSWORD="$REPLICATION_PASSWORD" psql -h "$host" -p 5432 -U "$REPLICATION_USER" -d postgres -c "SELECT rolreplication FROM pg_roles WHERE rolname = '$REPLICATION_USER';" -t | grep -q "t" >/dev/null 2>&1; then
        return 1
    fi
    
    # Step 4: Verify ecommerce database exists (indicates schema is loaded)
    if ! PGPASSWORD="$REPLICATION_PASSWORD" psql -h "$host" -p 5432 -U "$REPLICATION_USER" -d ecommerce -c "SELECT 1;" >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Test connection to primary server with retry logic
log "Testing if primary server is fully ready for replication..."
RETRY_TIMEOUT=1800  # 30 minutes in seconds
RETRY_INTERVAL=60   # Retry every 60 seconds
START_TIME=$(date +%s)

while true; do
    if test_primary_ready "$PRIMARY_HOST"; then
        log "✓ Primary server is fully ready for replication at $PRIMARY_HOST:5432"
        break
    fi
    
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED_TIME -ge $RETRY_TIMEOUT ]; then
        handle_error "Timeout: Primary server at $PRIMARY_HOST:5432 not ready for replication after 30 minutes"
    fi
    
    REMAINING_TIME=$((RETRY_TIMEOUT - ELAPSED_TIME))
    log "⚠ Primary server not ready for replication. Retrying in ${RETRY_INTERVAL} seconds (${REMAINING_TIME}s remaining)..."
    sleep $RETRY_INTERVAL
done

# Create base backup from primary
log "Creating base backup from primary server..."
cd /tmp
if ! sudo -u postgres pg_basebackup -h "$PRIMARY_HOST" -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -U "$REPLICATION_USER" --no-password --wal-method=stream; then
    handle_error "Failed to create base backup from primary server"
fi

# Return to temp directory for configuration file access
cd "$TEMP_DIR"

# Create standby signal file
touch "/var/lib/postgresql/$POSTGRES_VERSION/main/standby.signal" || handle_error "Failed to create standby.signal file"

log "Configuring replica settings..."

# Set ownership of data directory and all contents
log "Setting proper ownership of data directory..."
chown -R postgres:postgres "/var/lib/postgresql/$POSTGRES_VERSION/main" || handle_error "Failed to set data directory ownership"
chmod 700 "/var/lib/postgresql/$POSTGRES_VERSION/main" || handle_error "Failed to set data directory permissions"

# Ensure proper permissions on key files
chmod 600 "/var/lib/postgresql/$POSTGRES_VERSION/main/standby.signal" 2>/dev/null || log "standby.signal permissions set"

# Ensure socket directory exists with proper permissions
log "Setting up socket directory permissions..."
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql
chmod 755 /var/run/postgresql

# Generate SSL certificates if not present (for production)
if [ ! -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
    log "Generating SSL certificates for PostgreSQL replica..."
    make-ssl-cert generate-default-snakeoil --force-overwrite
fi

# Set proper SSL certificate permissions
chmod 644 /etc/ssl/certs/ssl-cert-snakeoil.pem
chmod 600 /etc/ssl/private/ssl-cert-snakeoil.key
chown postgres:postgres /etc/ssl/private/ssl-cert-snakeoil.key

# Ensure configuration directory exists
log "Ensuring PostgreSQL configuration directory exists..."
mkdir -p "/etc/postgresql/$POSTGRES_VERSION/main"
chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main"
chmod 755 "/etc/postgresql/$POSTGRES_VERSION/main"

# Create minimal pg_hba.conf and postgresql.conf in /etc for pg_createcluster
log "Creating minimal configuration files for cluster registration..."
cat > "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" << EOF
# Minimal configuration for cluster registration and replica startup
data_directory = '/var/lib/postgresql/$POSTGRES_VERSION/main'
hba_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf'
ident_file = '/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf'
external_pid_file = '/var/run/postgresql/$POSTGRES_VERSION-main.pid'
unix_socket_directories = '/var/run/postgresql'
port = 5432
max_connections = 100
shared_buffers = 128MB
hot_standby = on
listen_addresses = '*'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
EOF

cat > "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" << EOF
# Minimal pg_hba.conf for cluster registration
local   all             postgres                                peer
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF

# Set proper ownership and permissions
chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"
chmod 644 "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"
chmod 640 "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf"

# Skip pg_createcluster since we have data from pg_basebackup
# The data directory already contains a properly configured PostgreSQL instance
log "Skipping cluster creation - using data from pg_basebackup..."

# Backup original configuration files
log "Backing up original minimal configuration files..."
cp "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf.backup" 2>/dev/null || log "No existing postgresql.conf to backup"
cp "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf.backup" 2>/dev/null || log "No existing pg_hba.conf to backup"

# Install PostgreSQL replica configuration from archive
log "Installing PostgreSQL replica configuration from archive..."
if [ -f "postgresql-replica.conf" ]; then
    # First, process the replica config with environment variables AND add connection settings
    log "Processing replica configuration and adding connection settings..."
    
    # Start with the base replica config, substitute variables
    sed -e "s/POSTGRES_VERSION_PLACEHOLDER/$POSTGRES_VERSION/g" postgresql-replica.conf > temp-replica.conf
    
    # Add the replica-specific connection settings to the end of the config
    cat >> temp-replica.conf << EOF

# Replica connection settings - added dynamically
primary_conninfo = 'host=$PRIMARY_HOST port=5432 user=$REPLICATION_USER password=$REPLICATION_PASSWORD application_name=replica_$(hostname)'
restore_command = ''
primary_slot_name = ''

# Additional replica tuning
wal_receiver_status_interval = 10s
wal_retrieve_retry_interval = 5s
recovery_min_apply_delay = 0
EOF
    
    # Copy the enhanced configuration to /etc directory where PostgreSQL expects it
    cp temp-replica.conf "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to install postgresql.conf to etc directory"
    
    # Clean up temp file
    rm -f temp-replica.conf
    
    # Set proper ownership and permissions
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to set ownership on postgresql.conf"
    chmod 644 "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || handle_error "Failed to set permissions on postgresql.conf"
    
    log "PostgreSQL replica configuration installed successfully to /etc directory"
    
    # Log key settings for debugging (check /etc directory version since that's what PostgreSQL uses)
    log "Key replica settings from postgresql.conf (/etc directory):"
    grep -E "^(hot_standby|wal_level|max_wal_senders|listen_addresses|port|primary_conninfo)" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || log "Some settings not found in config"
    
    # Also show the actual primary_conninfo line for verification
    log "Primary connection configuration:"
    grep "primary_conninfo" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" || log "primary_conninfo not found"
else
    handle_error "postgresql-replica.conf not found in extracted archive"
fi

# Install pg_hba.conf for replica from archive
if [ -f "pg_hba-replica.conf" ]; then
    # Install to /etc directory where PostgreSQL expects it based on hba_file configuration
    cp "pg_hba-replica.conf" "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to install pg_hba.conf to etc directory"
    
    # Set proper ownership and permissions
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to set ownership on pg_hba.conf"
    chmod 640 "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" || handle_error "Failed to set permissions on pg_hba.conf"
    
    log "pg_hba.conf for replica installed successfully to /etc directory"
else
    handle_error "pg_hba-replica.conf not found in extracted archive"
fi

# Install pg_ident.conf for replica from archive
if [ -f "pg_ident-replica.conf" ]; then
    # Install to /etc directory where PostgreSQL expects it based on ident_file configuration
    cp "pg_ident-replica.conf" "/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf" || handle_error "Failed to install pg_ident.conf to etc directory"
    
    # Set proper ownership and permissions
    chown postgres:postgres "/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf" || handle_error "Failed to set ownership on pg_ident.conf"
    chmod 640 "/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf" || handle_error "Failed to set permissions on pg_ident.conf"
    
    log "pg_ident.conf for replica installed successfully to /etc directory"
else
    handle_error "pg_ident-replica.conf not found in extracted archive"
fi

# Start PostgreSQL replica service
log "Starting PostgreSQL replica service..."

# Verify all required files exist before starting
log "Verifying replica configuration files..."
if [ ! -f "/var/lib/postgresql/$POSTGRES_VERSION/main/standby.signal" ]; then
    handle_error "standby.signal file missing"
fi

if [ ! -f "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" ]; then
    handle_error "postgresql.conf file missing from /etc directory"
fi

# Verify the postgresql.conf contains replica connection settings (check /etc directory version)
if ! grep -q "primary_conninfo" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf"; then
    handle_error "primary_conninfo not found in /etc directory postgresql.conf"
fi

# Verify pg_ident.conf exists
if [ ! -f "/etc/postgresql/$POSTGRES_VERSION/main/pg_ident.conf" ]; then
    handle_error "pg_ident.conf file missing from /etc directory"
fi

log "All configuration files verified, attempting to start..."

# For Ubuntu with pg_ctlcluster, we need to start the specific cluster, not the service
log "Starting PostgreSQL cluster $POSTGRES_VERSION/main directly..."
if pg_ctlcluster $POSTGRES_VERSION main start 2>&1; then
    log "✓ PostgreSQL cluster started successfully"
else
    log "pg_ctlcluster failed, checking if cluster is registered..."
    
    # Display cluster information for debugging
    log "Current cluster information:"
    pg_lsclusters || log "Failed to list clusters"
    
    # Check if cluster needs to be registered first
    if ! pg_lsclusters | grep -q "$POSTGRES_VERSION.*main"; then
        log "Cluster not registered, registering now..."
        if pg_createcluster $POSTGRES_VERSION main --datadir="/var/lib/postgresql/$POSTGRES_VERSION/main"; then
            log "Cluster registered successfully, attempting to start..."
            if ! pg_ctlcluster $POSTGRES_VERSION main start; then
                log "Failed to start after registration, checking logs..."
                tail -50 /var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log 2>/dev/null || log "No PostgreSQL logs available"
                handle_error "Failed to start PostgreSQL cluster after registration"
            fi
        else
            handle_error "Failed to register PostgreSQL cluster"
        fi
    else
        log "Cluster is registered but won't start, checking logs..."
        log "Cluster status:"
        pg_lsclusters || log "Failed to list clusters"
        
        log "Configuration file check:"
        log "standby.signal exists: $([ -f "/var/lib/postgresql/$POSTGRES_VERSION/main/standby.signal" ] && echo "YES" || echo "NO")"
        log "postgresql.conf exists: $([ -f "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" ] && echo "YES" || echo "NO")"
        
        if [ -f "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" ]; then
            log "Key postgresql.conf settings:"
            grep -E "^(primary_conninfo|hot_standby|wal_level)" "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" | head -10
        fi
        
        log "PostgreSQL logs:"
        tail -50 /var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log 2>/dev/null || log "No PostgreSQL logs available"
        
        # Also check for logs in the data directory (where logging_collector writes them)
        log "Checking data directory logs..."
        if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main/log" ]; then
            log "Found log directory in data directory, checking latest logs:"
            find "/var/lib/postgresql/$POSTGRES_VERSION/main/log" -name "postgresql-*.log" -type f -exec ls -la {} \; 2>/dev/null | head -5
            # Get the most recent log file
            LATEST_LOG=$(find "/var/lib/postgresql/$POSTGRES_VERSION/main/log" -name "postgresql-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
                log "Latest PostgreSQL log content from: $LATEST_LOG"
                tail -50 "$LATEST_LOG" 2>/dev/null || log "Cannot read latest log"
            else
                log "No recent PostgreSQL log files found in data directory"
            fi
        else
            log "No log directory found in data directory"
        fi
        
        log "Attempting configuration validation..."
        log "Testing key configuration parameters that PostgreSQL will use:"
        sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C data_directory 2>&1 || log "data_directory check failed"
        sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C hba_file 2>&1 || log "hba_file check failed"
        sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C hot_standby 2>&1 || log "hot_standby check failed"
        sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C primary_conninfo 2>&1 || log "primary_conninfo check failed"
        
        log "Verifying file existence for configured paths:"
        DATA_DIR_CONFIG=$(sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C data_directory 2>/dev/null)
        HBA_FILE_CONFIG=$(sudo -u postgres /usr/lib/postgresql/$POSTGRES_VERSION/bin/postgres -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -C hba_file 2>/dev/null)
        log "Configured data_directory: $DATA_DIR_CONFIG"
        log "Configured hba_file: $HBA_FILE_CONFIG"
        
        if [ -n "$HBA_FILE_CONFIG" ] && [ -f "$HBA_FILE_CONFIG" ]; then
            log "✓ hba_file exists at configured location"
            log "hba_file permissions: $(ls -la "$HBA_FILE_CONFIG" 2>/dev/null)"
        else
            log "❌ hba_file missing at configured location: $HBA_FILE_CONFIG"
        fi
        
        handle_error "Failed to start registered PostgreSQL cluster"
    fi
fi

# Enable the postgresql service for startup (after cluster is working)
systemctl enable postgresql || log "Warning: Failed to enable PostgreSQL service"

# Wait for replica to be ready
log "Waiting for PostgreSQL replica to be ready..."
sleep 10

# Additional check to ensure cluster is actually running
CLUSTER_STATUS=$(pg_lsclusters | grep "$POSTGRES_VERSION.*main" | awk '{print $4}' || echo "unknown")
log "Cluster status after startup: $CLUSTER_STATUS"

if [[ "$CLUSTER_STATUS" != *"online"* ]]; then
    log "Cluster is not online, checking PostgreSQL logs for startup errors..."
    if [ -f "/var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log" ]; then
        log "Recent PostgreSQL log entries:"
        tail -20 /var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log
    fi
    
    # Try to get more specific error information
    log "Attempting to start with verbose logging..."
    sudo -u postgres pg_ctl start -D "/var/lib/postgresql/$POSTGRES_VERSION/main" -l "/var/log/postgresql/manual-start.log" || log "Manual pg_ctl start failed"
    
    if [ -f "/var/log/postgresql/manual-start.log" ]; then
        log "Manual start log:"
        cat /var/log/postgresql/manual-start.log
    fi
    
    handle_error "PostgreSQL cluster failed to achieve online status: $CLUSTER_STATUS"
fi

# Verify systemd service status
if ! systemctl is-active --quiet postgresql; then
    log "PostgreSQL service not active, attempting to start it..."
    systemctl start postgresql || log "Warning: systemctl start failed, but cluster may be running"
fi

# Check if PostgreSQL cluster is running with detailed verification
log "Verifying PostgreSQL replica cluster status..."

# First check with pg_lsclusters
CLUSTER_STATUS=$(pg_lsclusters | grep "$POSTGRES_VERSION.*main" | awk '{print $4}' || echo "unknown")
log "Cluster status from pg_lsclusters: $CLUSTER_STATUS"

# Check systemctl status
SYSTEMD_STATUS=$(systemctl is-active postgresql 2>/dev/null || echo "inactive")
log "Systemd service status: $SYSTEMD_STATUS"

# Only proceed with connection test if cluster shows as online
if [[ "$CLUSTER_STATUS" == *"online"* ]]; then
    log "Cluster shows as online, testing local connection..."
    
    # Check if we can connect locally
    if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
        log "✓ Local PostgreSQL connection successful"
        
        # Check if in recovery mode (replica)
        RECOVERY_STATUS=$(sudo -u postgres psql -c "SELECT pg_is_in_recovery();" -t 2>/dev/null | tr -d ' ')
        if [ "$RECOVERY_STATUS" = "t" ]; then
            log "✓ Server is in recovery mode (replica) - startup successful!"
        else
            log "⚠ Server is not in recovery mode - may not be properly configured as replica"
        fi
    else
        log "❌ Cannot connect to PostgreSQL locally even though cluster shows online"
        log "This may indicate authentication or permission issues"
        handle_error "PostgreSQL connection failed despite cluster being online"
    fi
else
    log "❌ Cluster is not online (status: $CLUSTER_STATUS)"
    log "Detailed status information:"
    pg_lsclusters || log "pg_lsclusters failed"
    
    # Get the latest PostgreSQL logs
    log "Recent PostgreSQL logs:"
    if [ -f "/var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log" ]; then
        tail -30 /var/log/postgresql/postgresql-$POSTGRES_VERSION-main.log
    else
        log "No PostgreSQL log file found at expected location"
        find /var/log -name "*postgresql*" -type f 2>/dev/null | head -5 | while read logfile; do
            log "Found log file: $logfile"
            tail -10 "$logfile" 2>/dev/null || log "Cannot read $logfile"
        done
    fi
    
    # Also check data directory logs which may contain the real startup errors
    log "Checking data directory logs for startup errors..."
    if [ -d "/var/lib/postgresql/$POSTGRES_VERSION/main/log" ]; then
        log "Data directory log files:"
        find "/var/lib/postgresql/$POSTGRES_VERSION/main/log" -name "postgresql-*.log" -type f -exec ls -la {} \; 2>/dev/null | head -5
        # Get the most recent log file
        LATEST_LOG=$(find "/var/lib/postgresql/$POSTGRES_VERSION/main/log" -name "postgresql-*.log" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        if [ -n "$LATEST_LOG" ] && [ -f "$LATEST_LOG" ]; then
            log "Content from latest data directory log: $LATEST_LOG"
            tail -30 "$LATEST_LOG" 2>/dev/null || log "Cannot read latest data directory log"
        else
            log "No recent log files found in data directory"
        fi
    else
        log "No log directory in data directory"
    fi
    
    # Try to understand why the cluster won't start
    log "Checking configuration files..."
    if [ -f "/etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf" ]; then
        log "postgresql.conf exists: $(ls -la /etc/postgresql/$POSTGRES_VERSION/main/postgresql.conf)"
    else
        log "postgresql.conf is missing from /etc directory!"
    fi
    
    if [ -f "/etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf" ]; then
        log "pg_hba.conf exists and is readable: $(ls -la /etc/postgresql/$POSTGRES_VERSION/main/pg_hba.conf)"
    else
        log "pg_hba.conf is missing!"
    fi
    
    handle_error "PostgreSQL replica cluster failed to start properly - cluster status: $CLUSTER_STATUS"
fi

# Configure firewall with security hardening
log "Configuring firewall with security hardening..."
ufw --force enable || log "UFW already enabled"
ufw default deny incoming || log "Default deny already set"
ufw default allow outgoing || log "Default allow outgoing already set"
ufw allow 22/tcp comment 'SSH' || log "SSH port already allowed"
ufw allow 5432/tcp comment 'PostgreSQL Replica' || log "PostgreSQL port already allowed"

# Limit SSH connections to prevent brute force
ufw limit 22/tcp || log "SSH rate limiting already configured"

# Install replica monitoring script from archive
log "Installing replica monitoring script..."
if [ -f "monitor-replica.sh" ]; then
    cp "monitor-replica.sh" "$SCRIPT_DIR/monitor-replica.sh" || handle_error "Failed to copy monitoring script"
    chmod +x "$SCRIPT_DIR/monitor-replica.sh" || handle_error "Failed to make monitoring script executable"
    
    # Set environment variables in monitoring script
    sed -i "s/\${PRIMARY_IP:-}/$PRIMARY_HOST/g" "$SCRIPT_DIR/monitor-replica.sh" || log "PRIMARY_HOST substitution in monitoring script"
    log "Replica monitoring script installed from archive"
else
    handle_error "monitor-replica.sh not found in extracted archive"
fi

# Install failover script from archive
log "Installing failover script..."
if [ -f "promote-replica.sh" ]; then
    cp "promote-replica.sh" "$SCRIPT_DIR/promote-replica.sh" || handle_error "Failed to copy failover script"
    chmod +x "$SCRIPT_DIR/promote-replica.sh" || handle_error "Failed to make failover script executable"
    log "Failover script installed from archive"
else
    handle_error "promote-replica.sh not found in extracted archive"
fi

# Set up log rotation configuration
log "Setting up log rotation..."
if [ -f "logrotate-replica.conf" ]; then
    cp "logrotate-replica.conf" "/etc/logrotate.d/ecommerce-replica" || handle_error "Failed to copy logrotate configuration"
    chmod 644 "/etc/logrotate.d/ecommerce-replica" || handle_error "Failed to set logrotate permissions"
    log "Log rotation configuration installed from archive"
else
    handle_error "logrotate-replica.conf not found in extracted archive"
fi

# Test log rotation
logrotate -t /etc/logrotate.d/ecommerce-replica || log "Log rotation test completed with warnings"

# Set up cron job for monitoring
log "Setting up monitoring cron job..."
(crontab -l 2>/dev/null; echo "*/5 * * * * $SCRIPT_DIR/monitor-replica.sh") | crontab -

# Final verification and status
log "Performing final verification and collecting replication status..."

# Check replication connection
LAG=$(sudo -u postgres psql -c "
SELECT CASE 
    WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
    THEN 0 
    ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
END as lag_seconds;" -t 2>/dev/null | tr -d ' ')

if [ -n "$LAG" ] && [ "$LAG" != "" ]; then
    log "✓ Replication lag: ${LAG} seconds"
else
    log "⚠ Unable to determine replication lag - may still be connecting"
fi

# Check WAL receiver status
WAL_RECEIVER=$(sudo -u postgres psql -c "SELECT status FROM pg_stat_wal_receiver;" -t 2>/dev/null | tr -d ' ')
if [ "$WAL_RECEIVER" = "streaming" ]; then
    log "✓ WAL receiver is streaming"
else
    log "⚠ WAL receiver status: ${WAL_RECEIVER:-unknown}"
fi

# Display final status
log "PostgreSQL Replica Database setup completed successfully!"
log "PostgreSQL Replica ready - streaming from: $PRIMARY_HOST"
log "Replication user: $REPLICATION_USER"
log "Monitoring and failover scripts installed"
log "Configuration files extracted from archive"

# Display useful information
log "=== Deployment Summary ==="
log "PostgreSQL Version: $POSTGRES_VERSION"
log "Primary Server: $PRIMARY_HOST"
log "Replication User: $REPLICATION_USER"
log "Configuration: /etc/postgresql/$POSTGRES_VERSION/main/"
log "Data Directory: /var/lib/postgresql/$POSTGRES_VERSION/main/"
log "Monitor Script: $SCRIPT_DIR/monitor-replica.sh"
log "Failover Script: $SCRIPT_DIR/promote-replica.sh"

# Display replication information
log "=== Replication Information ==="
log "Recovery Mode: Active (this is a replica)"
log "Primary Connection: $PRIMARY_HOST:5432"
log "Replication Method: Streaming"
log "Automatic Failover: Manual (use promote-replica.sh)"

# Show PostgreSQL status
systemctl status postgresql --no-pager --lines=5 || log "PostgreSQL status unavailable"

# Display last received WAL location
LAST_RECEIVED=$(sudo -u postgres psql -c "SELECT pg_last_wal_receive_lsn();" -t 2>/dev/null | tr -d ' ')
LAST_REPLAYED=$(sudo -u postgres psql -c "SELECT pg_last_wal_replay_lsn();" -t 2>/dev/null | tr -d ' ')

if [ -n "$LAST_RECEIVED" ] && [ -n "$LAST_REPLAYED" ]; then
    log "Last received WAL: $LAST_RECEIVED"
    log "Last replayed WAL: $LAST_REPLAYED"
fi

# Disable cloud-init to prevent network configuration conflicts on future boots
log "Disabling cloud-init to prevent network configuration issues..."
touch /etc/cloud/cloud-init.disabled 2>/dev/null || log "Warning: Could not disable cloud-init"

# Ensure all background processes complete and file handles are closed
log "Finalizing deployment and closing all processes..."
sync  # Force filesystem sync

# Final completion signal
echo "DEPLOYMENT_COMPLETE: $(date)" >> "$FULL_OUTPUT_LOG"
log "Setup completed successfully. PostgreSQL Replica deployment finished."

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
log "PostgreSQL Replica deployment fully completed"

exit 0