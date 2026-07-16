#!/bin/bash
# Weekly Synthesis — generate signal map from daily reports
# Platform: Kiro-CLI

set -uo pipefail  # 去掉 -e，手动检查退出码

export PATH="$HOME/.local/bin:$PATH"
# kiro-cli 通过 nvm 安装时，cron 环境不加载 nvm，需手动添加 node bin 到 PATH
if [ -d "$HOME/.nvm/versions/node" ]; then
    _NODE_VER=$(ls "$HOME/.nvm/versions/node" | sort -V | tail -1)
    export PATH="$HOME/.nvm/versions/node/$_NODE_VER/bin:$PATH"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RADAR_HOME="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$RADAR_HOME/logs"

if [ -z "${1:-}" ]; then
    echo "用法: $0 <instance_dir>" >&2
    exit 1
fi
INSTANCE_DIR="$1"
SCAN_CONFIG="$INSTANCE_DIR/scan-config.yaml"

source "$INSTANCE_DIR/instance.env"

WEEK_END=$(date +%Y-%m-%d)
WEEK_START=$(date -d "$WEEK_END - 6 days" +%Y-%m-%d)
WEEK_ID=$(date -d "$WEEK_END" +%YW%V)
LAST_WEEK=$(date -d "$WEEK_END - 7 days" +%YW%V)

mkdir -p "$REPORT_DIR/weekly"

if [ -f "$REPORT_DIR/weekly/$WEEK_ID.md" ]; then
    echo "[$WEEK_END] Weekly $WEEK_ID already exists, skipping." >> "$LOG_DIR/cron.log"
    exit 0
fi

# Load agent prompt (kiro-cli loads agent from ~/.kiro/agents/ JSON config,
# system prompt is separate, so we concatenate it with the task prompt)
AGENT_PROMPT=$(cat "$SCRIPT_DIR/agent.md")

# Load prompt template from core/ and substitute variables
PROMPT=$(sed \
    -e "s|\${WEEK_END}|$WEEK_END|g" \
    -e "s|\${WEEK_START}|$WEEK_START|g" \
    -e "s|\${WEEK_ID}|$WEEK_ID|g" \
    -e "s|\${LAST_WEEK}|$LAST_WEEK|g" \
    -e "s|\${REPORT_DIR}|$REPORT_DIR|g" \
    -e "s|\${SCAN_CONFIG}|$SCAN_CONFIG|g" \
    "$RADAR_HOME/core/weekly.prompt.md")

# Combine agent prompt + task prompt
FULL_PROMPT="$AGENT_PROMPT
---
$PROMPT"

echo "[$WEEK_END] Starting weekly synthesis $WEEK_ID..." >> "$LOG_DIR/cron.log"

run_agent() {
    cd "$RADAR_HOME"
    timeout $TIMEOUT_WEEKLY kiro-cli chat --no-interactive \
        --agent "$AGENT_NAME" --model "$MODEL_WEEKLY" \
        "$FULL_PROMPT" \
        >> "$LOG_DIR/weekly-$WEEK_ID.log" 2>&1
}

run_agent
EXIT_CODE=$?

verify_output() {
    [ -f "$REPORT_DIR/weekly/$WEEK_ID.md" ]
}

is_dispatch_failure() {
    grep -q "dispatch failure" "$LOG_DIR/weekly-$WEEK_ID.log" 2>/dev/null
}

attempt=1
if [ $EXIT_CODE -eq 0 ] && verify_output && ! is_dispatch_failure; then
    echo "[$WEEK_END] Weekly $WEEK_ID completed." >> "$LOG_DIR/cron.log"
else
    max_attempts=5
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        if is_dispatch_failure; then
            echo "[$WEEK_END] Weekly $WEEK_ID attempt $((attempt-1)) failed due to dispatch failure, retrying ($attempt/$max_attempts) in 30s..." >> "$LOG_DIR/cron.log"
            sleep 30
        else
            echo "[$WEEK_END] Weekly $WEEK_ID attempt $((attempt-1)) failed (exit=$EXIT_CODE), retrying ($attempt/$max_attempts) in 60s..." >> "$LOG_DIR/cron.log"
            sleep 60
        fi
        rm -f "$REPORT_DIR/weekly/$WEEK_ID.md"
        run_agent
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ] && verify_output && ! is_dispatch_failure; then
            echo "[$WEEK_END] Weekly $WEEK_ID attempt $attempt succeeded." >> "$LOG_DIR/cron.log"
            break
        fi
    done
    if ! verify_output; then
        echo "[$WEEK_END] Weekly $WEEK_ID all $max_attempts attempts failed." >> "$LOG_DIR/cron.log"
    fi
fi

# Log rotation
find "$LOG_DIR" -name "weekly-*.log" -mtime +60 -delete
