#!/bin/bash
# FlowSpace Database Backup Script (Linux/macOS)
# Runs pg_dump inside the PostgreSQL Docker container, compresses the output, and performs rotation.

set -e

# Configuration
DB_CONTAINER="flowspace_postgres"
DB_USER="flowspace_user"
DB_NAME="flowspace_db"
BACKUP_DIR="$(pwd)/backups"
RETENTION_COUNT=10
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/flowspace_backup_$TIMESTAMP.sql.gz"

echo "=================================================="
echo "Starting FlowSpace database backup..."
echo "Timestamp: $TIMESTAMP"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Verify docker is installed
if ! command -v docker &> /dev/null; then
    echo "ERROR: docker CLI is not installed or not in PATH."
    exit 1
fi

# Verify container is running
if [ "$(docker inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" != "true" ]; then
    echo "ERROR: Docker container '$DB_CONTAINER' is not running."
    exit 1
fi

# Perform backup
echo "Executing pg_dump inside $DB_CONTAINER..."
if docker exec -t "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" | gzip > "$BACKUP_FILE"; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "Backup completed successfully!"
    echo "Saved to: $BACKUP_FILE ($SIZE)"
else
    echo "ERROR: Database backup failed."
    rm -f "$BACKUP_FILE"
    exit 1
fi

# Perform retention cleanup
echo "Performing backup rotation (keeping last $RETENTION_COUNT backups)..."
cd "$BACKUP_DIR"
# Find backup files, sort them chronologically (oldest first), and get all but the last N
BACKUP_FILES=$(ls -1 flowspace_backup_*.sql.gz 2>/dev/null || true)
BACKUP_COUNT=$(echo "$BACKUP_FILES" | wc -l)

if [ "$BACKUP_COUNT" -gt "$RETENTION_COUNT" ]; then
    REMOVE_COUNT=$((BACKUP_COUNT - RETENTION_COUNT))
    echo "Found $BACKUP_COUNT backups. Removing $REMOVE_COUNT oldest backup(s)..."
    echo "$BACKUP_FILES" | head -n "$REMOVE_COUNT" | while read -r old_file; do
        if [ -n "$old_file" ]; then
            echo "Deleting: $old_file"
            rm -f "$old_file"
        fi
    done
else
    echo "Currently have $BACKUP_COUNT backups. No rotation needed."
fi

echo "Backup process finished."
echo "=================================================="
