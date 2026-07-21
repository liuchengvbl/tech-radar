[English](README.md)

---
# Kiro-CLI 适配

## 前置条件

- [kiro-cli](https://kiro.dev) 已安装
- Python 3 + pyyaml + arxiv
- Agent 已在 `~/.kiro/agents/tech-radar.json` 中注册

## 安装

### 1. 注册 agent

在 `~/.kiro/agents/tech-radar.json` 中注册 agent，引用 `$INSTALL_DIR/scripts/agent.md` 作为 prompt。

### 2. 安装脚本

将 `daily.sh`、`weekly.sh`、`monthly.sh`、`agent.md` 复制到 `$INSTALL_DIR/scripts/`。

### 3. 安装 core 文件

确保 `core/` 目录在 `$INSTALL_DIR/core/`。

### 4. 配置 crontab

```
0 6  * * * $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR
0 20 * * 0 $INSTALL_DIR/scripts/weekly.sh $INSTANCE_DIR
0 3  1 * * $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR
```

## 模型配置

在 `instance.env` 中使用完整模型名：

```bash
MODEL_DAILY="claude-sonnet-4.6"
MODEL_WEEKLY="claude-opus-4.6"
MODEL_MONTHLY="claude-opus-4.6"
```

## 网络搜索

kiro-cli 原生支持 `web_search` 和 `web_fetch` 工具，无需额外配置。

## 已知限制

- `write` 工具每次调用限制 ≤150 行，需要分段写入（create + append）
- kiro-cli 在 API dispatch timeout 后可能返回 exit=0，脚本内置 `is_dispatch_failure()` 检测
- cron 环境需要手动设置 PATH（脚本已内置 nvm 探测）
