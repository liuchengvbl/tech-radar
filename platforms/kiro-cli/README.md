[中文](README_ZH.md)

---
# Kiro-CLI Adaptation

## Prerequisites

- [kiro-cli](https://kiro.dev) installed
- Python 3 + pyyaml + arxiv
- Agent registered in `~/.kiro/agents/tech-radar.json`

## Installation

### 1. Register the agent

Register the agent in `~/.kiro/agents/tech-radar.json`, referencing `$INSTALL_DIR/scripts/agent.md` as the prompt.

### 2. Install scripts

Copy `daily.sh`, `weekly.sh`, `monthly.sh`, and `agent.md` to `$INSTALL_DIR/scripts/`.

### 3. Install core files

Ensure the `core/` directory is at `$INSTALL_DIR/core/`.

### 4. Configure crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## Model Configuration

Use full model names in `instance.env`:

```bash
MODEL_DAILY="claude-sonnet-4.6"
MODEL_WEEKLY="claude-opus-4.6"
MODEL_MONTHLY="claude-opus-4.6"
```

## Web Search

kiro-cli natively supports `web_search` and `web_fetch` tools, no extra configuration needed.

## Known Limitations

- The `write` tool has a per-call limit of ≤150 lines; segmented writing is required (create + append)
- kiro-cli may return exit=0 after an API dispatch timeout; the script includes a built-in `is_dispatch_failure()` check
- The cron environment requires manual PATH setup (nvm detection is built into the scripts)
