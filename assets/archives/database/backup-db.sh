#!/bin/bash
# Database backup script for PostgreSQL Primary

BACKUP_DIR="/opt/ecommerce/backups"
DATE=$(date +%Y%m%d_%H%M%S)
DB_NAME="${DB_NAME:-ecommerce}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Create database backup
sudo -u postgres pg_dump "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_$DATE.sql"

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Database backup created: ${DB_NAME}_$DATE.sql"
    
    # Compress backup
    gzip "$BACKUP_DIR/${DB_NAME}_$DATE.sql"
    
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup compressed: ${DB_NAME}_$DATE.sql.gz"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Failed to compress backup"
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Database backup failed"
    exit 1
fi

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
echo "$(date '+%Y-%m-%d %H:%M:%S') - Old backups cleaned up (kept last 7 days)"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completed successfully: ${DB_NAME}_$DATE.sql.gz"