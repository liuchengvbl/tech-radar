[中文](README_ZH.md)

---
# OpenCode Adaptation

## Prerequisites

- [opencode](https://opencode.ai) CLI installed
- Python 3 + pyyaml + arxiv
- Model provider configured in `~/.config/opencode/opencode.json`

## Installation

### 1. Install the agent definition

Copy `agent.md` to the opencode global agents directory, substituting placeholders:

```bash
sed -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
    -e "s|{{MODEL_DAILY}}|$MODEL_DAILY|g" \
    -e "s|{{REPORT_DIR}}|$REPORT_DIR|g" \
    agent.md > ~/.config/opencode/agents/tech-radar.md
```

### 2. Install scripts

Copy `daily.sh`, `weekly.sh`, `monthly.sh` to `$INSTALL_DIR/scripts/`.

### 3. Install core files

Ensure the `core/` directory is at `$INSTALL_DIR/core/` (contains prompt templates and skills).

### 4. Configure crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## Model Configuration

Use the `provider/model-id` format in `instance.env`:

```bash
MODEL_DAILY="mify-openai/ppio/pa/gpt-5.5"
MODEL_WEEKLY="mify-zhipu/zhipuai/glm-5.2"
MODEL_MONTHLY="mify-zhipu/zhipuai/glm-5.2"
```

## Web Search

OpenCode's `websearch` tool requires the `OPENCODE_ENABLE_EXA=1` environment variable.

If using a model that supports native web_search (e.g., GLM-5.2, GPT-5.5), but the platform's provider adapter does not pass through that parameter, you can deploy a local HTTP proxy to inject the `web_search` tool:

```bash
# Install the proxy
cp glm-websearch-proxy.js ~/.config/opencode/
cp glm-websearch-proxy.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now glm-websearch-proxy

# In opencode.json, point the provider's baseURL to the proxy
# "baseURL": "http://127.0.0.1:8899/v1"
```

The proxy automatically injects the `{"type":"web_search","web_search":{"enable":true,"search_result":true}}` tool for GLM and GPT model requests.

## Known Limitations

- opencode's `webfetch` tool is available by default, no extra configuration needed
- Both `write` and `apply_patch` are governed by the `edit` permission; either can be used to write files
- The cron environment requires manual PATH setup (nvm detection is built into the scripts)
