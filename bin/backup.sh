#!/bin/bash
set -u

# ==============================================================================
#  zt-backup-kit :: backup.sh
# ------------------------------------------------------------------------------
#  Automated Restic backup with multi-target support, encryption, deduplication,
#  retention enforcement, integrity checking, and HTML email reporting.
#
#  Usage:
#    backup.sh                    # normal run (uses config/config.sh)
#    backup.sh --config PATH      # use a different config file
#    backup.sh --check            # validate config without backing up
#    backup.sh --dry-run          # show what would happen
#
#  See README.md and docs/INSTALL.md for setup instructions.
# ==============================================================================

# Make cron-safe: ensure tools are findable when run from crontab
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ---------------- 0. Locate config ----------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_ROOT}/config/config.sh"
DRY_RUN="no"
CHECK_ONLY="no"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        --check)
            CHECK_ONLY="yes"
            shift
            ;;
        -h|--help)
            sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "❌ Config file not found or unreadable: $CONFIG_FILE"
    echo "   Copy config/config.example.sh to config/config.sh and customize it."
    exit 2
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"

# ---------------- 1. Sanity checks ----------------

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Required tool missing: $1"
        echo "   Install with: sudo apt install $1   (or your distro's equivalent)"
        exit 3
    fi
}

require restic
require flock
require jq
require numfmt
require base64

if [[ -n "${EMAILS:-}" ]]; then
    require msmtp
fi

if [[ ! -r "$RESTIC_PASSWORD_FILE" ]]; then
    echo "❌ RESTIC_PASSWORD_FILE not readable: $RESTIC_PASSWORD_FILE"
    echo "   Create with: echo 'PASSWORD' > $RESTIC_PASSWORD_FILE && chmod 400 $RESTIC_PASSWORD_FILE"
    exit 4
fi

mkdir -p "$LOG_DIR"

IFS=':' read -r -a SRC_PATHS <<< "$SRC_PATHS_RAW"
for p in "${SRC_PATHS[@]}"; do
    if [[ ! -r "$p" ]]; then
        echo "❌ Source path not readable by $(whoami): $p"
        exit 5
    fi
done

# Build restic --exclude args from EXCLUDE_PATTERNS array
EXCLUDE_ARGS=()
for pattern in "${EXCLUDE_PATTERNS[@]:-}"; do
    EXCLUDE_ARGS+=( --exclude "$pattern" )
done

if [[ "$CHECK_ONLY" == "yes" ]]; then
    echo "✅ Config is valid."
    echo "   Sources: $SRC_PATHS_RAW"
    echo "   Targets: ${#TARGETS[@]}"
    for t in "${TARGETS[@]}"; do
        IFS='|' read -r NAME REPO _ <<< "$t"
        echo "     - $NAME → $REPO"
    done
    echo "   Email recipients: ${EMAILS:-(none)}"
    echo "   Log dir: $LOG_DIR"
    exit 0
fi

# ---------------- 2. Locking ----------------

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "[$(date)] Backup already running. Skipping." >> "$SKIP_LOG"
    exit 1
fi

# ---------------- 3. Setup logging & cleanup ----------------

TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="${LOG_DIR}/backup-${TIMESTAMP}.log"
JSON_LOG="$(mktemp -t ztbk-json-XXXXXX.json)"
REPORT_FILE="$(mktemp -t ztbk-report-XXXXXX.html)"
EMAIL_MIME="$(mktemp -t ztbk-mime-XXXXXX.txt)"
DAILY_LOG="${LOG_DIR}/backup-summary.log"
BOUNDARY="====$(date +%s)==="

SSH_AGENT_STARTED="no"
cleanup() {
    if [[ "${SSH_AGENT_STARTED}" == "yes" ]]; then
        eval "$(ssh-agent -k)" >/dev/null 2>&1 || true
    fi
    rm -f "$JSON_LOG" "$REPORT_FILE" "$EMAIL_MIME"
}
trap cleanup EXIT

exec > >(tee -a "$LOG_FILE") 2>&1
echo "=== Backup Started: $START_TIME (user: $(whoami), host: $(hostname)) ==="

if [[ "$DRY_RUN" == "yes" ]]; then
    echo "🔍 DRY RUN — no data will be transferred."
fi

# ---------------- 4. SSH agent (only if needed) ----------------

NEEDS_SSH="no"
for t in "${TARGETS[@]}"; do
    case "$t" in
        *"|yes") NEEDS_SSH="yes" ;;
    esac
