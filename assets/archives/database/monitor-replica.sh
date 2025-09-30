#!/bin/bash
# Replica monitoring script for PostgreSQL

PRIMARY_HOST="${PRIMARY_IP:-}"
HEALTH_LOG="/var/log/replica-health.log"

# Logging function
log_health() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$HEALTH_LOG"
}

log_health "=== PostgreSQL Replica Health Check ==="

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

# Check if in recovery mode (replica)
RECOVERY_STATUS=$(sudo -u postgres psql -c "SELECT pg_is_in_recovery();" -t 2>/dev/null | tr -d ' ')
if [ "$RECOVERY_STATUS" = "t" ]; then
    log_health "✓ Server is in recovery mode (replica)"
else
    log_health "✗ Server is not in recovery mode - may have been promoted"
fi

# Check replication lag
LAG=$(sudo -u postgres psql -c "
SELECT CASE 
    WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
    THEN 0 
    ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
END as lag_seconds;" -t 2>/dev/null | tr -d ' ')

if [ -n "$LAG" ] && [ "$LAG" != "" ] && [ "$LAG" != "0" ]; then
    if [ $(echo "$LAG < 60" | bc -l 2>/dev/null || echo "1") -eq 1 ]; then
        log_health "✓ Replication lag: ${LAG} seconds"
    else
        log_health "⚠ High replication lag: ${LAG} seconds"
    fi
elif [ "$LAG" = "0" ]; then
    log_health "✓ Replication lag: 0 seconds (up to date)"
else
    log_health "⚠ Unable to determine replication lag"
fi

# Check connection to primary
if [ -n "$PRIMARY_HOST" ]; then
    if pg_isready -h "$PRIMARY_HOST" -p 5432 > /dev/null 2>&1; then
        log_health "✓ Connection to primary server ($PRIMARY_HOST) OK"
    else
        log_health "✗ Cannot connect to primary server ($PRIMARY_HOST)"
    fi
else
    log_health "⚠ PRIMARY_HOST not set - cannot check primary connection"
fi

# Check WAL receiver status
WAL_RECEIVER=$(sudo -u postgres psql -c "SELECT status FROM pg_stat_wal_receiver;" -t 2>/dev/null | tr -d ' ')
if [ "$WAL_RECEIVER" = "streaming" ]; then
    log_health "✓ WAL receiver is streaming"
elif [ -n "$WAL_RECEIVER" ]; then
    log_health "⚠ WAL receiver status: $WAL_RECEIVER"
else
    log_health "⚠ WAL receiver not active"
fi

# Check last received WAL location
LAST_RECEIVED=$(sudo -u postgres psql -c "SELECT pg_last_wal_receive_lsn();" -t 2>/dev/null | tr -d ' ')
LAST_REPLAYED=$(sudo -u postgres psql -c "SELECT pg_last_wal_replay_lsn();" -t 2>/dev/null | tr -d ' ')

if [ -n "$LAST_RECEIVED" ] && [ -n "$LAST_REPLAYED" ]; then
    log_health "Last received WAL: $LAST_RECEIVED"
    log_health "Last replayed WAL: $LAST_REPLAYED"
    
    if [ "$LAST_RECEIVED" = "$LAST_REPLAYED" ]; then
        log_health "✓ WAL replay is up to date"
    else
        log_health "⚠ WAL replay lag detected"
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

# Check connection count
CONN_COUNT=$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" 2>/dev/null | tr -d ' ')
if [ -n "$CONN_COUNT" ]; then
    log_health "Active connections: $CONN_COUNT"
fi

log_health "Replica health check completed"