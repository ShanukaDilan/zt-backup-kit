# Disaster Recovery Runbook

This is the generic runbook template for zt-backup-kit users. Print a copy,
fill in your specifics, and store with your encrypted credentials.

## ⚠️ The Three Critical Items

Restore is **impossible** without all three. Treat them like the keys to a
safe deposit box.

| Item | What it is | Where to keep it |
|---|---|---|
| **Restic password** | The encryption key. Without it data is unreadable noise. | Sealed envelope in office safe + a copy with a trusted person off-site |
| **rclone OAuth credentials** | client_id, client_secret, and refresh_token to reach Google Drive (or whichever cloud you use) | Encrypted USB drive in safe + access to the Google account that owns the storage |
| **This document + emergency-restore.sh** | Repo path, scripts, instructions | Printed paper copy + digital copy in personal email |

> ⚠️ **Never store all three together.** If a thief or ransomware operator
> obtains all three, they can read your backups.

## Encrypting your credentials archive

Run these on the server, as the user that runs the backup:

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

# Remove unencrypted copies
rm .restic-pass rclone.conf
```

Distribute the resulting `.gpg` file:
1. USB drive in office safe
2. Personal email account (encrypted, so safe to email)
3. A second physical location

**Write the GPG passphrase on paper** and store it with this runbook.

To decrypt during recovery:

```bash
gpg --decrypt ztbk-credentials-YYYYMMDD.tar.gz.gpg | tar xzf -
```

## Three Recovery Scenarios

### Scenario A: Single file recovery

**When:** a user deleted a file. Server is healthy. You want yesterday's version back.

**Tool:** `bin/restore.sh` on the server.

**Time:** under 2 minutes for a single file.

```bash
./bin/restore.sh
# Choose: latest snapshot, mode 2 (Partial restore)
# Enter the path inside the snapshot, e.g. /var/www/html/index.php
# Default target /tmp/restore-<timestamp> is safe — won't overwrite the live file
```

After restore, verify and copy back:

```bash
diff /tmp/restore-.../var/www/html/index.php /var/www/html/index.php
# If satisfied:
cp /tmp/restore-.../var/www/html/index.php /var/www/html/index.php
```

### Scenario B: Full server rebuild

**When:** hardware failed, OS reinstalled, ransomware. You have a fresh
Linux machine ready and want to restore the website.

**Time:** approximately 15 min for a small site (depends on dataset size and bandwidth).

```bash
# 1. Install dependencies
sudo apt update
sudo apt install -y restic rclone msmtp jq gpg

# 2. Decrypt and place credentials
cd ~
gpg --decrypt /path/to/ztbk-credentials-*.tar.gz.gpg | tar xzf -
chmod 400 .restic-pass
mkdir -p .config/rclone
mv rclone.conf .config/rclone/

# 3. Verify access
export RCLONE_CONFIG=~/.config/rclone/rclone.conf
export RESTIC_PASSWORD_FILE=~/.restic-pass
export RESTIC_REPOSITORY="rclone:MyDrive:Backups/ResticRepo"
restic snapshots

# 4. Restore to a staging area
restic restore latest --target /tmp/recovery

# 5. Move into place (review first!)
sudo rsync -av /tmp/recovery/var/www/ /var/www/

# 6. Reset permissions
sudo chown -R appuser:www-data /var/www/html
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;

