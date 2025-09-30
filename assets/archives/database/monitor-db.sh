#!/bin/bash
# Database monitoring script for PostgreSQL Primary

DB_NAME="${DB_NAME:-ecommerce}"
HEALTH_LOG="/var/log/db-health.log"

# Logging function
log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$HEALTH_LOG"
}

log_health "=== PostgreSQL Primary Health Check ==="

# Check if PostgreSQL service is running
if systemctl is-active --quiet postgresql; then
    log_health "✓ PostgreSQL service is running"
else
    log_health "✗ PostgreSQL service is not running - attempting to start"
    systemctl start postgresql
    sleep 3
    if systemctl is-active --quiet postgresql; then
        log_health "✓ PostgreSQL service started successfully"
    else
        log_health "✗ Failed to start PostgreSQL service"
        exit 1
    fi
fi

# Check database connectivity
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    log_health "✓ Database connection OK"
else
    log_health "✗ Database connection failed"
    exit 1
fi

# Check replication status
REPLICA_COUNT=$(sudo -u postgres psql -t -c "SELECT COUNT(*) FROM pg_stat_replication;" 2>/dev/null | tr -d ' ')
if [ "$REPLICA_COUNT" -gt 0 ]; then
    log_health "✓ Replication is active - $REPLICA_COUNT replica(s) connected"
    
    # Show replication details
    sudo -u postgres psql -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;" 2>/dev/null | while read line; do
        if [ -n "$line" ]; then
            log_health "  Replica: $line"
        fi
    done
else
    log_health "⚠ No active replicas connected"
fi

# Check database size
DB_SIZE=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" 2>/dev/null | tr -d ' ')
if [ -n "$DB_SIZE" ]; then
    log_health "Database size: $DB_SIZE"
fi

# Check connection count
CONN_COUNT=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tr -d ' ')
if [ -n "$CONN_COUNT" ]; then
    log_health "Active connections: $CONN_COUNT"
fi

# Check for long-running queries (over 5 minutes)
LONG_QUERIES=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND now() - query_start > interval '5 minutes';" 2>/dev/null | tr -d ' ')
if [ "$LONG_QUERIES" -gt 0 ]; then
    log_health "⚠ Warning: $LONG_QUERIES long-running queries detected"
else
    log_health "✓ No long-running queries"
fi

# Check archive directory space
ARCHIVE_DIR="/var/lib/postgresql/16/main/archive"
if [ -d "$ARCHIVE_DIR" ]; then
    ARCHIVE_COUNT=$(ls -1 "$ARCHIVE_DIR" 2>/dev/null | wc -l)
    log_health "WAL archive files: $ARCHIVE_COUNT"
    
    # Clean up old WAL files (keep last 50)
    if [ "$ARCHIVE_COUNT" -gt 50 ]; then
        ls -1t "$ARCHIVE_DIR"/* | tail -n +51 | xargs rm -f 2>/dev/null
        log_health "Cleaned up old WAL archive files"
    fi
fi

# Check disk space for data directory
DATA_DIR_USAGE=$(df -h /var/lib/postgresql | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DATA_DIR_USAGE" -gt 80 ]; then
    log_health "⚠ Warning: Data directory disk usage is ${DATA_DIR_USAGE}%"
elif [ "$DATA_DIR_USAGE" -gt 90 ]; then
    log_health "✗ Critical: Data directory disk usage is ${DATA_DIR_USAGE}%"
else
    log_health "✓ Data directory disk usage: ${DATA_DIR_USAGE}%"
fi

log_health "Health check completed"