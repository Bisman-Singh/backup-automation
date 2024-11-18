#!/usr/bin/env bash
#
# backup-automation/backup.sh
# Creates timestamped compressed backups of configured directories.
# Supports backup rotation based on retention period.
#
# Usage: ./backup.sh [-c config_file] [-n] [-v] [-h]
#

set -euo pipefail

# ─── Defaults ───────────────────────────────────────────────────────────────────
CONFIG_FILE="$(dirname "$0")/backup.conf"
DRY_RUN=false
VERBOSE=false
LOG_FILE=""

# ─── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Functions ──────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Creates timestamped, compressed backups of configured directories.
Rotates old backups based on retention period.

Options:
  -c CONFIG   Path to configuration file (default: backup.conf)
  -n          Dry-run: show what would be done without creating backups
  -v          Verbose: show detailed progress
  -h          Show this help message

Configuration File Format:
  SOURCE_DIRS=/path/one,/path/two    Comma-separated source directories
  DEST_DIR=/path/to/backups          Backup destination directory
  RETENTION_DAYS=30                  Delete backups older than N days
  COMPRESSION=gzip                   Compression: gzip, bzip2, xz, none
  BACKUP_PREFIX=backup               Filename prefix for backups

Examples:
  $(basename "$0")                     # Run with defaults
  $(basename "$0") -c /etc/backup.conf # Custom config
  $(basename "$0") -n -v              # Verbose dry-run
  $(basename "$0") -h                 # Show help
EOF
    exit 0
}

log_msg() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""

    case "$level" in
        INFO)  color="$GREEN" ;;
        WARN)  color="$YELLOW" ;;
        ERROR) color="$RED" ;;
        DEBUG) color="$CYAN" ;;
    esac

    echo -e "${color}[$timestamp] [$level]${RESET} $msg"

    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $(echo "$msg" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG_FILE"
    fi
}

log_verbose() {
    if $VERBOSE; then
        log_msg "DEBUG" "$1"
    fi
}

# Load configuration from file
load_config() {
    local config="$1"
    if [[ ! -f "$config" ]]; then
        echo "Error: Config file not found: $config" >&2
        exit 1
    fi

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        case "$key" in
            SOURCE_DIRS)    SOURCE_DIRS="$value" ;;
            DEST_DIR)       DEST_DIR="$value" ;;
            RETENTION_DAYS) RETENTION_DAYS="$value" ;;
            COMPRESSION)    COMPRESSION="$value" ;;
            BACKUP_PREFIX)  BACKUP_PREFIX="$value" ;;
        esac
    done < "$config"
}

# Get file extension based on compression type
get_extension() {
    case "$COMPRESSION" in
        gzip)  echo "tar.gz" ;;
        bzip2) echo "tar.bz2" ;;
        xz)    echo "tar.xz" ;;
        none)  echo "tar" ;;
        *)     echo "tar.gz" ;;
    esac
}

# Get tar compression flag
get_tar_flag() {
    case "$COMPRESSION" in
        gzip)  echo "z" ;;
        bzip2) echo "j" ;;
        xz)    echo "J" ;;
        none)  echo "" ;;
        *)     echo "z" ;;
    esac
}

# Format file size for display
format_size() {
    local size="$1"
    if [[ "$size" -ge 1073741824 ]]; then
        echo "$(echo "scale=2; $size / 1073741824" | bc) GB"
    elif [[ "$size" -ge 1048576 ]]; then
        echo "$(echo "scale=2; $size / 1048576" | bc) MB"
    elif [[ "$size" -ge 1024 ]]; then
        echo "$(echo "scale=2; $size / 1024" | bc) KB"
    else
        echo "${size} B"
    fi
}

# ─── Parse arguments ────────────────────────────────────────────────────────────
while getopts ":c:nvh" opt; do
    case "$opt" in
        c) CONFIG_FILE="$OPTARG" ;;
        n) DRY_RUN=true ;;
        v) VERBOSE=true ;;
        h) usage ;;
        \?) echo "Error: Unknown option -$OPTARG" >&2; usage ;;
        :)  echo "Error: Option -$OPTARG requires an argument" >&2; usage ;;
    esac
done

# ─── Load config ────────────────────────────────────────────────────────────────
# Set defaults
SOURCE_DIRS=""
DEST_DIR=""
RETENTION_DAYS=30
COMPRESSION="gzip"
BACKUP_PREFIX="backup"

load_config "$CONFIG_FILE"

# Validate required settings
if [[ -z "$SOURCE_DIRS" ]]; then
    echo "Error: SOURCE_DIRS not configured in $CONFIG_FILE" >&2
    exit 1
fi
if [[ -z "$DEST_DIR" ]]; then
    echo "Error: DEST_DIR not configured in $CONFIG_FILE" >&2
    exit 1
fi

# Set up log file in destination directory
LOG_FILE="${DEST_DIR}/backup.log"

# ─── Header ─────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Backup Automation${RESET}"
echo -e "Timestamp:   $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Config:      $CONFIG_FILE"
echo -e "Destination: $DEST_DIR"
echo -e "Compression: $COMPRESSION"
echo -e "Retention:   $RETENTION_DAYS days"
if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN MODE] No changes will be made.${RESET}"
fi
echo ""

# ─── Prepare destination ────────────────────────────────────────────────────────
if ! $DRY_RUN; then
    if [[ ! -d "$DEST_DIR" ]]; then
        log_msg "INFO" "Creating destination directory: $DEST_DIR"
        mkdir -p "$DEST_DIR"
    fi
