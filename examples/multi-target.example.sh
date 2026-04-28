#!/bin/bash
# ==============================================================================
#  Example: 3-2-1 multi-target backup configuration
# ------------------------------------------------------------------------------
#  This is an example snippet showing how to configure multiple backup targets
#  in a single run, implementing the classic "3-2-1" rule:
#    - 3 copies of data
#    - 2 different storage media types
#    - 1 off-site copy
#
#  Drop the TARGETS array below into your config/config.sh.
# ==============================================================================

# Three independent backup targets:
#   1. Local NAS over SFTP   (fast, on-premises, pulled when you're at the office)
#   2. Backblaze B2          (cheapest off-site, fast restore)
#   3. Google Drive          (familiar interface, easy to share access)
TARGETS=(
  "Local NAS|sftp:backup@nas.lan:/volume1/Backups/ResticRepo|yes"
  "Backblaze B2|b2:my-backup-bucket:restic|no"
  "Google Drive|rclone:MyDrive:Backups/ResticRepo|no"
)

# Make sure ALL of these are set (the kit needs them at runtime):
export RESTIC_PASSWORD_FILE="${HOME}/.restic-pass"
export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

# Backblaze native backend needs these env vars
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-application-key"

# SSH key for the NAS target
NAS_KEY="${HOME}/.ssh/id_backup"

# Note: The kit processes targets sequentially in the order listed. If any
# target fails, the others still run and the email reports per-target status.
# A single run with 3 targets takes roughly 3x the time of a single-target run,
# but the data is uploaded only once per target (Restic dedup means most chunks
# already exist after the first target's run).
