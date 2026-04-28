#!/bin/bash
set -u

# ==============================================================================
#  zt-backup-kit :: backup-status.sh
# ------------------------------------------------------------------------------
#  Inspect your Restic repository — show snapshots, sizes, deduplication ratio,
#  and recent run history at a glance.
#
#  Usage:
#    ./bin/backup-status.sh                # full report (default)
#    ./bin/backup-status.sh --short        # one-page summary only
#    ./bin/backup-status.sh --runs         # only the last 15 runs
#    ./bin/backup-status.sh --json         # machine-readable JSON output
#    ./bin/backup-status.sh --target NAME  # use the named target from config
#    ./bin/backup-status.sh --config PATH  # use a different config file
#
#  By default the first target in config.sh is queried.
# ==============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_ROOT}/config/config.sh"
TARGET_NAME=""
MODE="full"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --short)  MODE="short"; shift ;;
        --runs)   MODE="runs";  shift ;;
        --json)   MODE="json";  shift ;;
        --target) TARGET_NAME="$2"; shift 2 ;;
        --config) CONFIG_FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown argument: $1"
            exit 1 ;;
    esac
done

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    echo "   Copy config/config.example.sh to config/config.sh and customize it."
    exit 2
fi

# shellcheck source=/dev/null
. "$CONFIG_FILE"

# ---------------- Sanity checks ----------------
require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "❌ Required tool missing: $1"
        exit 3
    fi
}
require restic
require jq
require numfmt

if [[ ! -r "$RESTIC_PASSWORD_FILE" ]]; then
    echo "❌ Password file not readable: $RESTIC_PASSWORD_FILE"
    exit 4
fi

# Pick the target to query
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
    exit 5
fi

export RESTIC_REPOSITORY="$TARGET_REPO"
SUMMARY_LOG="${LOG_DIR:-${HOME}/.zt-backup-kit/logs}/backup-summary.log"
SCHEDULE_PATTERN="$(basename "$REPO_ROOT")/bin/backup.sh"

# ---------------- Pretty colors (only for terminals) ----------------
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    RED=$'\033[31m'
    BLUE=$'\033[34m'
    CYAN=$'\033[36m'
    NC=$'\033[0m'
else
    BOLD="" DIM="" GREEN="" YELLOW="" RED="" BLUE="" CYAN="" NC=""
fi

hr() { printf "${DIM}─%.0s${NC}" {1..70}; echo; }

# ---------------- Header ----------------
if [[ "$MODE" != "json" ]]; then
    echo ""
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo "${BOLD}${BLUE}  📊  Backup Status Report${NC}"
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo "  Target     : ${CYAN}${TARGET_DISPLAY}${NC}"
    echo "  Repository : ${CYAN}${TARGET_REPO}${NC}"
    echo "  Generated  : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  Host       : $(hostname)"
    echo "  User       : $(whoami)"
    hr
fi

# ---------------- Connectivity check ----------------
if ! restic snapshots --json >/dev/null 2>&1; then
    echo "${RED}❌ Cannot reach the repository. Check internet/credentials.${NC}"
    exit 6
fi

# ---------------- Gather data ----------------
SNAPSHOTS_JSON=$(restic snapshots --json 2>/dev/null || echo "[]")
SNAP_COUNT=$(echo "$SNAPSHOTS_JSON" | jq 'length')

STATS_RESTORE=$(restic stats latest --mode restore-size --json 2>/dev/null || echo '{}')
STATS_RAW=$(restic stats --mode raw-data --json 2>/dev/null || echo '{}')
STATS_FILES=$(restic stats latest --mode files-by-contents --json 2>/dev/null || echo '{}')

LOGICAL_BYTES=$(echo "$STATS_RESTORE" | jq -r '.total_size // 0')
RAW_BYTES=$(echo "$STATS_RAW" | jq -r '.total_size // 0')
TOTAL_FILES=$(echo "$STATS_FILES" | jq -r '.total_file_count // 0')

fmt_bytes() {
    if [[ "$1" -eq 0 ]]; then
        echo "0 B"
    else
        numfmt --to=iec --suffix=B "$1"
    fi
}

LOGICAL=$(fmt_bytes "$LOGICAL_BYTES")
RAW=$(fmt_bytes "$RAW_BYTES")

if [[ "$RAW_BYTES" -gt 0 ]]; then
    DEDUP_RATIO=$(awk "BEGIN { printf \"%.2f\", $LOGICAL_BYTES / $RAW_BYTES }")
    DEDUP_PCT=$(awk "BEGIN { printf \"%.1f\", (1 - $RAW_BYTES/$LOGICAL_BYTES) * 100 }")
else
    DEDUP_RATIO="0.00"
    DEDUP_PCT="0.0"
fi

LATEST_TIME=$(echo "$SNAPSHOTS_JSON" | jq -r '.[-1].time // "unknown"')
LATEST_PATHS=$(echo "$SNAPSHOTS_JSON" | jq -r '.[-1].paths // [] | join(", ")')
OLDEST_TIME=$(echo "$SNAPSHOTS_JSON" | jq -r '.[0].time // "unknown"')

