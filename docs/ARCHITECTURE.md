# Architecture

This document explains the design choices behind zt-backup-kit. If you just
want to get backups running, see [INSTALL.md](INSTALL.md). This is for the
curious and for contributors.

## What problem this solves

Modern ransomware operators target backups before encrypting production.
Industry data has shown the majority of ransomware attacks now include
explicit steps to find and destroy backup repositories before triggering
encryption. A "3-2-1" backup strategy that fails this attack is no strategy
at all — it just gives a false sense of security.

The two competing requirements:

1. **Recovery speed (RTO)** — backups must be quickly retrievable when needed
2. **Resilience** — backups must be inaccessible to a compromised server

Local NAS gives you (1) but fails (2). Cloud cold storage gives you (2) but
fails (1). The Zero-Trust framing of backup is: make the production server
*untrusted* so its compromise can't destroy historical data, while keeping
recovery latency reasonable.

## Core design decisions

### Use restic, not invent something new

restic gives us, free:

- AES-256 encryption with Poly1305 authentication, applied client-side
- Content-defined chunking for deduplication (handles "tiny change at start
  of huge file" gracefully — only the changed chunk uploads)
- Snapshot-based versioning (every backup is a point-in-time view, old
  snapshots are immutable from the application's perspective)
- Repository integrity verification
- A wide range of supported backends (local, SFTP, S3, B2, GCS, Azure, plus
  anything rclone supports)

The kit is a wrapper that adds operational concerns: configuration, scheduling,
reporting, error handling, and recovery procedure.

### Separate backup engine from storage backend

The TARGETS array deliberately accepts any restic-compatible URI:

```bash
"Friendly Name|RESTIC_REPO_STRING|NeedsSSH(yes|no)"
```

This means migrating to a different cloud is a config change, not a code
change. It also means you can have multiple targets in one run — important
for the "3" in "3-2-1": three independent copies on different infrastructure.

### Granular exit code handling

restic uses a few specific exit codes that aren't simple binary
success/failure:

- `0` — full success
- `3` — backup completed, but some files were unreadable (snapshot still saved)
- `1`, `10`, `11`, `12` — actual failures of various kinds

A common scripting mistake is to treat anything non-zero as failure, which
turns "we backed up 99.9% of files but one was permission-denied" into "FAILED".
That's misleading and conditions you to ignore alerts.

The kit distinguishes:

- **Success** — green, no email anxiety
- **Success (some files skipped)** — orange warning, you check why but don't panic
- **Failed** — red, the snapshot didn't save, investigate now

### Cron-safe by default

Cron environments are minimal. Common scripts that work fine interactively
fail under cron because:

- `$PATH` doesn't include `/usr/local/bin` where restic and rclone often live
- `$HOME` may not be set
- Interactive prompts hang silently
- Lock files or sockets are missing

The kit handles all of these:

- `PATH` is set explicitly at the top of every script
- All paths are absolute or anchored to `$HOME` with explicit fallbacks
- No interactive prompts in `backup.sh` (only in `restore.sh` / `emergency-restore.sh`)
- `flock` prevents overlapping runs
- Tools are checked for presence before use

### Locking with `flock`

If a backup takes 8 minutes and cron tries to start a new one at the 5-minute
mark, two parallel runs would corrupt the JSON output and confuse the metrics
extraction. `flock` on a lock file ensures only one runs at a time. Concurrent
attempts log to a separate file and exit cleanly.

### Logs are first-class

The kit writes:

- A full run log (`~/.zt-backup-kit/logs/backup-<timestamp>.log`) — kept for 30 days by default
- A one-line daily summary (`backup-summary.log`) — appended forever
- A skipped-run log when locking blocks an attempt
- The full log is also attached to email reports as a base64 attachment

If you can't read the logs, you can't trust the backups. Logs persist by
default and rotate by age, not by size — predictable behavior for monitoring.

### Configuration as code, but separate from code

`config/config.example.sh` is in the repo. `config/config.sh` is git-ignored.
This is the simplest possible "credentials never end up in source control"
solution that doesn't require external dependencies (Vault, etc.).

For users with sufficient operational maturity to use a secrets manager,
nothing prevents sourcing config from elsewhere — `backup.sh --config /path/to/secrets.sh`
works as expected.

## What's *not* here yet

### Pull-mode setup

The most secure architecture for ransomware resilience is one where the
**backup vault initiates connections to the production server**, never
the other way around. Production server has no credentials for the vault.
Even with full root compromise, the attacker has no way to reach the vault
because the production side has no path *to* anything.

This kit currently ships with the simpler push-mode setup. Pull-mode
requires:

- A separate "vault" host (could be a Raspberry Pi for small deployments)
- SSH keys provisioned only on the vault, with the vault's public key on production
- Cron on the vault running `restic backup user@production:/path`
- Production has zero awareness of where its backups live

This is on the roadmap but adds operational complexity that isn't worth it
for everyone. The push-mode setup with cloud storage and immutable snapshot
versioning already raises the bar significantly above what most small
deployments have.

### Ransomware detection

A future enhancement is entropy analysis on incoming backup data: if today's
backup contents have suddenly become high-entropy (looks like encrypted gibberish),
something is wrong and the backup should pause rather than overwrite the last
clean snapshot. Restic's snapshot model means yesterday's clean backup is
preserved automatically, but explicit detection would give earlier warning.

## Threat model summary

What this kit defends against:

- ✅ Ransomware encrypting `/var/www` (yesterday's snapshot remains intact and restorable)
- ✅ Casual data loss (deleted files, corrupted databases, bad deployments)
- ✅ Hardware failure (data is encrypted off-site)
- ✅ Provider-side data loss at the cloud (use multiple TARGETS for full 3-2-1)
- ✅ Credential theft from the production server (cloud account is separate; you can rotate the OAuth token without losing the repo)

What it doesn't defend against:

- ❌ Compromise of your Google account (or whichever cloud account holds the backups)
- ❌ Loss of the restic password if you also lose the encrypted credentials archive
- ❌ Long-running, sophisticated attackers with months of dwell time who poison
  multiple snapshots before triggering ransomware (mitigated by retention
  policy keeping older snapshots, but not eliminated)
- ❌ Insider attack with full root access AND knowledge of restic password
  (no software defends against an admin gone rogue with credentials in hand)

For higher-trust environments, layer additional controls: 2FA on the cloud
account, separate paper-only restic password storage, off-site monitoring
that alerts on missing daily summary entries, etc.
