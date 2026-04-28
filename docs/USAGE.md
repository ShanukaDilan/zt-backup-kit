# Usage Guide

Day-to-day operations once zt-backup-kit is installed.

## Running a backup manually

```bash
./bin/backup.sh
```

You'll see live progress and get an email (if configured) when it finishes.

## Running with options

```bash
./bin/backup.sh --check          # validate config, don't back up
./bin/backup.sh --dry-run        # show what would happen, don't transfer
./bin/backup.sh --config /path/to/other.sh   # alternate config
```

## Inspecting backups

The fastest way to see the state of your repository is `backup-status.sh`:

```bash
./bin/backup-status.sh                # full report
./bin/backup-status.sh --short        # one-page summary
./bin/backup-status.sh --runs         # only run history
./bin/backup-status.sh --json         # machine-readable
```

It shows snapshot count, sizes, deduplication ratio, freshness of the latest
snapshot (color-coded), the last 15 backup runs from your local log, and
whether the cron schedule is installed.

For lower-level access, set the same environment your config uses, then run
any restic command:

```bash
export RCLONE_CONFIG="$HOME/.config/rclone/rclone.conf"
export RESTIC_PASSWORD_FILE="$HOME/.restic-pass"
export RESTIC_REPOSITORY="rclone:MyDrive:Backups/ResticRepo"

# List all snapshots
restic snapshots

# Show repository statistics
restic stats               # logical (uncompressed) size
restic stats --mode raw-data  # actual bytes stored on remote

# List files in the latest snapshot
restic ls latest

# Find every version of a specific file
restic find /var/www/html/index.php

# Compare two snapshots
restic diff <id1> <id2>
```

## Restoring data

### File or folder recovery

```bash
./bin/restore.sh
```

Walks you through:
1. Picking a snapshot
2. Choosing full vs partial restore
3. Specifying where to restore to (defaults to `/tmp/restore-<timestamp>`,
   which is safe — never overwrites originals unless you tell it to)

### Browse without restoring

The mount mode in `restore.sh` lets you treat any snapshot as a normal folder:

```bash
./bin/restore.sh
# Choose option 3 (Mount snapshot)

# In another terminal:
cd /tmp/ztbk-mount-*/snapshots/latest
ls -la
# Browse, copy specific files, etc.
```

Press Ctrl+C in the original terminal to unmount.

### Emergency recovery on another machine

See `bin/emergency-restore.sh` and the procedure in
[DR-RUNBOOK.md](DR-RUNBOOK.md#scenario-c--emergency-self-service-restore).

## Monitoring

### Email reports

If `EMAILS` is set in `config.sh`, every run sends an HTML report with:

- Overall status (Success / Warning / Failed)
- Per-target status table
- File counts, data added, duration
- Source paths and timestamps
- The full log file as an attachment

### Daily summary log

Every run appends one line to `~/.zt-backup-kit/logs/backup-summary.log`:

```
[20260428-090000] Status=Success Log=/home/backup/.zt-backup-kit/logs/backup-20260428-090000.log
[20260429-090000] Status=Success Log=/home/backup/.zt-backup-kit/logs/backup-20260429-090000.log
```

Useful for `tail` watching or simple grep-based monitoring.

### Detailed logs

Full per-run logs live in `~/.zt-backup-kit/logs/backup-<timestamp>.log` and
are auto-rotated based on `LOG_RETENTION_DAYS` in your config (default 30 days).

### Skipped runs

If cron tries to start a backup while another is still running, the new run
exits immediately and appends to `~/.zt-backup-kit/logs/backup-skipped.log`.
This is safe behavior — `flock` is doing its job.

## Maintenance

### Forcing a forget + prune

The kit auto-prunes weekly (configured by `PRUNE_DOW`). To run manually:

```bash
restic forget --keep-daily 14 --keep-weekly 4 --keep-monthly 6 --prune
```

### Verifying repo integrity

```bash
# Quick: metadata only (fast)
restic check

# Thorough: download a sample
restic check --read-data-subset=10%

# Full: download everything (slow, expensive on cloud)
restic check --read-data
```

The kit auto-runs the 2% sample check weekly (`CHECK_DOW`).

### Removing a snapshot

```bash
restic snapshots                    # find the ID
restic forget <snapshot-id>         # mark for deletion
restic prune                        # actually remove the data
```

### Migrating to a new target

Easy — restic repositories are self-contained. For example, to move from
Google Drive to Backblaze B2:

```bash
# Copy the repo
restic -r rclone:MyDrive:Backups/ResticRepo \
       copy --from-repo b2:new-bucket:restic

# Or use rclone directly
rclone copy MyDrive:Backups/ResticRepo b2:new-bucket/restic --progress
```

Then update your `TARGETS` array in `config.sh`.

## Troubleshooting

### "Repository not found"

Either the path is wrong or the password is wrong. Check:

```bash
echo "$RESTIC_REPOSITORY"
cat $RESTIC_PASSWORD_FILE | head -c 20  # shows first 20 chars
restic snapshots                          # see the actual error
```

### "Lock failed" / "repository is already locked"

A previous run was killed. Clear with:

```bash
restic unlock
```

### Email not arriving

```bash
# Test msmtp directly
echo "Test" | msmtp -a default you@example.com

# Check msmtp's log
cat ~/.msmtp.log
```

Common issues:
- App password not used (Gmail requires this if 2FA is on)
- TLS misconfigured
- Sender email rejected by recipient's SPF/DKIM rules

### "rate limit exceeded" / 403 errors

You're using shared rclone OAuth credentials. See
[INSTALL.md §8](INSTALL.md#8-recommended-create-your-own-google-cloud-oauth-project)
to create your own OAuth project — solves this permanently.

### Backup is slow

First runs are always slow (no dedup baseline). Subsequent runs should be fast
because only changed chunks transfer. If it's chronically slow:

- Check your upload bandwidth: `speedtest-cli`
- Consider raising `RCLONE_TRANSFERS` (default 4) if your bandwidth allows
- For very large repos, use a closer cloud region