if [[ "$LATEST_TIME" != "unknown" ]]; then
    LATEST_EPOCH=$(date -d "$LATEST_TIME" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    HOURS_AGO=$(( (NOW_EPOCH - LATEST_EPOCH) / 3600 ))
else
    HOURS_AGO=-1
fi

# ---------------- JSON mode ----------------
if [[ "$MODE" == "json" ]]; then
    cat <<EOF
{
  "target": "$TARGET_DISPLAY",
  "repository": "$TARGET_REPO",
  "generated": "$(date -Iseconds)",
  "snapshot_count": $SNAP_COUNT,
  "logical_size_bytes": $LOGICAL_BYTES,
  "raw_size_bytes": $RAW_BYTES,
  "logical_size": "$LOGICAL",
  "raw_size": "$RAW",
  "dedup_ratio": $DEDUP_RATIO,
  "dedup_savings_percent": $DEDUP_PCT,
  "total_files": $TOTAL_FILES,
  "latest_snapshot_time": "$LATEST_TIME",
  "latest_snapshot_hours_ago": $HOURS_AGO,
  "oldest_snapshot_time": "$OLDEST_TIME"
}
EOF
    exit 0
fi

# ---------------- Summary block ----------------
echo ""
echo "${BOLD}📦  Repository Summary${NC}"
echo ""
printf "  %-22s %s\n" "Total snapshots"   "${BOLD}${SNAP_COUNT}${NC}"
printf "  %-22s %s\n" "Files in latest"   "${BOLD}${TOTAL_FILES}${NC}"
printf "  %-22s %s\n" "Logical size"      "${BOLD}${LOGICAL}${NC} (sum of restored files)"
printf "  %-22s %s\n" "Stored size"       "${BOLD}${RAW}${NC} (actual bytes on remote)"
printf "  %-22s %s\n" "Dedup ratio"       "${GREEN}${DEDUP_RATIO}×${NC} (saves ${DEDUP_PCT}%)"
echo ""

if [[ "$HOURS_AGO" -lt 0 ]]; then
    echo "  ${YELLOW}⚠️  No snapshots in repository.${NC}"
elif [[ "$HOURS_AGO" -lt 24 ]]; then
    echo "  Latest snapshot   : ${GREEN}✅ ${HOURS_AGO}h ago${NC} (${LATEST_TIME%%T*})"
elif [[ "$HOURS_AGO" -lt 48 ]]; then
    echo "  Latest snapshot   : ${YELLOW}⚠️  ${HOURS_AGO}h ago${NC} (${LATEST_TIME%%T*})"
else
    echo "  Latest snapshot   : ${RED}❌ ${HOURS_AGO}h ago — STALE${NC} (${LATEST_TIME%%T*})"
fi
echo "  Oldest snapshot   : ${OLDEST_TIME%%T*}"
echo "  Source paths      : $LATEST_PATHS"
echo ""

if [[ "$MODE" == "short" ]]; then
    hr
    echo "  Run with no args for full snapshot list and run history."
    echo ""
    exit 0
fi

# ---------------- Snapshot table ----------------
if [[ "$MODE" != "runs" ]]; then
    hr
    echo ""
    echo "${BOLD}📅  Snapshot History${NC}"
    echo ""
    echo "$SNAPSHOTS_JSON" | jq -r '
        ["Date/Time","ID","Files","Size","Tags"],
        ["─────────────────────","────────","──────","──────","──────"],
        ( .[] | [
            (.time | sub("\\..*"; "") | sub("T"; " ")),
            (.short_id // (.id[0:8])),
            (.summary.total_files_processed // "—" | tostring),
            (
              if (.summary.total_bytes_processed // null) == null then "—"
              else (.summary.total_bytes_processed | (
                  if . >= 1073741824 then ((./1073741824*10|floor)/10|tostring) + " GiB"
                  elif . >= 1048576 then ((./1048576*10|floor)/10|tostring) + " MiB"
                  elif . >= 1024 then ((./1024*10|floor)/10|tostring) + " KiB"
                  else (.|tostring) + " B" end))
              end
            ),
            ((.tags // []) | join(","))
        ] )
        | @tsv
    ' | column -t -s $'\t'
    echo ""
fi

# ---------------- Recent run history ----------------
if [[ "$MODE" == "runs" || "$MODE" == "full" ]]; then
    hr
    echo ""
    echo "${BOLD}📋  Recent Backup Runs${NC} ${DIM}(from $SUMMARY_LOG)${NC}"
    echo ""
    if [[ -r "$SUMMARY_LOG" ]]; then
        tail -n 15 "$SUMMARY_LOG" | while IFS= read -r line; do
            case "$line" in
                *"Status=Success"*)  echo "  ${GREEN}✓${NC} $line" ;;
                *"Status=Warning"*)  echo "  ${YELLOW}⚠${NC}  $line" ;;
                *"FAILED"*|*"Status=Failed"*) echo "  ${RED}✗${NC} $line" ;;
                *) echo "    $line" ;;
            esac
        done
    else
        echo "  ${DIM}(no run history yet — first backup will create it)${NC}"
    fi
    echo ""

    # ---------------- Schedule check ----------------
    hr
    echo ""
    echo "${BOLD}⏰  Schedule${NC}"
    echo ""
    if crontab -l 2>/dev/null | grep -q "$SCHEDULE_PATTERN"; then
        echo "  ${GREEN}✓${NC} Cron entry installed:"
        crontab -l 2>/dev/null | grep "$SCHEDULE_PATTERN" | sed 's/^/    /'
    elif command -v systemctl >/dev/null && systemctl --user is-active --quiet zt-backup.timer 2>/dev/null; then
        echo "  ${GREEN}✓${NC} systemd timer active:"
        systemctl --user list-timers zt-backup.timer 2>/dev/null | head -2 | tail -1 | sed 's/^/    /'
    else
        echo "  ${YELLOW}⚠${NC}  No schedule found for ${SCHEDULE_PATTERN}"
        echo "     Install cron with:  crontab -e"
        echo "     Add line:           30 2 * * * ${REPO_ROOT}/bin/backup.sh"
        echo "     See examples/crontab.example for more options."
    fi
    echo ""
fi

hr
echo ""
echo "  ${DIM}Tip: 'restic snapshots' for raw output, 'restic ls latest' to browse files.${NC}"
echo ""
