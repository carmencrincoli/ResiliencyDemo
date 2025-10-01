#!/bin/sh
# Minimal Bash Installer Script for Azure Local E-commerce Application
# This script ensures bash is installed and available on Ubuntu systems
# Uses /bin/sh for maximum compatibility during initial bootstrap

# Create log file first
LOG_FILE="/var/log/bashdeploy.log"
mkdir -p /var/log

# Basic logging function that writes to both console and log file
log() {
    MESSAGE="$(date '+%Y-%m-%d %H:%M:%S') [BASH-INSTALLER] $1"
    echo "$MESSAGE"
    echo "$MESSAGE" >> "$LOG_FILE"
}

log "Starting bash installation check..."

# Disable automatic updates to prevent package lock conflicts during deployment
log "Stopping and disabling unattended-upgrades to prevent lock conflicts..."
systemctl stop unattended-upgrades 2>/dev/null || log "unattended-upgrades not running"
systemctl disable unattended-upgrades 2>/dev/null || log "unattended-upgrades not installed"

# Also stop apt-daily services that can cause similar issues
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true

# Check if bash is already installed and working
BASH_INSTALLED=false
if command -v bash > /dev/null 2>&1 && [ -f "/bin/bash" ] && /bin/bash -c 'echo "test"' > /dev/null 2>&1; then
    BASH_VERSION=$(bash --version 2>/dev/null | head -n1 | cut -d' ' -f4 2>/dev/null || echo 'unknown')
    log "Bash already installed and working (version: $BASH_VERSION)"
    BASH_INSTALLED=true
else
    log "Bash not found or not working, proceeding with installation..."
fi

# Only install bash if not already present and working
if [ "$BASH_INSTALLED" = false ]; then
    # Update package lists (non-blocking)
    log "Updating package lists..."
    apt-get update || log "Package update completed with warnings"

    # Install bash (critical operation)
    log "Installing bash package..."
    if apt-get install -y bash; then
        log "Bash package installed successfully"
    else
        log "Error: Failed to install bash package"
        exit 1
    fi

    # Verify bash installation (critical)
    if command -v bash > /dev/null 2>&1; then
        log "Bash installed and available"
    else
        log "Error: Bash not found after installation"
        exit 1
    fi

    # Ensure bash is available at /bin/bash
    if [ ! -f "/bin/bash" ]; then
        BASH_PATH=$(which bash 2>/dev/null)
        if [ -n "$BASH_PATH" ] && [ -f "$BASH_PATH" ]; then
            ln -sf "$BASH_PATH" /bin/bash
            log "Created symlink: /bin/bash -> $BASH_PATH"
        else
            log "Error: Could not find bash to create symlink"
            exit 1
        fi
    fi

    # Make bash executable
    chmod +x /bin/bash

    # Test bash functionality (critical)
    if /bin/bash -c 'echo "Bash test successful"'; then
        log "Bash functionality test passed"
    else
        log "Error: Bash functionality test failed"
        exit 1
    fi
fi

# Always configure shell settings (whether bash was just installed or already present)
log "Configuring bash as default shell..."

# Set environment
export SHELL="/bin/bash"

# Add bash to shells (non-critical)
if [ ! -f "/etc/shells" ] || ! grep -q "^/bin/bash$" /etc/shells 2>/dev/null; then
    echo "/bin/bash" >> /etc/shells 2>/dev/null || log "Could not update /etc/shells"
    log "Added /bin/bash to /etc/shells"
fi

# Configure default shell for new users (non-critical)
if [ -f "/etc/default/useradd" ]; then
    if grep -q "^SHELL=" /etc/default/useradd 2>/dev/null; then
        sed -i 's|^SHELL=.*|SHELL=/bin/bash|' /etc/default/useradd 2>/dev/null || log "Could not update useradd default shell"
    else
        echo "SHELL=/bin/bash" >> /etc/default/useradd 2>/dev/null || log "Could not add default shell to useradd"
    fi
else
    echo "SHELL=/bin/bash" > /etc/default/useradd 2>/dev/null || log "Could not create useradd configuration"
fi

# Update root shell (non-critical)
if command -v usermod > /dev/null 2>&1; then
    usermod -s /bin/bash root || log "Could not update root shell via usermod"
fi

# Update ubuntu shell if exists (non-critical)
if id ubuntu > /dev/null 2>&1 && command -v usermod > /dev/null 2>&1; then
    usermod -s /bin/bash ubuntu || log "Could not update ubuntu shell via usermod"
fi

# Create completion marker
echo "$(date '+%Y-%m-%d %H:%M:%S')" > /var/log/bash-ready.marker

log "Bash installation completed successfully"
log "Bash version: $(bash --version 2>/dev/null | head -n1 | cut -d' ' -f4 2>/dev/null || echo 'unknown')"

exit 0