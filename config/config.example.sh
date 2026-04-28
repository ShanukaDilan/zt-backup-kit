#!/bin/bash
# ==============================================================================
#  zt-backup-kit configuration
# ------------------------------------------------------------------------------
#  Copy this file to "config.sh" in the same directory and customize.
#  Both backup.sh and restore.sh source it automatically.
#
#    cp config/config.example.sh config/config.sh
#    chmod 600 config/config.sh
#    nano config/config.sh
#
#  IMPORTANT: config.sh is git-ignored so credentials never reach the repo.
# ==============================================================================

# ---------------- Source paths ----------------

# Directories to back up (colon-separated). The user running the script must
# have read access. Example webroot + app data:
SRC_PATHS_RAW="/var/www/html:/var/www/myapp"

# ---------------- Restic password ----------------

# Path to a file containing the restic encryption password.
# Create it with:
#   echo 'YOUR-LONG-RANDOM-PASSWORD' > "$HOME/.restic-pass"
#   chmod 400 "$HOME/.restic-pass"
#
# WITHOUT THIS PASSWORD YOUR BACKUPS ARE PERMANENTLY UNRECOVERABLE.
# Store a paper copy in a safe along with the encrypted credentials archive.
export RESTIC_PASSWORD_FILE="${HOME}/.restic-pass"

# ---------------- rclone configuration ----------------

# Path to rclone's config file. Default location used by `rclone config`.
export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

# ---------------- Backup targets ----------------

# Format: "Friendly Name|Restic repository string|NeedsSSH(yes|no)"
#
# Examples (uncomment one or more):
#
#   Google Drive (via rclone):
#     "Google Drive|rclone:MyDrive:Backups/ResticRepo|no"
#
#   Backblaze B2 (via rclone or native):
#     "Backblaze B2|rclone:b2-remote:my-bucket/restic|no"
#     "Backblaze B2|b2:my-bucket:restic|no"   # native (set B2_ACCOUNT_ID/B2_ACCOUNT_KEY)
#
#   AWS S3 (native):
#     "AWS S3|s3:s3.amazonaws.com/my-bucket/restic|no"
#
#   Local NAS over SFTP:
#     "Local NAS|sftp:user@192.168.1.50:/volume1/Backups/ResticRepo|yes"
#
#   Plain filesystem (mounted disk, NFS, etc.):
#     "Local disk|/mnt/backup-disk/restic|no"
#
# Multiple targets are backed up sequentially in a single run.
TARGETS=(
  "Google Drive|rclone:MyDrive:Backups/ResticRepo|no"
  # "Local NAS|sftp:user@192.168.1.50:/volume1/Backups/ResticRepo|yes"
)

# SSH key used for SFTP/SSH targets (only loaded if a target sets NeedsSSH=yes).
NAS_KEY="${HOME}/.ssh/id_backup"

# ---------------- Identity & notifications ----------------

# Used in email subject lines and report headers.
HOST_TAG="MyServer"

# Notification recipients (comma-separated). Leave empty to disable email.
EMAILS=""

# msmtp config file (see https://marlam.de/msmtp/ for setup).
MSMTP_CONFIG="${HOME}/.msmtprc"

# ---------------- Retention policy ----------------

KEEP_DAILY=14      # keep last 14 daily snapshots
KEEP_WEEKLY=4      # keep last 4 weekly snapshots
KEEP_MONTHLY=6     # keep last 6 monthly snapshots

# Run prune (heavy, rewrites pack files) only on this day of the week.
# 1=Mon ... 7=Sun. Recommended: weekly, off-peak.
PRUNE_DOW="7"

# Run integrity check (downloads a sample to verify) only on this day.
CHECK_DOW="3"

# ---------------- rclone throttling (optional but recommended) ----------------

# These help avoid hitting cloud-provider API rate limits, especially Google Drive.
# If you have your own OAuth credentials (see docs/INSTALL.md) you can relax these.
export RCLONE_TPSLIMIT=10
export RCLONE_TPSLIMIT_BURST=1
export RCLONE_TRANSFERS=4
export RCLONE_DRIVE_PACER_MIN_SLEEP=10ms
export RCLONE_DRIVE_PACER_BURST=100

# Larger pack size = fewer files on remote = fewer API calls.
export RESTIC_PACK_SIZE=64

# ---------------- Exclusion patterns ----------------

# Files and directories Restic should skip. Useful for cutting noise from
# user-private files, caches, logs, and regenerable build artifacts.
EXCLUDE_PATTERNS=(
  # User shell artifacts
  ".bash_history"
  ".bash_logout"
  ".zsh_history"
  ".lesshst"
  ".viminfo"
  ".python_history"
  ".node_repl_history"
  # User caches & private dirs
  ".cache"
  ".gnupg"
  ".ssh"
  ".npm"
  ".composer/cache"
  # Temporary / runtime
  "*.tmp"
  "*.swp"
  "*.swo"
  "*~"
  "tmp/"
  "temp/"
  "cache/"
  "Cache/"
  "sessions/"
  # Logs (these get huge and rarely useful in backups)
  "*.log"
  "logs/"
  "log/"
  # Build artifacts (regenerable)
  "node_modules/"
  ".git/objects/pack/"
  # OS junk
  ".DS_Store"
  "Thumbs.db"
  "desktop.ini"
)

# ---------------- Working directories ----------------

# Where logs and lock files live. Created automatically.
BACKUP_HOME="${HOME}/.zt-backup-kit"
LOG_DIR="${BACKUP_HOME}/logs"
LOCK_FILE="${BACKUP_HOME}/backup.lock"
SKIP_LOG="${LOG_DIR}/backup-skipped.log"

# How many days of detailed logs to keep on disk before auto-deletion.
LOG_RETENTION_DAYS=30
