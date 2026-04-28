# FAQ

## General

### Why Restic and not BorgBackup, Duplicati, Kopia, etc.?

All of these are solid choices. Restic was picked because:

- Single static binary (no Python/Mono runtime)
- Wide native backend support (S3, B2, GCS, Azure, SFTP, plus rclone wraps the rest)
- Very active development
- Good performance for cloud backends
- Mature CLI

If you have a strong preference for another tool, the wrapper logic in this
kit (config sourcing, locking, exit code handling, email reporting) is mostly
backend-agnostic and could be ported.

### Is this audited / battle-tested?

zt-backup-kit itself is new (v0.1, released 2026). The underlying tool, restic,
is widely used in production. Most of what makes this kit *safe* comes from
restic; the wrapper adds operational quality-of-life and a documented
recovery process.

Treat it like any open source tool: read the code, understand what it does,
test it for your scenario before relying on it.

### Can I use this on macOS?

For *backups*, no — designed and tested only on Linux.

For *restores*, yes — `restore.sh` and `emergency-restore.sh` work on macOS.
This matters for emergency recovery to a Mac laptop when the server is gone.

### Can I use this on Windows?

Backups: not directly. WSL2 works, but native Windows is not supported.

Restores: WSL2 or Git Bash for `emergency-restore.sh`. Or use restic + rclone
manually following the runbook commands — Windows-native binaries exist for
both.

## Configuration

### How often should I run the backup?

Depends on RPO needs. Reasonable defaults:

- **Daily** — most websites and small apps. RPO 24 hours.
- **Hourly** — busy databases, e-commerce, anything where 24 hours of loss hurts.
- **Every 15 minutes** — high-frequency change. Make sure your bandwidth and
  cloud quotas can sustain it.

For Google Drive specifically, use your own OAuth project (see INSTALL.md §8)
before going more frequent than hourly to avoid rate limits.

### How long should I keep snapshots?

Default is 14 daily / 4 weekly / 6 monthly = roughly 6 months of history.
Adjust in `config.sh`:

```bash
KEEP_DAILY=14
KEEP_WEEKLY=4
KEEP_MONTHLY=6
```

For ransomware resilience, keep at least 30 days. Some attackers dwell for
weeks before triggering, hoping their backdoors get into all snapshots. A
month of retention gives you uninfected snapshots to fall back to.

### Can I exclude a directory entirely?

Yes — add to `EXCLUDE_PATTERNS`:

```bash
EXCLUDE_PATTERNS=(
  "*.log"
  "node_modules/"
  "/var/www/html/large-uploads"   # specific path
)
```

Patterns work like `.gitignore`.

### What about backing up databases?

This kit backs up **files**, not running databases. For MySQL/PostgreSQL,
the standard pattern is:

1. Run a database dump on a schedule (separate cron job, e.g. `mysqldump`)
2. Write the dump to a directory included in `SRC_PATHS_RAW`
3. zt-backup-kit picks it up on its normal run

Don't try to back up live database data files — you'll get crash-consistent
but not transactionally-consistent snapshots, which can make restore painful.

A future helper script (`scripts/db-backup.sh`) is on the roadmap.

## Costs

### How much will Google Drive cost me?

Google One pricing (subject to change):
- 100 GB: ~$2/month
- 200 GB: ~$3/month
- 2 TB: ~$10/month

Restic deduplication is aggressive, so 100 GB of backed-up data often fits
in 30-50 GB of stored chunks. Test with `restic stats --mode raw-data`.

### What about Backblaze B2?

B2 is the cheapest for serious data:
- $6/TB/month storage
- $10/TB egress (most providers charge a lot more)
- 10 GB/month free egress

For backups (write-heavy, restore is rare), B2 typically beats every other
provider on cost.

### AWS S3?

S3 pricing is more complex. Roughly:
- Standard: ~$23/TB/month
- IA (infrequent access): ~$13/TB/month + retrieval fees
- Glacier: cheap to store (~$1/TB/month) but slow to restore

For restic specifically, Standard or IA are practical. Glacier is only
useful for archive snapshots you'll never realistically restore.

## Security

### What if my restic password is compromised?

If you suspect the password is compromised but the repository itself isn't,
you can change it without re-uploading:

```bash
restic key add        # adds a new password
restic key list       # shows all
restic key remove <id-of-old-key>
```

If the repository itself is compromised (someone has your password AND
ability to reach the storage), you should:
1. Create a new repository with a new password
2. Migrate snapshots forward
3. Delete the old repository

### Can the cloud provider read my data?

No. Restic encrypts client-side with AES-256 before any data leaves your
server. Google/AWS/B2 see encrypted blobs. Without your password, the data
is mathematically inaccessible to anyone, including the cloud provider,
including law enforcement subpoenaing your cloud provider.

This is the whole point of using a tool like restic.

### What if I lose my password?

Your data is permanently inaccessible. There is no recovery, no backdoor,
no support team that can help. AES-256 with a strong password is unbreakable.

This is why the runbook spends so much time on protecting the password —
it's the single most important artifact in your DR setup.

### Can I store the password in a password manager?

Yes, that's a reasonable approach. 1Password, Bitwarden, etc. work fine.
Just make sure:
- You're not the only person who can access the password manager
- The password manager itself is backed up
- A copy of the password exists on physical paper somewhere as final fallback

## Troubleshooting

### "Backup failed - exit 3"

This is `Success (some files skipped)` in newer versions of the kit. It
means the snapshot saved successfully but a few files couldn't be read
(usually due to permissions). Check the log to see which files. Usually
they're system files or other users' private files that don't matter.

### "Repository is already locked"

A previous run was killed. Run `restic unlock` to clear it.

### Daily summary log shows "Status=Warning" but I can't tell why

Check the detailed log:

```bash
ls -t ~/.zt-backup-kit/logs/backup-*.log | head -1 | xargs cat
```

Common causes:
- Some files unreadable (exit 3, see above)
- Email failed to send (msmtp issue)
- `forget` or `check` reported errors

### Backups are succeeding but I never receive emails

Test msmtp directly:

```bash
echo "Test" | msmtp -a default you@example.com
cat ~/.msmtp.log
```

If msmtp itself works but the kit's emails don't arrive, check spam folders.
Provider-side rejection is common for emails sent from residential IPs.

## Project / community

### How can I contribute?

See [CONTRIBUTING.md](../CONTRIBUTING.md). High-impact contributions are
listed there — pull-mode setup, notification integrations, additional
distro testing, etc.

### Is there a Slack / Discord / forum?

Not yet. Use GitHub Issues for everything: bugs, questions, feature requests.

### Will this be maintained?

Best effort. It's a personal project that grew out of a real need. If
people use it, I'll keep it going. PRs that improve quality without
expanding scope are very welcome.

### Can I use this commercially?

Yes — MIT license. Use it however you like, including in commercial
products. No warranty, you assume all risk. Crediting the project is
appreciated but not required.