done
if [[ "$NEEDS_SSH" == "yes" ]]; then
    if [[ -r "$NAS_KEY" ]]; then
        eval "$(ssh-agent -s)" >/dev/null
        SSH_AGENT_STARTED="yes"
        ssh-add "$NAS_KEY" >/dev/null 2>&1 || echo "⚠️  ssh-add failed for $NAS_KEY"
    else
        echo "⚠️  NAS_KEY not readable: $NAS_KEY"
    fi
fi

# ---------------- 5. Backup loop ----------------

HTML_ROWS=""
OVERALL_STATUS="Success"

generate_html_row() {
    local name="$1" status="$2" new_files="$3" added_size="$4" duration="$5"
    local color="green"
    case "$status" in
        Success) color="green" ;;
        "Success (some files skipped)") color="orange" ;;
        *) color="red" ;;
    esac
    cat <<HTML
<tr>
  <td style='padding:8px;border:1px solid #ddd;'><b>${name}</b></td>
  <td style='padding:8px;border:1px solid #ddd;color:${color}'><b>${status}</b></td>
  <td style='padding:8px;border:1px solid #ddd;'>${new_files}</td>
  <td style='padding:8px;border:1px solid #ddd;'>${added_size}</td>
  <td style='padding:8px;border:1px solid #ddd;'>${duration} s</td>
</tr>
HTML
}

DOW=$(date +%u)

for target in "${TARGETS[@]}"; do
    IFS='|' read -r NAME REPO REQ_SSH <<< "$target"
    echo "------------------------------------------------"
    echo "🚀 Processing Target: $NAME ($REPO)"

    export RESTIC_REPOSITORY="$REPO"

    # Init repo if missing
    if ! restic snapshots >/dev/null 2>&1; then
        echo "ℹ️  Repository not found — running 'restic init'..."
        if [[ "$DRY_RUN" == "yes" ]]; then
            echo "    (dry-run: skipped)"
        elif ! restic init; then
            echo "❌ restic init failed for $NAME — skipping target."
            OVERALL_STATUS="Warning"
            HTML_ROWS+="$(generate_html_row "$NAME" "INIT FAILED" "-" "-" "0")"
            continue
        fi
    fi

    # Backup
    if [[ "$DRY_RUN" == "yes" ]]; then
        echo "🔍 Would back up: ${SRC_PATHS[*]}"
        restic backup "${SRC_PATHS[@]}" --dry-run --tag daily \
            "${EXCLUDE_ARGS[@]}" >> "$LOG_FILE" 2>&1 || true
        STATUS="Dry-run"
        FILES_NEW="-"
        BYTES_ADDED="-"
        DURATION="0"
    else
        set +e
        restic backup "${SRC_PATHS[@]}" --tag daily --json \
            "${EXCLUDE_ARGS[@]}" \
            > "$JSON_LOG" 2>> "$LOG_FILE"
        EXIT_CODE=$?
        set -u

        # Restic exit codes:
        #   0 = full success
        #   3 = some files unreadable, snapshot still saved (warning)
        #   * = real failure
        BACKUP_OK="no"
        case $EXIT_CODE in
            0)
                STATUS="Success"
                BACKUP_OK="yes"
                ;;
            3)
                STATUS="Success (some files skipped)"
                BACKUP_OK="yes"
                OVERALL_STATUS="Warning"
                ;;
            *)
                STATUS="FAILED (exit $EXIT_CODE)"
                OVERALL_STATUS="Warning"
                ;;
        esac

        if [[ "$BACKUP_OK" == "yes" ]]; then
            SUMMARY=$(grep -E '"message_type":[[:space:]]*"summary"' "$JSON_LOG" | tail -n 1)
            [[ -z "$SUMMARY" ]] && SUMMARY=$(tail -n 1 "$JSON_LOG")

            FILES_NEW=$(jq -r '.files_new // 0' <<<"$SUMMARY" 2>/dev/null || echo 0)
            BYTES_RAW=$(jq -r '.data_added // 0' <<<"$SUMMARY" 2>/dev/null || echo 0)
            BYTES_ADDED=$(numfmt --to=iec "$BYTES_RAW" 2>/dev/null || echo "$BYTES_RAW")
            DURATION=$(jq -r '.total_duration // 0' <<<"$SUMMARY" 2>/dev/null \
                       | awk '{printf "%.1f", $1}')

            echo "✅ $STATUS — New files: $FILES_NEW  Added: $BYTES_ADDED  Duration: ${DURATION}s"

            # Forget + (optionally) prune
            if [[ "$DOW" == "$PRUNE_DOW" ]]; then
                echo "🧹 Forget + Prune (weekly maintenance) ..."
                if ! restic forget \
                        --keep-daily "$KEEP_DAILY" \
                        --keep-weekly "$KEEP_WEEKLY" \
                        --keep-monthly "$KEEP_MONTHLY" \
                        --prune >> "$LOG_FILE" 2>&1; then
                    echo "⚠️  forget --prune reported errors"
                    OVERALL_STATUS="Warning"
                fi
            else
                echo "🧹 Forget (no prune today) ..."
                if ! restic forget \
                        --keep-daily "$KEEP_DAILY" \
                        --keep-weekly "$KEEP_WEEKLY" \
                        --keep-monthly "$KEEP_MONTHLY" >> "$LOG_FILE" 2>&1; then
                    echo "⚠️  forget reported errors"
                    OVERALL_STATUS="Warning"
                fi
            fi

            # Integrity check (sample)
            if [[ "$DOW" == "$CHECK_DOW" ]]; then
                echo "🔍 Verifying integrity (weekly subset check) ..."
                if ! restic check --read-data-subset=2% >> "$LOG_FILE" 2>&1; then
                    echo "⚠️  restic check reported errors"
                    OVERALL_STATUS="Warning"
                fi
            fi
        else
            FILES_NEW="-"
            BYTES_ADDED="-"
            DURATION="0"
            echo "❌ Backup Failed for $NAME (exit $EXIT_CODE)"
        fi
    fi

    HTML_ROWS+="$(generate_html_row "$NAME" "$STATUS" "$FILES_NEW" "$BYTES_ADDED" "$DURATION")"
