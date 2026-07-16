#!/bin/bash
# Monthly Deep Analysis — trend report with maturity assessment
# Platform: Claude Code

set -uo pipefail  # 去掉 -e，手动检查退出码

export PATH="$HOME/.local/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
    _NODE_VER=$(ls "$HOME/.nvm/versions/node" | sort -V | tail -1)
    export PATH="$HOME/.nvm/versions/node/$_NODE_VER/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RADAR_HOME="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$RADAR_HOME/logs"

if [ -z "${1:-}" ]; then
    echo "用法: $0 <instance_dir>" >&2; exit 1
fi
INSTANCE_DIR="$1"
SCAN_CONFIG="$INSTANCE_DIR/scan-config.yaml"

source "$INSTANCE_DIR/instance.env"

MONTH=$(date +%Y-%m)
MONTH_END=$(date +%Y-%m-%d)
MONTH_START=$(date -d "$MONTH_END -1 month +1 day" +%Y-%m-%d)
LAST_MONTH=$(date -d "$MONTH_START -1 day" +%Y-%m)

mkdir -p "$REPORT_DIR/monthly"

if [ -f "$REPORT_DIR/monthly/$MONTH.md" ]; then
    echo "[$MONTH_END] Monthly $MONTH already exists, skipping." >> "$LOG_DIR/cron.log"
    exit 0
fi

# Load prompt template from core/ and substitute variables
PROMPT=$(sed \
    -e "s|\${MONTH}|$MONTH|g" \
    -e "s|\${MONTH_END}|$MONTH_END|g" \
    -e "s|\${MONTH_START}|$MONTH_START|g" \
    -e "s|\${LAST_MONTH}|$LAST_MONTH|g" \
    -e "s|\${REPORT_DIR}|$REPORT_DIR|g" \
    -e "s|\${SCAN_CONFIG}|$SCAN_CONFIG|g" \
    "$RADAR_HOME/core/monthly.prompt.md")

echo "[$MONTH_END] Starting monthly analysis $MONTH..." >> "$LOG_DIR/cron.log"

run_agent() {
    cd "$RADAR_HOME"
    timeout $TIMEOUT_MONTHLY claude --print \
        --agent "$AGENT_NAME" --model "$MODEL_MONTHLY" \
        "$PROMPT" \
        >> "$LOG_DIR/monthly-$MONTH.log" 2>&1
}

run_agent
EXIT_CODE=$?

verify_output() {
    [ -f "$REPORT_DIR/monthly/$MONTH.md" ]
}

attempt=1
if [ $EXIT_CODE -eq 0 ] && verify_output; then
    echo "[$MONTH_END] Monthly $MONTH completed. Please review config proposal." >> "$LOG_DIR/cron.log"
else
    max_attempts=5
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        echo "[$MONTH_END] Monthly $MONTH attempt $((attempt-1)) failed (exit=$EXIT_CODE), retrying ($attempt/$max_attempts) in 120s..." >> "$LOG_DIR/cron.log"
        sleep 120
        rm -f "$REPORT_DIR/monthly/$MONTH.md" "$REPORT_DIR/monthly/$MONTH-config-proposal.yaml"
        run_agent
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ] && verify_output; then
            echo "[$MONTH_END] Monthly $MONTH attempt $attempt succeeded." >> "$LOG_DIR/cron.log"
            break
        fi
    done
    if ! verify_output; then
        echo "[$MONTH_END] Monthly $MONTH all $max_attempts attempts failed." >> "$LOG_DIR/cron.log"
    fi
fi

# Log rotation
find "$LOG_DIR" -name "monthly-*.log" -mtime +90 -delete
