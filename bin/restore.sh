#!/bin/bash
set -u

# ==============================================================================
#  zt-backup-kit :: restore.sh
# ------------------------------------------------------------------------------
#  Interactive restore tool for the configured backup repository.
#
#  Modes:
#    1) Full restore  — restore everything to a folder
#    2) Partial restore — pick specific file(s) or directory
#    3) Mount snapshot — browse it as a read-only filesystem
#    4) List contents — print files inside a snapshot
#
#  Usage:
#    restore.sh                         # interactive
#    restore.sh --target NAME           # use the named target from config
#    restore.sh --config PATH           # use a different config file
#
#  By default the first target in config.sh is used.
# ==============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_ROOT}/config/config.sh"
TARGET_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config) CONFIG_FILE="$2"; shift 2 ;;
        --target) TARGET_NAME="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 2
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"

# Pick the target to restore from
TARGET_REPO=""
TARGET_DISPLAY=""
for t in "${TARGETS[@]}"; do
    IFS='|' read -r NAME REPO _ <<< "$t"
    if [[ -z "$TARGET_NAME" ]]; then
        TARGET_REPO="$REPO"
        TARGET_DISPLAY="$NAME"
        break
    elif [[ "$NAME" == "$TARGET_NAME" ]]; then
        TARGET_REPO="$REPO"
        TARGET_DISPLAY="$NAME"
        break
    fi
done

if [[ -z "$TARGET_REPO" ]]; then
    echo "❌ No matching target found."
    echo "   Available targets:"
    for t in "${TARGETS[@]}"; do
        IFS='|' read -r NAME _ _ <<< "$t"
        echo "     - $NAME"
    done
    exit 3
fi

export RESTIC_REPOSITORY="$TARGET_REPO"

echo "═══════════════════════════════════════════════════════════════"
echo "  🔄  zt-backup-kit Restore Tool"
echo "═══════════════════════════════════════════════════════════════"
echo "  Target: $TARGET_DISPLAY"
echo "  Repo:   $TARGET_REPO"
echo ""

if [[ ! -r "$RESTIC_PASSWORD_FILE" ]]; then
    echo "❌ Password file not readable: $RESTIC_PASSWORD_FILE"
    exit 4
fi

echo "📡 Connecting to repository..."
if ! restic snapshots --compact >/dev/null 2>&1; then
    echo "❌ Cannot reach the repository. Check internet/credentials."
    exit 5
fi
echo "✅ Repository accessible."
echo ""

# List snapshots
echo "═══════════════════════════════════════════════════════════════"
echo "  📋  Available Snapshots"
echo "═══════════════════════════════════════════════════════════════"
restic snapshots --compact
echo ""

# Pick a snapshot
read -rp "Enter snapshot ID (or 'latest'): " SNAPSHOT_ID
SNAPSHOT_ID="${SNAPSHOT_ID:-latest}"

if ! restic snapshots "$SNAPSHOT_ID" >/dev/null 2>&1; then
    echo "❌ Snapshot '$SNAPSHOT_ID' not found."
    exit 6
fi
echo "✅ Selected snapshot: $SNAPSHOT_ID"
echo ""

# Pick mode
echo "═══════════════════════════════════════════════════════════════"
echo "  🎯  What would you like to do?"
echo "═══════════════════════════════════════════════════════════════"
echo "  1) Full restore  — Restore everything to a folder"
echo "  2) Partial restore — Restore specific file(s) or directory"
echo "  3) Mount snapshot — Browse it as read-only filesystem"
echo "  4) List contents — Just show what's in the snapshot"
echo "  5) Quit"
echo ""
read -rp "Choose [1-5]: " MODE
echo ""

case "$MODE" in
    1)
        DEFAULT_TARGET="/tmp/restore-$(date +%Y%m%d-%H%M%S)"
        read -rp "Restore target folder [default: $DEFAULT_TARGET]: " TGT
        TGT="${TGT:-$DEFAULT_TARGET}"

        echo ""
        echo "⚠️  Restoring snapshot $SNAPSHOT_ID → $TGT"
        if [[ -d "$TGT" && -n "$(ls -A "$TGT" 2>/dev/null)" ]]; then
            echo "⚠️  Target exists and is NOT empty — files may be overwritten."
        fi
        read -rp "Continue? [y/N]: " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "Aborted."
            exit 0
        fi

        mkdir -p "$TGT"
        echo "📥 Restoring..."
        if restic restore "$SNAPSHOT_ID" --target "$TGT"; then
            echo ""
            echo "✅ Restore complete!"
            echo "   Files at: $TGT"
            echo ""
            echo "   Inspect:    ls -la $TGT"
        else
            echo "❌ Restore failed."
            exit 7
        fi
        ;;

    2)
        echo "Tip: paths inside the snapshot start at the same paths as on the original system."
        echo "     Use 'restic ls $SNAPSHOT_ID' first if you need to browse."
        echo ""
        read -rp "Path to restore: " PATH_IN
        if [[ -z "$PATH_IN" ]]; then
            echo "❌ No path given."
            exit 1
        fi

        DEFAULT_TARGET="/tmp/restore-$(date +%Y%m%d-%H%M%S)"
        read -rp "Restore target folder [default: $DEFAULT_TARGET]: " TGT
        TGT="${TGT:-$DEFAULT_TARGET}"

        echo ""
        echo "⚠️  Restoring '$PATH_IN' from $SNAPSHOT_ID → $TGT"
        read -rp "Continue? [y/N]: " CONFIRM
        if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
            echo "Aborted."
            exit 0
        fi

        mkdir -p "$TGT"
        echo "📥 Restoring..."
        if restic restore "$SNAPSHOT_ID" --target "$TGT" --include "$PATH_IN"; then
            echo "✅ Restore complete! Files at: $TGT$PATH_IN"
        else
            echo "❌ Restore failed."
            exit 7
        fi
        ;;

    3)
        if ! command -v fusermount >/dev/null 2>&1 && ! command -v fusermount3 >/dev/null 2>&1; then
            echo "❌ FUSE not installed. Install with: sudo apt install fuse"
            exit 1
        fi

        DEFAULT_MOUNT="/tmp/ztbk-mount-$(date +%H%M%S)"
        read -rp "Mount point [default: $DEFAULT_MOUNT]: " MOUNT_POINT
        MOUNT_POINT="${MOUNT_POINT:-$DEFAULT_MOUNT}"

        mkdir -p "$MOUNT_POINT"
        echo ""
        echo "🔗 Mounting snapshot $SNAPSHOT_ID at $MOUNT_POINT (read-only)"
        echo ""
        echo "   Browse in another terminal:"
        echo "      cd $MOUNT_POINT/snapshots/$SNAPSHOT_ID"
        echo ""
        echo "   When done, press Ctrl+C in THIS terminal to unmount."
        echo ""
        restic mount "$MOUNT_POINT"
        ;;

    4)
        read -rp "Path filter (or Enter for everything): " FILTER
        if [[ -z "$FILTER" ]]; then
            restic ls "$SNAPSHOT_ID" | less
        else
            restic ls "$SNAPSHOT_ID" | grep -- "$FILTER" | less
        fi
        ;;

    5|q|Q)
        echo "Goodbye."
        exit 0
        ;;

    *)
        echo "❌ Invalid choice."
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Done."
echo "═══════════════════════════════════════════════════════════════"
