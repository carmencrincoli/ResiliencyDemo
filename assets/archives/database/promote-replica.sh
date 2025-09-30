#!/bin/bash
# Manual failover script for PostgreSQL Replica - USE WITH CAUTION
# This script promotes a replica to become the new primary

FAILOVER_LOG="/var/log/postgresql-failover.log"

# Logging function
log_failover() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$FAILOVER_LOG"
}

log_failover "=== PostgreSQL Replica Promotion Script ==="
log_failover "WARNING: This will promote the replica to primary!"
log_failover "Make sure the primary server is down before proceeding."

# Check if running interactively
if [ -t 0 ]; then
    echo "WARNING: This will promote the replica to primary!"
    echo "Make sure the primary server is down before proceeding."
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Failover cancelled."
        log_failover "Failover cancelled by user"
        exit 0
    fi
else
    log_failover "Running in non-interactive mode - proceeding with promotion"
fi

# Check if server is currently a replica
RECOVERY_STATUS=$(sudo -u postgres psql -c "SELECT pg_is_in_recovery();" -t 2>/dev/null | tr -d ' ')
if [ "$RECOVERY_STATUS" != "t" ]; then
    log_failover "✗ Server is not in recovery mode - already a primary or promotion failed"
    exit 1
fi

log_failover "Pre-promotion status check..."
log_failover "Server is in recovery mode (replica) - proceeding with promotion"

# Get current WAL position before promotion
LAST_RECEIVED=$(sudo -u postgres psql -c "SELECT pg_last_wal_receive_lsn();" -t 2>/dev/null | tr -d ' ')
LAST_REPLAYED=$(sudo -u postgres psql -c "SELECT pg_last_wal_replay_lsn();" -t 2>/dev/null | tr -d ' ')

log_failover "Last received WAL: $LAST_RECEIVED"
log_failover "Last replayed WAL: $LAST_REPLAYED"

# Promote the replica
log_failover "Promoting replica to primary..."
sudo -u postgres pg_promote

# Wait for promotion to complete
log_failover "Waiting for promotion to complete..."
sleep 5

# Check promotion status multiple times
for i in {1..10}; do
    RECOVERY_STATUS=$(sudo -u postgres psql -c "SELECT pg_is_in_recovery();" -t 2>/dev/null | tr -d ' ')
    if [ "$RECOVERY_STATUS" = "f" ]; then
        log_failover "✓ Replica successfully promoted to primary (check $i)"
        break
    else
        log_failover "Still in recovery mode, waiting... (check $i)"
        sleep 2
    fi
done

# Final verification
RECOVERY_STATUS=$(sudo -u postgres psql -c "SELECT pg_is_in_recovery();" -t 2>/dev/null | tr -d ' ')
if [ "$RECOVERY_STATUS" = "f" ]; then
    log_failover "✓ Promotion successful - server is now primary"
    log_failover "Remember to:"
    log_failover "  1. Update application connection strings"
    log_failover "  2. Reconfigure any remaining replicas to use this as primary"
    log_failover "  3. Update load balancer configuration if applicable"
    log_failover "  4. Review and update backup procedures"
    
    # Display new primary status
    NEW_LOCATION=$(sudo -u postgres psql -c "SELECT pg_current_wal_lsn();" -t 2>/dev/null | tr -d ' ')
    log_failover "New primary WAL location: $NEW_LOCATION"
    
    echo "✓ Promotion successful - server is now primary"
    echo "Remember to update application connection strings!"
else
    log_failover "✗ Promotion failed - server still in recovery mode"
    echo "✗ Promotion failed"
    exit 1
fi