# 7. Restart services
sudo systemctl restart apache2  # or nginx
curl -I http://localhost/
```

### Scenario C: Emergency self-service restore

**When:** server destroyed and you're not at the office. You have a laptop,
internet, and the encrypted credentials archive.

**Time:** approximately 30 minutes including tool installation.

#### What you need

| # | Item | Where it should be |
|---|---|---|
| 1 | Any laptop (Linux, macOS, or Windows + WSL2) | With you, or borrow one |
| 2 | Internet | Home wifi, mobile hotspot, etc. |
| 3 | `ztbk-credentials-YYYYMMDD.tar.gz.gpg` | Personal email or USB drive |
| 4 | GPG passphrase for the archive | Written on paper with this runbook |
| 5 | `emergency-restore.sh` | Personal email, USB, or printed copy |

#### Procedure

1. Boot the laptop and open a terminal.
   - macOS: Cmd+Space, type "Terminal", Enter
   - Linux: Ctrl+Alt+T
   - Windows: open WSL Ubuntu (`wsl --install -d Ubuntu` if not installed)

2. Decrypt the credentials:
   ```bash
   gpg --decrypt ztbk-credentials-*.tar.gz.gpg | tar xzf -
   ls -la
   # Should show .restic-pass and rclone.conf
   ```

3. Place credentials where the script expects them:
   ```bash
   chmod 400 .restic-pass
   mv .restic-pass ~/.restic-pass
   mkdir -p ~/.config/rclone
   mv rclone.conf ~/.config/rclone/rclone.conf
   ```

4. Run the restore script:
   ```bash
   chmod +x emergency-restore.sh
   ./emergency-restore.sh
   ```

5. The script:
   - Installs `restic` and `rclone` (asks for sudo)
   - Detects your existing rclone config
   - Verifies access to the cloud
   - Lists snapshots and lets you pick one
   - Restores to `~/ztbk-restore-<date>/`

6. Once restored:
   - Browse the recovered files locally
   - Upload critical files to a temporary host if needed
   - Copy to a new server when one is available

#### Security after recovery

⚠️ On a borrowed laptop, wipe everything when done:

```bash
unset RESTIC_PASSWORD
rm -rf ~/ztbk-restore-*
rm -f ~/.restic-pass ~/.config/rclone/rclone.conf
# Also clear browser history (the OAuth flow involves Google login)
```

#### Emergency contacts

| Role | Name | Phone / Email |
|---|---|---|
| Primary | (your name) | (your contact) |
| Secondary | (deputy) | (their contact) |
| Provider support | (cloud provider) | (their support URL) |

## Testing the recovery (do this quarterly)

A backup you've never restored is not a backup — it's a hope. Test once
every 3 months.

### Quick test (5 minutes)

```bash
./bin/restore.sh
# Choose mode 4 (List contents) — verify file count looks right

./bin/restore.sh
# Choose mode 1 (Full restore) to /tmp/restore-test
# Verify some random files match originals:
diff /tmp/restore-test/var/www/html/index.html /var/www/html/index.html

rm -rf /tmp/restore-test
```

### Full test (30 minutes, do annually)

1. Spin up a fresh VM (VirtualBox / cloud)
2. Run `emergency-restore.sh` from your printed runbook
3. Verify the restored site can serve pages
4. Document any steps that didn't work
5. Update this runbook with the corrections

## Trust chain — who has what

| Role | Person | What they have |
|---|---|---|
| Primary | (you) | Server access, restic password, OAuth (everything) |
| Secondary | (deputy) | Encrypted credentials archive + passphrase (separate channel) |
| Tertiary | (off-site trusted person) | Sealed envelope with restic password only |

⚠️ **No single person except the primary should have all three items.**

## After a successful restore

1. **Spot-check the restored data.** Don't trust it blindly.
2. **Investigate the original cause.** If ransomware, do not connect the new
   server to the same network until you've identified the entry point.
3. **Generate a new restic password** for the new repository. The old one is
   potentially compromised.
4. **Update this runbook** with new credentials path and any deviations.
5. **Re-deploy `backup.sh`** so the new server starts protecting itself.
6. **Schedule the next quarterly DR test** on your calendar.

## Quick command reference

```bash
# Set environment
export RCLONE_CONFIG=~/.config/rclone/rclone.conf
export RESTIC_PASSWORD_FILE=~/.restic-pass
export RESTIC_REPOSITORY="rclone:MyDrive:Backups/ResticRepo"

# Browse
restic snapshots                       # list all
restic stats                           # logical size + dedup ratio
restic stats --mode raw-data           # actual bytes on remote
restic ls latest                       # files in latest snapshot
restic find /var/www/html/x.php        # every version of a file

# Restore
restic restore latest --target /tmp/restore
restic restore <id> --target /tmp/restore --include /var/www/html/x.php

# Mount
mkdir /tmp/mnt
restic mount /tmp/mnt
# Browse: cd /tmp/mnt/snapshots/latest
# Unmount: Ctrl+C

# Verify
restic check                           # metadata
restic check --read-data-subset=10%    # also 10% of data chunks

# Destructive (be careful)
restic forget <snapshot-id>            # marks for deletion
restic prune                           # actually deletes
```
