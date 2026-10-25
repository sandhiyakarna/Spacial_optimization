# FlowSpace Database Backup Script (Windows PowerShell)
# Runs pg_dump inside the PostgreSQL Docker container, compresses to ZIP, and performs rotation.

$ErrorActionPreference = "Stop"

# Configuration
$DB_CONTAINER = "flowspace_postgres"
$DB_USER = "flowspace_user"
$DB_NAME = "flowspace_db"
$BACKUP_DIR = "$PSScriptRoot\..\backups"
$RETENTION_COUNT = 10
$TIMESTAMP = Get-Date -Format "yyyyMMdd_HHmmss"
$TEMP_FILE = "$BACKUP_DIR\flowspace_backup_temp_$TIMESTAMP.sql"
$BACKUP_FILE = "$BACKUP_DIR\flowspace_backup_$TIMESTAMP.sql.zip"

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Starting FlowSpace database backup (Windows)..."
Write-Host "Timestamp: $TIMESTAMP"

# Ensure backup directory exists
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Verify Docker is running
$dockerCheck = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCheck) {
    Write-Error "Docker CLI is not installed or not in PATH."
}

# Verify container is running
$containerStatus = docker inspect -f '{{.State.Running}}' $DB_CONTAINER 2>$null
if ($containerStatus -ne "true") {
    Write-Error "Docker container '$DB_CONTAINER' is not running."
}

# Perform backup
Write-Host "Executing pg_dump inside $DB_CONTAINER..." -ForegroundColor Gray
try {
    # Dump DB to temp sql file
    docker exec -t $DB_CONTAINER pg_dump -U $DB_USER -d $DB_NAME > $TEMP_FILE
    
    # Compress using native PowerShell Compress-Archive
    Compress-Archive -Path $TEMP_FILE -DestinationPath $BACKUP_FILE -Force
    
    # Remove temp uncompressed file
    Remove-Item -Path $TEMP_FILE -Force
    
    $size = (Get-Item $BACKUP_FILE).Length / 1KB
    Write-Host "Backup completed successfully!" -ForegroundColor Green
    Write-Host "Saved to: $BACKUP_FILE ($($size.ToString('N2')) KB)"
}
catch {
    Write-Host "ERROR: Database backup failed. $_" -ForegroundColor Red
    if (Test-Path $TEMP_FILE) { Remove-Item -Path $TEMP_FILE -Force }
    if (Test-Path $BACKUP_FILE) { Remove-Item -Path $BACKUP_FILE -Force }
    exit 1
}

# Perform retention cleanup
Write-Host "Performing backup rotation (keeping last $RETENTION_COUNT backups)..." -ForegroundColor Gray
$backups = Get-ChildItem -Path $BACKUP_DIR -Filter "flowspace_backup_*.zip" | Sort-Object Name

if ($backups.Count -gt $RETENTION_COUNT) {
    $removeCount = $backups.Count - $RETENTION_COUNT
    Write-Host "Found $($backups.Count) backups. Removing $removeCount oldest backup(s)..." -ForegroundColor Yellow
    for ($i = 0; $i -lt $removeCount; $i++) {
        Write-Host "Deleting: $($backups[$i].Name)"
        Remove-Item -Path $backups[$i].FullName -Force
    }
} else {
    Write-Host "Currently have $($backups.Count) backups. No rotation needed." -ForegroundColor Gray
}

Write-Host "Backup process finished." -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
