# OpenCode 适配

## 前置条件

- [opencode](https://opencode.ai) CLI 已安装
- Python 3 + pyyaml + arxiv
- 模型 provider 已在 `~/.config/opencode/opencode.json` 中配置

## 安装

### 1. 安装 agent 定义

将 `agent.md` 复制到 opencode 全局 agents 目录，替换占位符：

```bash
sed -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
    -e "s|{{MODEL_DAILY}}|$MODEL_DAILY|g" \
    -e "s|{{REPORT_DIR}}|$REPORT_DIR|g" \
    agent.md > ~/.config/opencode/agents/tech-radar.md
```

### 2. 安装脚本

将 `daily.sh`、`weekly.sh`、`monthly.sh` 复制到 `$INSTALL_DIR/scripts/`。

### 3. 安装 core 文件

确保 `core/` 目录在 `$INSTALL_DIR/core/`（包含 prompt 模板和 skills）。

### 4. 配置 crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## 模型配置

在 `instance.env` 中使用 `provider/model-id` 格式：

```bash
MODEL_DAILY="mify-openai/ppio/pa/gpt-5.5"
MODEL_WEEKLY="mify-zhipu/zhipuai/glm-5.2"
MODEL_MONTHLY="mify-zhipu/zhipuai/glm-5.2"
```

## 网络搜索

OpenCode 的 `websearch` 工具需要 `OPENCODE_ENABLE_EXA=1` 环境变量。

如果使用支持原生 web_search 的模型（如 GLM-5.2、GPT-5.5），但平台的 provider 适配器不透传该参数，可以部署本地 HTTP 代理注入 `web_search` tool：

```bash
# 安装代理
cp glm-websearch-proxy.js ~/.config/opencode/
cp glm-websearch-proxy.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now glm-websearch-proxy

# 在 opencode.json 中将 provider 的 baseURL 指向代理
# "baseURL": "http://127.0.0.1:8899/v1"
```

代理会自动为 GLM 和 GPT 模型的请求注入 `{"type":"web_search","web_search":{"enable":true,"search_result":true}}` 工具。

## 已知限制

- opencode 的 `webfetch` 工具默认可用，无需额外配置
- `write` 和 `apply_patch` 均受 `edit` 权限控制，两者均可用于写文件
- cron 环境需要手动设置 PATH（脚本已内置 nvm 探测）
