#!/bin/bash
set -u

# ==============================================================================
#  zt-backup-kit :: tests/test-roundtrip.sh
# ------------------------------------------------------------------------------
#  Smoke test: backup → snapshot → restore → diff
#
#  Uses a temporary local restic repo. Does NOT touch any cloud target.
#  Safe to run on any machine with restic installed.
# ==============================================================================

set -e

TMPDIR=$(mktemp -d -t ztbk-test-XXXXXX)
SRC="$TMPDIR/src"
REPO="$TMPDIR/repo"
RESTORE="$TMPDIR/restore"
PASS_FILE="$TMPDIR/pass"

cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

echo "🧪 zt-backup-kit smoke test"
echo "Tempdir: $TMPDIR"
echo ""

# 1. Set up source data
echo "→ Creating test source data..."
mkdir -p "$SRC/subdir"
echo "Hello, world." > "$SRC/file1.txt"
echo "More content." > "$SRC/file2.txt"
dd if=/dev/urandom of="$SRC/random.bin" bs=1024 count=100 2>/dev/null
echo "Nested." > "$SRC/subdir/nested.txt"

# 2. Set up restic repo
echo "→ Initialising restic repo..."
echo "test-password-$$" > "$PASS_FILE"
chmod 400 "$PASS_FILE"

export RESTIC_PASSWORD_FILE="$PASS_FILE"
export RESTIC_REPOSITORY="$REPO"

restic init >/dev/null

# 3. Run backup
echo "→ Backing up source..."
restic backup "$SRC" --tag test --quiet

# 4. List snapshots
echo "→ Listing snapshots..."
restic snapshots --compact

# 5. Restore
echo "→ Restoring latest snapshot..."
mkdir -p "$RESTORE"
restic restore latest --target "$RESTORE" --quiet

# 6. Verify
echo "→ Verifying restored files..."
RESTORED_SRC="$RESTORE$SRC"
FAIL=0
for f in file1.txt file2.txt random.bin subdir/nested.txt; do
    if ! cmp -s "$SRC/$f" "$RESTORED_SRC/$f"; then
        echo "❌ Mismatch: $f"
        FAIL=1
    else
        echo "  ✓ $f"
    fi
done

# 7. Repository check
echo "→ Running 'restic check'..."
if restic check --quiet; then
    echo "  ✓ Repository integrity OK"
else
    echo "❌ Repository check failed"
    FAIL=1
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "═══════════════════════════════════════════════════════════════"
    echo "  ✅  All tests passed."
    echo "═══════════════════════════════════════════════════════════════"
    exit 0
else
    echo "═══════════════════════════════════════════════════════════════"
    echo "  ❌  Tests FAILED."
    echo "═══════════════════════════════════════════════════════════════"
    exit 1
fi
