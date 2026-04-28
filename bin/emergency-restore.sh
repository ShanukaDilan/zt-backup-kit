#!/bin/bash
set -u

# ==============================================================================
#  zt-backup-kit :: emergency-restore.sh
# ------------------------------------------------------------------------------
#  Bootstrap recovery on a clean Linux/macOS machine when the production
#  server is unavailable. This script:
#
#    1. Installs restic + rclone if missing
#    2. Walks you through reconfiguring rclone (or uses an existing config)
#    3. Verifies access to the configured backup repository
#    4. Restores the snapshot of your choice to a folder in $HOME
#
#  Required to run this:
#    - The restic password (from your sealed credentials envelope)
#    - Either a pre-configured rclone.conf at ~/.config/rclone/rclone.conf
#      OR your OAuth client_id/secret to set up rclone interactively
#
#  Tested on: Ubuntu 22.04+, Debian 11+, macOS 13+, WSL2
# ==============================================================================

# Edit this line to point at your repository if the credentials don't already
# specify it. Format: "rclone:REMOTE:PATH" or "s3:..." or "sftp:..." etc.
DEFAULT_REPO="${RESTIC_REPOSITORY:-}"

cat <<'BANNER'
╔═══════════════════════════════════════════════════════════════╗
║       🚨  zt-backup-kit  —  EMERGENCY RESTORE TOOL             ║
║                                                               ║
║   Use this when the production server is unreachable and     ║
║   you need to recover data from cloud backup on a clean      ║
║   machine.                                                    ║
╚═══════════════════════════════════════════════════════════════╝

BANNER

# ---------------- Detect OS ----------------
OS_TYPE="unknown"
PKG_MGR=""
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    if command -v apt-get >/dev/null; then PKG_MGR="apt"
    elif command -v dnf >/dev/null; then PKG_MGR="dnf"
    elif command -v yum >/dev/null; then PKG_MGR="yum"
    elif command -v pacman >/dev/null; then PKG_MGR="pacman"
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="mac"
fi

echo "Detected OS: $OS_TYPE   Package manager: ${PKG_MGR:-(none)}"
echo ""

install_tool() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✅ $tool already installed"
        return 0
    fi
    echo "⏳ Installing $tool..."
    case "$OS_TYPE" in
        linux)
            case "$PKG_MGR" in
                apt) sudo apt-get update -qq && sudo apt-get install -y "$tool" ;;
                dnf) sudo dnf install -y "$tool" ;;
                yum) sudo yum install -y "$tool" ;;
                pacman) sudo pacman -S --noconfirm "$tool" ;;
                *) echo "❌ Unknown package manager. Install $tool manually."; return 1 ;;
            esac
            ;;
        mac)
            if ! command -v brew >/dev/null; then
                echo "❌ Install Homebrew first: https://brew.sh"
                return 1
            fi
            brew install "$tool"
            ;;
        *)
            echo "❌ Unsupported OS. Install $tool manually:"
            echo "   restic: https://github.com/restic/restic/releases"
            echo "   rclone: https://rclone.org/downloads/"
            return 1
            ;;
    esac
}

# ---------------- Step 1: tools ----------------
echo "Step 1/4: Checking required tools..."
echo "─────────────────────────────────────"
install_tool restic || exit 1
install_tool rclone || exit 1
install_tool gpg    || true
install_tool jq     || true
echo ""

# ---------------- Step 2: rclone config ----------------
echo "Step 2/4: rclone configuration"
echo "─────────────────────────────────────"

RCLONE_CONFIG_FILE="$(rclone config file 2>/dev/null | tail -n1)"
echo "rclone config: $RCLONE_CONFIG_FILE"

if [[ -f "$RCLONE_CONFIG_FILE" ]] && rclone listremotes 2>/dev/null | grep -q .; then
    echo "✅ rclone config already present with at least one remote."
    rclone listremotes
else
    echo ""
    echo "No rclone remotes found. Run 'rclone config' to set up your cloud target."
    echo "When prompted:"
    echo "   - Type: drive (Google Drive), s3 (AWS), b2 (Backblaze), sftp, etc."
    echo "   - Use your saved client_id and client_secret"
    echo "   - For 'auto config' answer Y if you have a browser, N if SSH-only"
    echo ""
    read -rp "Press Enter to launch rclone config..."
    rclone config
fi

# ---------------- Step 3: restic credentials ----------------
echo ""
echo "Step 3/4: Restic credentials"
echo "─────────────────────────────────────"

if [[ -r "${HOME}/.restic-pass" ]]; then
    echo "✅ Found ${HOME}/.restic-pass — using it."
    export RESTIC_PASSWORD_FILE="${HOME}/.restic-pass"
else
    echo "Enter the restic repository password (will not be shown):"
    read -rsp "Password: " RESTIC_PASSWORD
    echo ""
    export RESTIC_PASSWORD
fi

if [[ -z "$DEFAULT_REPO" ]]; then
    echo ""
    echo "Enter the restic repository path."
    echo "Examples:"
    echo "  rclone:MyDrive:Backups/ResticRepo"
    echo "  s3:s3.amazonaws.com/my-bucket/restic"
    echo "  sftp:user@host:/path/to/repo"
    read -rp "Repository: " DEFAULT_REPO
fi
export RESTIC_REPOSITORY="$DEFAULT_REPO"

echo ""
echo "🔍 Testing repository access..."
if ! restic snapshots --compact >/dev/null 2>&1; then
    echo "❌ Cannot open repository. Wrong password, or repo path differs."
    echo "   Repo: $RESTIC_REPOSITORY"
    exit 2
fi
echo "✅ Repository unlocked."
echo ""

# ---------------- Step 4: restore ----------------
echo "Step 4/4: Choose what to restore"
echo "─────────────────────────────────────"
echo ""
echo "Available snapshots:"
restic snapshots --compact
echo ""

read -rp "Snapshot ID to restore [default: latest]: " SNAPSHOT_ID
SNAPSHOT_ID="${SNAPSHOT_ID:-latest}"

DEFAULT_TARGET="${HOME}/ztbk-restore-$(date +%Y%m%d-%H%M%S)"
read -rp "Restore target folder [default: $DEFAULT_TARGET]: " TGT
TGT="${TGT:-$DEFAULT_TARGET}"

read -rp "Restore everything, or a specific path? [all/specific]: " SCOPE
SCOPE="${SCOPE:-all}"

mkdir -p "$TGT"
echo ""
echo "📥 Restoring..."
echo ""

if [[ "$SCOPE" == "specific" ]]; then
    read -rp "Path inside snapshot to restore: " SUBPATH
    restic restore "$SNAPSHOT_ID" --target "$TGT" --include "$SUBPATH"
else
    restic restore "$SNAPSHOT_ID" --target "$TGT"
fi

RESULT=$?
echo ""
if [[ $RESULT -eq 0 ]]; then
    cat <<DONE
╔═══════════════════════════════════════════════════════════════╗
║                  ✅  RESTORE COMPLETE                          ║
╚═══════════════════════════════════════════════════════════════╝

Restored to: $TGT

To inspect:
   ls -la "$TGT"

Disk usage:
   du -sh "$TGT"

🔒 Security reminder:
   - On a borrowed/shared device, wipe credentials and restored data
     when no longer needed:
       unset RESTIC_PASSWORD
       rm -rf "$TGT"
       rm -f ~/.restic-pass
DONE
else
    echo "❌ Restore failed."
    exit 3
fi
