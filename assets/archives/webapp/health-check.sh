#!/bin/bash

# Health check script for the Next.js web application
# This script checks if the application is responding correctly

set -e

# Configuration
APP_NAME="ecommerce-webapp"
HEALTH_URL="http://localhost:3000/health"
LOG_FILE="/var/log/webapp/health-check.log"
MAX_WAIT_TIME=30
RETRY_INTERVAL=5

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

check_health() {
    local start_time=$(date +%s)
    local end_time=$((start_time + MAX_WAIT_TIME))
    
    log_message "Starting health check for $APP_NAME"
    
    while [ $(date +%s) -lt $end_time ]; do
        # Check if the health endpoint responds with HTTP 200
        if response=$(curl -s -w "%{http_code}" -o /dev/null "$HEALTH_URL" 2>/dev/null); then
            if [ "$response" = "200" ]; then
                log_message "✅ Health check passed - Application is healthy"
                
                # Check if PM2 process is running
                if pm2 describe $APP_NAME >/dev/null 2>&1; then
                    status=$(pm2 describe $APP_NAME | grep 'status' | head -1 | awk '{print $4}')
                    log_message "📊 PM2 Status: $status"
                else
                    log_message "⚠️  PM2 process not found but application is responding"
                fi
                
                exit 0
            else
                log_message "❌ Health check failed - HTTP status: $response"
            fi
        else
            log_message "❌ Health check failed - Cannot connect to application"
        fi
        
        sleep $RETRY_INTERVAL
    done
    
    log_message "❌ Health check timeout - Application is not healthy after ${MAX_WAIT_TIME}s"
    exit 1
}

# Check if port 3000 is being used
if ! netstat -tuln | grep -q ":3000 "; then
    log_message "❌ Application port 3000 is not listening"
    exit 1
fi

# Perform health check
check_health