fi

# ─── Parse source directories ───────────────────────────────────────────────────
IFS=',' read -ra SOURCES <<< "$SOURCE_DIRS"

# Validate source directories
valid_sources=()
for src in "${SOURCES[@]}"; do
    src=$(echo "$src" | xargs)  # trim
    if [[ -d "$src" ]]; then
        valid_sources+=("$src")
        log_verbose "Source directory found: $src"
    else
        log_msg "WARN" "Source directory not found, skipping: $src"
    fi
done

if [[ ${#valid_sources[@]} -eq 0 ]]; then
    log_msg "ERROR" "No valid source directories found. Nothing to back up."
    exit 1
fi

# ─── Create backup ──────────────────────────────────────────────────────────────
echo -e "${BOLD}=== Creating Backup ===${RESET}"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
EXT=$(get_extension)
TAR_FLAG=$(get_tar_flag)
BACKUP_NAME="${BACKUP_PREFIX}_${TIMESTAMP}.${EXT}"
BACKUP_PATH="${DEST_DIR}/${BACKUP_NAME}"

log_msg "INFO" "Backup file: $BACKUP_NAME"
log_msg "INFO" "Sources: ${valid_sources[*]}"

START_TIME=$(date '+%s')

if $DRY_RUN; then
    log_msg "INFO" "Would create: $BACKUP_PATH"
    log_msg "INFO" "Would include ${#valid_sources[@]} source director(y/ies)"
else
    # Create the tar archive
    log_verbose "Running: tar -c${TAR_FLAG}f $BACKUP_PATH ${valid_sources[*]}"

    if tar -c"${TAR_FLAG}"f "$BACKUP_PATH" "${valid_sources[@]}" 2>/dev/null; then
        END_TIME=$(date '+%s')
        DURATION=$((END_TIME - START_TIME))

        # Get backup size
        if [[ -f "$BACKUP_PATH" ]]; then
            BACKUP_SIZE=$(stat -f%z "$BACKUP_PATH" 2>/dev/null || stat -c%s "$BACKUP_PATH" 2>/dev/null || echo "0")
            log_msg "INFO" "Backup created successfully"
            log_msg "INFO" "Size: $(format_size "$BACKUP_SIZE")"
            log_msg "INFO" "Duration: ${DURATION}s"
        fi
    else
        log_msg "ERROR" "Backup creation failed!"
        exit 1
    fi
fi
echo ""

# ─── Rotate old backups ─────────────────────────────────────────────────────────
echo -e "${BOLD}=== Backup Rotation ===${RESET}"

if [[ ! -d "$DEST_DIR" ]]; then
    log_msg "INFO" "Destination directory does not exist. No rotation needed."
else
    deleted_count=0
    deleted_size=0

    # Find old backup files matching our prefix and extension
    while IFS= read -r -d '' old_backup; do
        [[ -z "$old_backup" ]] && continue

        # Get file age in days
        if [[ "$(uname -s)" == "Darwin" ]]; then
            file_mod=$(stat -f%m "$old_backup" 2>/dev/null || echo "0")
        else
            file_mod=$(stat -c%Y "$old_backup" 2>/dev/null || echo "0")
        fi
        now=$(date '+%s')
        age_days=$(( (now - file_mod) / 86400 ))

        if [[ "$age_days" -gt "$RETENTION_DAYS" ]]; then
            fsize=$(stat -f%z "$old_backup" 2>/dev/null || stat -c%s "$old_backup" 2>/dev/null || echo "0")
            if $DRY_RUN; then
                log_msg "INFO" "Would delete (${age_days}d old): $(basename "$old_backup") ($(format_size "$fsize"))"
            else
                log_verbose "Deleting (${age_days}d old): $(basename "$old_backup")"
                rm -f "$old_backup"
                deleted_size=$((deleted_size + fsize))
            fi
            ((deleted_count++)) || true
        fi
    done < <(find "$DEST_DIR" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar*" -print0 2>/dev/null || true)

    if [[ "$deleted_count" -gt 0 ]]; then
        if $DRY_RUN; then
            log_msg "INFO" "Would delete $deleted_count old backup(s)"
        else
            log_msg "INFO" "Deleted $deleted_count old backup(s), freed $(format_size "$deleted_size")"
        fi
    else
        log_msg "INFO" "No backups exceed retention period ($RETENTION_DAYS days)"
    fi
fi
echo ""

# ─── List current backups ───────────────────────────────────────────────────────
echo -e "${BOLD}=== Current Backups ===${RESET}"
if [[ -d "$DEST_DIR" ]]; then
    backup_count=0
    total_size=0
    while IFS= read -r -d '' bf; do
        [[ -z "$bf" ]] && continue
        bsize=$(stat -f%z "$bf" 2>/dev/null || stat -c%s "$bf" 2>/dev/null || echo "0")
        total_size=$((total_size + bsize))
        ((backup_count++)) || true
        log_verbose "  $(basename "$bf") - $(format_size "$bsize")"
    done < <(find "$DEST_DIR" -maxdepth 1 -name "${BACKUP_PREFIX}_*.tar*" -print0 2>/dev/null | sort -z || true)

    log_msg "INFO" "$backup_count backup(s) stored, total size: $(format_size "$total_size")"
else
    log_msg "INFO" "No backups found (dry-run mode)"
fi
echo ""

echo -e "${BOLD}Done.${RESET}"
