# Backup Automation

A Bash script for creating timestamped, compressed backups with automatic rotation based on configurable retention periods.

## Features

- Timestamped backup archives (tar.gz, tar.bz2, tar.xz, or plain tar)
- Configurable source directories, destination, and retention
- Automatic rotation: deletes backups older than the retention period
- Detailed logging with backup size and duration
- Dry-run mode to preview operations
- Verbose mode for detailed progress output

## Requirements

- Bash 4.0+
- `tar`, `gzip`/`bzip2`/`xz` (depending on compression choice)
- `bc` (for size formatting)

## Usage

```bash
chmod +x backup.sh

# Run with default config (backup.conf)
./backup.sh

# Use a custom config file
./backup.sh -c /etc/my-backup.conf

# Dry-run with verbose output
./backup.sh -n -v

# Show help
./backup.sh -h
```

### Flags

| Flag | Description |
|------|-------------|
| `-c CONFIG` | Path to config file (default: `backup.conf`) |
| `-n` | Dry-run: show what would be done without creating backups |
| `-v` | Verbose: show detailed progress |
| `-h` | Show help message |

## Configuration

Edit `backup.conf`:

```
SOURCE_DIRS=/home/user/documents,/home/user/projects,/etc
DEST_DIR=/tmp/backups
RETENTION_DAYS=30
COMPRESSION=gzip
BACKUP_PREFIX=backup
```

| Setting | Description |
|---------|-------------|
| `SOURCE_DIRS` | Comma-separated list of directories to back up |
| `DEST_DIR` | Where to store backup archives |
| `RETENTION_DAYS` | Delete backups older than this (days) |
| `COMPRESSION` | `gzip`, `bzip2`, `xz`, or `none` |
| `BACKUP_PREFIX` | Prefix for backup filenames |

## Sample Output

```
Backup Automation
Timestamp:   2026-04-18 10:00:00
Config:      backup.conf
Destination: /tmp/backups
Compression: gzip
Retention:   30 days

=== Creating Backup ===
[2026-04-18 10:00:00] [INFO] Backup file: backup_20260418_100000.tar.gz
[2026-04-18 10:00:00] [INFO] Sources: /home/user/documents /home/user/projects /etc
[2026-04-18 10:00:03] [INFO] Backup created successfully
[2026-04-18 10:00:03] [INFO] Size: 156.42 MB
[2026-04-18 10:00:03] [INFO] Duration: 3s

=== Backup Rotation ===
[2026-04-18 10:00:03] [INFO] Deleted 2 old backup(s), freed 312.10 MB

=== Current Backups ===
[2026-04-18 10:00:03] [INFO] 5 backup(s) stored, total size: 780.25 MB

Done.
```



<sub><sup>Originally developed and tested locally during learning. Later organized and pushed to GitHub for portfolio visibility.</sup></sub>
