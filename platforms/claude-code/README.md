[中文](README_ZH.md)

---
# Claude Code Adaptation

## Prerequisites

- [claude](https://claude.ai) CLI installed (via nvm)
- Python 3 + pyyaml + arxiv
- Model provider configured in `~/.claude/settings.json`

## Installation

### 1. Install the agent definition

Copy `agent.md` to the Claude Code agents directory, substituting placeholders:

```bash
sed -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
    agent.md > ~/.claude/agents/tech-radar.md
```

### 2. Install scripts

Copy `daily.sh`, `weekly.sh`, `monthly.sh` to `$INSTALL_DIR/scripts/`.

### 3. Install core files

Ensure the `core/` directory is at `$INSTALL_DIR/core/` (contains prompt templates and skills).

### 4. Install hooks

Copy the hook scripts and configuration to `~/.claude/hooks/`:

```bash
mkdir -p ~/.claude/hooks
cp hooks/shell-guard.sh ~/.claude/hooks/
cp hooks/write-guard.sh ~/.claude/hooks/
cp hooks/curl-allowed-domains.conf ~/.claude/hooks/
# Create trust-paths.conf with allowed write paths
cp hooks/trust-paths.conf.example ~/.claude/hooks/trust-paths.conf
```

Register the hooks in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/shell-guard.sh"}]},
      {"matcher": "Write", "hooks": [{"type": "command", "command": "~/.claude/hooks/write-guard.sh"}]}
    ]
  }
}
```

### 5. Configure crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## Model Configuration

Use model aliases in `instance.env`:

```bash
MODEL_DAILY="claude-sonnet-4.6"
MODEL_WEEKLY="claude-opus-4.6"
MODEL_MONTHLY="claude-opus-4.6"
```

## Web Search

Claude Code uses `WebFetch` for all web access. There is no native `WebSearch` tool in proxy environments.

The agent constructs search engine URLs and fetches them via `WebFetch`:
- DuckDuckGo: `https://html.duckduckgo.com/html/?q=QUERY&df=d` (df=d/w/m controls the time range)
- arXiv search: `https://arxiv.org/search/?query=QUERY&searchtype=all&order=-announced_date_first`
- Google News RSS: `https://news.google.com/rss/search?q=QUERY&hl=en-US&gl=US&ceid=US:en`

No extra configuration is needed beyond the `WebFetch` tool permission.

## Hooks

Claude Code uses PreToolUse hooks to enforce security boundaries:

- **shell-guard.sh**: Filters shell commands — blocks dangerous commands (apt, ssh, systemctl, etc.), enforces path whitelisting for `python3`/`rm`, and restricts `curl`/`wget` to domains in `curl-allowed-domains.conf`
- **write-guard.sh**: Restricts file writes to paths listed in `trust-paths.conf`

## Known Limitations

- `claude --print` may exit 0 on API errors without producing output; the script includes `verify_output()` to check for the expected report files
- `WebSearch` is unavailable in proxy environments; all web access goes through `WebFetch` with constructed search URLs
- The cron environment requires manual PATH setup (nvm detection is built into the scripts)
- Shell hooks split compound commands (`;`, `&&`, `||`, `|`) and check each subcommand individually
