# Installation Guide

This guide walks you through a full setup of zt-backup-kit on a fresh server.
It assumes you have shell access to the machine and `sudo` privileges for
installing packages.

## 1. Prerequisites

You need a Linux box (Debian/Ubuntu, Fedora, RHEL, Arch — anything modern).
macOS works for `restore.sh` and `emergency-restore.sh` if you're recovering
on a Mac. The backup runs are tested on Linux.

Required packages:

| Package | Used for |
|---|---|
| `restic` | core backup engine |
| `rclone` | cloud target backend (Google Drive, B2, S3, etc.) |
| `jq` | parsing Restic's JSON output |
| `flock` (`util-linux`) | preventing overlapping cron runs |
| `coreutils` (`numfmt`, `base64`) | report formatting |
| `msmtp` | sending email reports (optional but recommended) |
| `gpg` | encrypting the credentials archive |

Install on Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y restic rclone jq msmtp gpg util-linux coreutils
```

Install on Fedora/RHEL:

```bash
sudo dnf install -y restic rclone jq msmtp gnupg2 util-linux coreutils
```

## 2. Pick (or create) a dedicated user

Best practice: don't run backups as root. Create a low-privilege user that
has *read* access to the directories you want to back up.

```bash
sudo useradd -m -s /bin/bash backup
# Add to relevant groups so backup can read your web/app data
sudo usermod -aG www-data backup
```

The rest of this guide assumes you're operating as that user.

## 3. Clone and configure the kit

```bash
cd ~
git clone https://github.com/ShanukaDilan/zt-backup-kit.git
cd zt-backup-kit
cp config/config.example.sh config/config.sh
chmod 600 config/config.sh
```

Edit `config/config.sh`:

- `SRC_PATHS_RAW` — colon-separated list of directories to back up
- `HOST_TAG` — short identifier shown in email subjects
- `EMAILS` — comma-separated recipients (or empty to skip email)
- `TARGETS` — see Section 5

## 4. Set the encryption password

This is the key that protects all your backup data. **Without it, your
backups are permanently unrecoverable.** Treat it like a safe combination.

```bash
# Generate a strong random password (or pick your own — make it long)
openssl rand -base64 32 > ~/.restic-pass
chmod 400 ~/.restic-pass

# Now write the password somewhere safe (sealed envelope, password manager,
# etc.) — you cannot recover backups without it.
cat ~/.restic-pass
```

## 5. Choose and configure a backup target

Restic supports many backends. Pick one (or several) for your `TARGETS` array.

### Option A: Google Drive (via rclone)

```bash
rclone config
# Type 'n' for new remote
# Name: MyDrive
# Type: drive
# Use 'Edit advanced config: n', then 'Use auto config: y' (or N if SSH-only)
# Authorize in your browser
# Configure as Shared Drive: n
```

Then in `config/config.sh`:

```bash
TARGETS=(
  "Google Drive|rclone:MyDrive:Backups/ResticRepo|no"
)
```

> **Recommended next step:** create your own Google Cloud OAuth project to
> avoid hitting the shared rclone client's rate limits. See
> [Section 8](#8-recommended-create-your-own-google-cloud-oauth-project) below.

### Option B: Backblaze B2 (native, fastest for B2)

```bash
# Get your account ID and application key from B2 web console
# Add to config.sh BEFORE the TARGETS line:
export B2_ACCOUNT_ID="your-account-id"
export B2_ACCOUNT_KEY="your-application-key"

TARGETS=(
  "Backblaze B2|b2:my-bucket:restic|no"
)
```

### Option C: AWS S3 / S3-compatible (Wasabi, MinIO, etc.)

```bash
# In config.sh:
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

TARGETS=(
  "AWS S3|s3:s3.amazonaws.com/my-bucket/restic|no"
  # or for Wasabi:
  # "Wasabi|s3:s3.us-east-1.wasabisys.com/my-bucket/restic|no"
)
```

### Option D: Local NAS over SFTP

```bash
# Generate an SSH key just for this purpose
ssh-keygen -t ed25519 -f ~/.ssh/id_backup -N ""
ssh-copy-id -i ~/.ssh/id_backup.pub user@nas-host

# In config.sh:
NAS_KEY="${HOME}/.ssh/id_backup"
TARGETS=(
  "Local NAS|sftp:user@nas-host:/volume1/Backups/ResticRepo|yes"
)
```

### Option E: Local disk (mounted external drive)

```bash
TARGETS=(
  "External disk|/mnt/backup-disk/restic|no"
)
```

## 6. Set up email notifications (optional)

If you set `EMAILS=` in `config.sh`, you also need msmtp configured:

```bash
nano ~/.msmtprc
```

Example for Gmail with an app password:

```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           you@gmail.com
user           you@gmail.com
password       your-app-password

account default : gmail
```

```bash
chmod 600 ~/.msmtprc
echo "Test message" | msmtp -a default you@example.com
```

## 7. Validate and run

```bash
# Validate the config
./bin/backup.sh --check

# Dry-run to see what would happen
./bin/backup.sh --dry-run

# Real first run
./bin/backup.sh
```

Watch the output. If everything works, you'll see `✅ Backup Success` and
(if email is configured) get a styled HTML report in your inbox.

## 8. Recommended: create your own Google Cloud OAuth project

If you're using Google Drive, the default rclone OAuth credentials are
shared with every other rclone user worldwide. Heavy usage can hit Google's
per-project rate limits and your backups will fail with HTTP 403 errors.

The fix is to create your own private OAuth project. It's free and takes
about 15 minutes.

1. Go to https://console.cloud.google.com/
2. Create a new project (any name)
3. APIs & Services → Library → enable "Google Drive API"
4. APIs & Services → OAuth consent screen → External → fill in basics → add
   your own Google account as a test user
5. APIs & Services → Credentials → Create OAuth client ID → Desktop app
6. Copy the Client ID and Client Secret
7. Run `rclone config`, edit your remote, paste the new Client ID and Secret
   when prompted, refresh the token

After this, you have your own private quota and rate-limit issues effectively
disappear for solo use.

## 9. Schedule with cron

```bash
crontab -e
```

Add a line like:

```cron
# Daily backup at 02:30
30 2 * * * /home/backup/zt-backup-kit/bin/backup.sh

# Or hourly:
# 5 * * * * /home/backup/zt-backup-kit/bin/backup.sh
```

Verify with `crontab -l`.

## 10. Back up the credentials!

This step is critical and often skipped.

```bash
mkdir -p ~/dr-credentials
cp ~/.restic-pass ~/dr-credentials/
cp ~/.config/rclone/rclone.conf ~/dr-credentials/
cd ~/dr-credentials

export GPG_TTY=$(tty)
tar czf - .restic-pass rclone.conf | \
  gpg --symmetric --cipher-algo AES256 \
      --output ztbk-credentials-$(date +%Y%m%d).tar.gz.gpg

# Verify
gpg --decrypt ztbk-credentials-*.gpg | tar tzf -

# Remove unencrypted copies (originals stay in their normal locations)
rm .restic-pass rclone.conf
```

Now copy `ztbk-credentials-YYYYMMDD.tar.gz.gpg` somewhere off the server:

- USB drive in a safe
- Personal email (encrypted, so safe to email)
- Another physical location

**Write the GPG passphrase on paper** and store it with the runbook.

You're done. The kit will run daily via cron and you have a tested recovery
path documented in `docs/DR-RUNBOOK.md`.