done

END_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# ---------------- 6. Reporting ----------------

cat > "$REPORT_FILE" <<EOF
<html>
  <body style="font-family: Arial, sans-serif; color: #333;">
    <h2 style="color: #005288;">Backup Report: $HOST_TAG</h2>
    <p><b>Status:</b> $OVERALL_STATUS<br><b>Time:</b> $TIMESTAMP</p>
    <table style="border-collapse: collapse; width: 100%; max-width: 700px;">
      <tr style="background-color: #f2f2f2;">
        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Target</th>
        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Status</th>
        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Files New</th>
        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Data Added</th>
        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Duration</th>
      </tr>
      $HTML_ROWS
    </table>
    <p style="margin-top: 20px; font-size: 12px; color: #666;">
        Sources: $SRC_PATHS_RAW<br>
        Start: $START_TIME | End: $END_TIME<br>
        Log: $LOG_FILE
    </p>
    <p style="margin-top: 20px; font-size: 11px; color: #999;">
        Generated by <a href="https://github.com/ShanukaDilan/zt-backup-kit">zt-backup-kit</a>
    </p>
  </body>
</html>
EOF

# Email
if [[ -n "${EMAILS:-}" && "$DRY_RUN" == "no" ]]; then
    B64_LOG=$(base64 -w 0 "$LOG_FILE")
    cat > "$EMAIL_MIME" <<EOF
To: $EMAILS
Subject: [Backup $OVERALL_STATUS] $HOST_TAG - $TIMESTAMP
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="$BOUNDARY"

--$BOUNDARY
Content-Type: text/html; charset="UTF-8"
Content-Transfer-Encoding: 7bit

$(cat "$REPORT_FILE")

--$BOUNDARY
Content-Type: text/plain; name="backup_log.txt"
Content-Disposition: attachment; filename="backup-${TIMESTAMP}.log"
Content-Transfer-Encoding: base64

$B64_LOG

--$BOUNDARY--
EOF
    if /usr/bin/msmtp --file="$MSMTP_CONFIG" -t < "$EMAIL_MIME"; then
        echo "📧 Email sent successfully."
    else
        echo "⚠️  Email failed to send (check $MSMTP_CONFIG and msmtp logs)."
        OVERALL_STATUS="Warning"
    fi
fi

echo "[$TIMESTAMP] Status=$OVERALL_STATUS Log=$LOG_FILE" >> "$DAILY_LOG"

# Rotate detailed logs
find "$LOG_DIR" -maxdepth 1 -type f -name 'backup-*.log' \
    -mtime +"${LOG_RETENTION_DAYS:-30}" -delete 2>/dev/null || true

echo "=== Finished: $END_TIME (Status: $OVERALL_STATUS) ==="

# Exit code reflects overall outcome (useful for monitoring tools)
[[ "$OVERALL_STATUS" == "Success" ]] && exit 0 || exit 1
