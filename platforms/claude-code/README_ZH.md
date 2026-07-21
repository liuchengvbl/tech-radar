[English](README.md)

---
# Claude Code 适配

## 前置条件

- [claude](https://claude.ai) CLI 已安装（通过 nvm）
- Python 3 + pyyaml + arxiv
- 模型 provider 已在 `~/.claude/settings.json` 中配置

## 安装

### 1. 安装 agent 定义

将 `agent.md` 复制到 Claude Code agents 目录，替换占位符：

```bash
sed -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
    agent.md > ~/.claude/agents/tech-radar.md
```

### 2. 安装脚本

将 `daily.sh`、`weekly.sh`、`monthly.sh` 复制到 `$INSTALL_DIR/scripts/`。

### 3. 安装 core 文件

确保 `core/` 目录在 `$INSTALL_DIR/core/`（包含 prompt 模板和 skills）。

### 4. 安装 hooks

将 hook 脚本和配置复制到 `~/.claude/hooks/`：

```bash
mkdir -p ~/.claude/hooks
cp hooks/shell-guard.sh ~/.claude/hooks/
cp hooks/write-guard.sh ~/.claude/hooks/
cp hooks/curl-allowed-domains.conf ~/.claude/hooks/
# 创建 trust-paths.conf，配置允许写入的路径
cp hooks/trust-paths.conf.example ~/.claude/hooks/trust-paths.conf
```

在 `~/.claude/settings.json` 中注册 hooks：

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

### 5. 配置 crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## 模型配置

在 `instance.env` 中使用模型别名：

```bash
MODEL_DAILY="claude-sonnet-4.6"
MODEL_WEEKLY="claude-opus-4.6"
MODEL_MONTHLY="claude-opus-4.6"
```

## 网络搜索

Claude Code 使用 `WebFetch` 进行所有网络访问。在代理环境下没有原生的 `WebSearch` 工具。

agent 构造搜索引擎 URL 并通过 `WebFetch` 获取：
- DuckDuckGo: `https://html.duckduckgo.com/html/?q=QUERY&df=d`（df=d/w/m 控制时间范围）
- arXiv 搜索: `https://arxiv.org/search/?query=QUERY&searchtype=all&order=-announced_date_first`
- Google News RSS: `https://news.google.com/rss/search?q=QUERY&hl=en-US&gl=US&ceid=US:en`

除了 `WebFetch` 工具权限外，无需额外配置。

## Hooks

Claude Code 使用 PreToolUse hooks 强制安全边界：

- **shell-guard.sh**：过滤 shell 命令 — 拦截危险命令（apt、ssh、systemctl 等），对 `python3`/`rm` 强制路径白名单，对 `curl`/`wget` 限制为 `curl-allowed-domains.conf` 中的域名
- **write-guard.sh**：限制文件写入路径为 `trust-paths.conf` 中列出的路径

## 已知限制

- `claude --print` 在 API 错误时可能返回 exit=0 但不产生输出；脚本内置 `verify_output()` 检查预期报告文件是否存在
- 代理环境下 `WebSearch` 不可用；所有网络访问通过 `WebFetch` 构造搜索 URL 实现
- cron 环境需要手动设置 PATH（脚本已内置 nvm 探测）
- Shell hooks 会拆分复合命令（`;`、`&&`、`||`、`|`），逐个子命令检查
