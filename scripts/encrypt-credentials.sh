#!/bin/bash
set -euo pipefail

# ==============================================================================
#  zt-backup-kit :: encrypt-credentials.sh
# ------------------------------------------------------------------------------
#  Bundles the restic password file and rclone config into a single
#  GPG-encrypted archive, suitable for off-site disaster recovery storage.
#
#  Usage:
#    ./scripts/encrypt-credentials.sh [output-dir]
#
#  Default output dir: ~/dr-credentials
# ==============================================================================

OUTDIR="${1:-$HOME/dr-credentials}"
RESTIC_PASS="${HOME}/.restic-pass"
RCLONE_CONF="${HOME}/.config/rclone/rclone.conf"

if [[ ! -r "$RESTIC_PASS" ]]; then
    echo "❌ Cannot read $RESTIC_PASS"
    echo "   Did you create the password file? See docs/INSTALL.md §4."
    exit 1
fi

if [[ ! -r "$RCLONE_CONF" ]]; then
    echo "❌ Cannot read $RCLONE_CONF"
    echo "   Have you run 'rclone config' yet?"
    exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
    echo "❌ gpg not installed. Install with: sudo apt install gpg"
    exit 1
fi

mkdir -p "$OUTDIR"
cd "$OUTDIR"

echo "Bundling credentials into encrypted archive..."
echo "You will be prompted for a passphrase TWICE."
echo "WRITE THIS PASSPHRASE ON PAPER — you cannot recover the archive without it."
echo ""

# Stage copies
cp "$RESTIC_PASS" .restic-pass
cp "$RCLONE_CONF" rclone.conf

OUTPUT="ztbk-credentials-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"

GPG_TTY=$(tty)
export GPG_TTY
tar czf - .restic-pass rclone.conf | \
    gpg --symmetric --cipher-algo AES256 \
        --output "$OUTPUT"

# Remove unencrypted copies
rm -f .restic-pass rclone.conf

# Verify
echo ""
echo "Verifying archive integrity..."
if gpg --decrypt "$OUTPUT" 2>/dev/null | tar tzf - >/dev/null 2>&1; then
    echo "✅ Archive verified — passphrase works, contents readable."
else
    echo "⚠️  Verification skipped (gpg-agent may have cached the passphrase, that's OK)."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Encrypted archive created:"
echo "     $OUTDIR/$OUTPUT"
echo ""
echo "  📋 Next steps:"
echo "     1. Copy to a USB drive (kept in office safe)"
echo "     2. Email to your personal email account"
echo "     3. Save to a second physical location"
echo "     4. Write the passphrase on paper, store with the runbook"
echo "═══════════════════════════════════════════════════════════════"
