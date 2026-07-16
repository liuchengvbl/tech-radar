#!/bin/bash
# Daily Scan — runs via cron, invokes opencode run in non-interactive mode
# Platform: OpenCode

set -uo pipefail  # 去掉 -e，手动检查关键步骤的退出码

export PATH="$HOME/.local/bin:$PATH"
# opencode 通过 nvm 安装时，cron 环境不加载 nvm，需手动添加 node bin 到 PATH
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

# Check dependencies
python3 -c "import yaml" 2>/dev/null || { echo "需要 pyyaml: pip3 install pyyaml" >&2; exit 1; }

DATE=$(date +%Y-%m-%d)

# Avoid duplicate runs
if [ -f "$REPORT_DIR/daily/$DATE.md" ]; then
    echo "[$DATE] Report already exists, skipping." >> "$LOG_DIR/cron.log"
    exit 0
fi

mkdir -p "$REPORT_DIR/daily"

# Extract budget mode from scan-config
BUDGET_MODE=$(python3 -c "import yaml; print(yaml.safe_load(open('$SCAN_CONFIG'))['budget']['mode'])")

# Load prompt template from core/ and substitute variables
# Note: agent prompt is NOT concatenated — opencode loads it from the agent definition file
PROMPT=$(sed \
    -e "s|\${DATE}|$DATE|g" \
    -e "s|\${REPORT_DIR}|$REPORT_DIR|g" \
    -e "s|\${SCAN_CONFIG}|$SCAN_CONFIG|g" \
    -e "s|\${BUDGET_MODE}|$BUDGET_MODE|g" \
    "$RADAR_HOME/core/daily.prompt.md")

echo "[$DATE] Starting daily scan (budget=$BUDGET_MODE, model=$MODEL_DAILY)..." >> "$LOG_DIR/cron.log"

# Record environment for debugging cron issues
echo "=== $(date) ===" > "$LOG_DIR/$DATE.env.log"
echo "PATH=$PATH" >> "$LOG_DIR/$DATE.env.log"
echo "HOME=$HOME" >> "$LOG_DIR/$DATE.env.log"
echo "SHELL=$SHELL" >> "$LOG_DIR/$DATE.env.log"
which opencode >> "$LOG_DIR/$DATE.env.log" 2>&1
which python3 >> "$LOG_DIR/$DATE.env.log" 2>&1

run_agent() {
    cd "$RADAR_HOME"
    timeout $TIMEOUT_DAILY opencode run \
        --model "$MODEL_DAILY" \
        --agent "$AGENT_NAME" \
        --auto \
        "$PROMPT" \
        >> "$LOG_DIR/$DATE.log" 2>&1
    return $?
}

# opencode may exit 0 but not generate output files
verify_output() {
    [ -f "$REPORT_DIR/daily/$DATE.md" ] && [ -f "$REPORT_DIR/daily/$DATE.items.yaml" ]
}

run_agent
EXIT_CODE=$?

attempt=1
if [ $EXIT_CODE -eq 0 ] && verify_output; then
    echo "[$DATE] Completed successfully." >> "$LOG_DIR/cron.log"
else
    [ $EXIT_CODE -eq 0 ] && ! verify_output && echo "[$DATE] Agent exited 0 but output missing, treating as failure." >> "$LOG_DIR/cron.log"

    max_attempts=5
    while [ $attempt -lt $max_attempts ]; do
        attempt=$((attempt + 1))
        echo "[$DATE] Attempt $((attempt-1)) failed (exit=$EXIT_CODE), retrying ($attempt/$max_attempts) in 60s..." >> "$LOG_DIR/cron.log"
        sleep 60
        rm -f "$REPORT_DIR/daily/$DATE.md" "$REPORT_DIR/daily/$DATE.items.yaml"
        run_agent
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ] && verify_output; then
            echo "[$DATE] Attempt $attempt succeeded." >> "$LOG_DIR/cron.log"
            break
        fi
    done

    if ! verify_output; then
        [ $EXIT_CODE -eq 0 ] && echo "[$DATE] Final attempt exited 0 but output missing." >> "$LOG_DIR/cron.log"
        echo "[$DATE] All $max_attempts attempts failed." >> "$LOG_DIR/cron.log"
    fi
fi

# Log rotation: delete logs older than 30 days
find "$LOG_DIR" -name "*.log" -not -name "cron.log" -mtime +30 -delete
