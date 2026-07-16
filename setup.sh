#!/bin/bash
# tech-radar agent 安装脚本（多平台版）
# 用法：bash setup.sh

set -euo pipefail

PORT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== tech-radar agent 安装向导 ==="
echo ""

# ── 1. 选择平台 ─────────────────────────────────────────────
echo "选择目标平台："
echo "  1) Claude Code"
echo "  2) OpenCode"
echo "  3) Kiro-CLI"
read -rp "请输入数字 [1-3]: " PLATFORM_CHOICE

case "$PLATFORM_CHOICE" in
    1) PLATFORM="claude-code" ;;
    2) PLATFORM="opencode"   ;;
    3) PLATFORM="kiro-cli"   ;;
    *) echo "无效选择：$PLATFORM_CHOICE"; exit 1 ;;
esac

PLATFORM_DIR="$PORT_DIR/platforms/$PLATFORM"
if [ ! -d "$PLATFORM_DIR" ]; then
    echo "错误：平台目录不存在：$PLATFORM_DIR" >&2
    exit 1
fi

echo "已选择：$PLATFORM"
echo ""

# ── 2. 安装目录 ──────────────────────────────────────────────
read -rp "Agent 安装目录 [默认: ~/tech-radar]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$HOME/tech-radar}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

# ── 3. 实例名称 ──────────────────────────────────────────────
read -rp "实例名称（如 sensor）[默认: sensor]: " INSTANCE_NAME
INSTANCE_NAME="${INSTANCE_NAME:-sensor}"

# ── 4. 报告目录 ──────────────────────────────────────────────
read -rp "报告输出目录 [默认: ~/tech-radar-reports/$INSTANCE_NAME]: " REPORT_DIR
REPORT_DIR="${REPORT_DIR:-$HOME/tech-radar-reports/$INSTANCE_NAME}"
REPORT_DIR="${REPORT_DIR/#\~/$HOME}"

# ── 5. 确认 ─────────────────────────────────────────────────
echo ""
echo "安装配置："
echo "  平台：      $PLATFORM"
echo "  Agent 目录：$INSTALL_DIR"
echo "  实例名称：  $INSTANCE_NAME"
echo "  报告目录：  $REPORT_DIR"
echo ""
read -rp "确认安装？[y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
fi

echo ""
echo "正在安装..."

# ── 6. 创建目录结构 ──────────────────────────────────────────
INSTANCE_DIR="$INSTALL_DIR/$INSTANCE_NAME"
mkdir -p "$INSTALL_DIR"/{scripts,logs,core} \
         "$INSTANCE_DIR" \
         "$REPORT_DIR"/{daily,weekly,monthly}

# ── 7. 复制 core/（平台无关的核心资产）──────────────────────
cp -r "$PORT_DIR/core/." "$INSTALL_DIR/core/"

# ── 8. 复制平台脚本到 scripts/ ──────────────────────────────
cp "$PLATFORM_DIR"/daily.sh \
   "$PLATFORM_DIR"/weekly.sh \
   "$PLATFORM_DIR"/monthly.sh \
   "$INSTALL_DIR/scripts/"

echo "  ✓ 脚本已复制到 $INSTALL_DIR/scripts/"

# ── 9. 平台特定安装 ─────────────────────────────────────────
case "$PLATFORM" in
    claude-code)
        # ── 9a. 复制 hooks ───────────────────────────────────
        mkdir -p "$INSTALL_DIR/hooks"
        cp -r "$PLATFORM_DIR/hooks/." "$INSTALL_DIR/hooks/"

        # ── 9b. 安装 agent 定义到 .claude/agents/ ────────────
        #      替换 {{INSTALL_DIR}}，其中 skills 路径需指向 core/skills/
        mkdir -p "$INSTALL_DIR/.claude/agents"
        sed -e "s|{{INSTALL_DIR}}/skills/|$INSTALL_DIR/core/skills/|g" \
            -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
            "$PLATFORM_DIR/agent.md" \
            > "$INSTALL_DIR/.claude/agents/tech-radar.md"

        # ── 9c. 生成 .claude/settings.json（hooks 配置）──────
        mkdir -p "$INSTALL_DIR/.claude"
        cat > "$INSTALL_DIR/.claude/settings.json" << SETTINGS_EOF
{
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Bash",
      "WebFetch"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$INSTALL_DIR/hooks/shell-guard.sh"
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "$INSTALL_DIR/hooks/write-guard.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF

        # ── 9d. 生成 trust-paths.conf（写入路径白名单）────────
        cat > "$INSTALL_DIR/hooks/trust-paths.conf" << TRUST_EOF
# tech-radar agent 允许写入的路径前缀
# 新增实例时追加对应目录

# $INSTANCE_NAME 实例
$REPORT_DIR/
$INSTALL_DIR/

# 通用
/tmp/
~/.agents/
TRUST_EOF

        chmod +x "$INSTALL_DIR"/hooks/*.sh
        echo "  ✓ hooks 已安装到 $INSTALL_DIR/hooks/"
        echo "  ✓ agent 定义已写入 $INSTALL_DIR/.claude/agents/tech-radar.md"
        ;;

    opencode)
        # ── 9a. 复制 agent.md 到 scripts/（参考副本）─────────
        cp "$PLATFORM_DIR/agent.md" "$INSTALL_DIR/scripts/agent.md"

        # ── 9b. 创建 opencode agents 目录 ────────────────────
        #      agent 定义将在 instance.env 创建后处理（需要 MODEL_DAILY）
        OPENCODE_AGENTS_DIR="$HOME/.config/opencode/agents"
        mkdir -p "$OPENCODE_AGENTS_DIR"
        echo "  ✓ 脚本已复制到 $INSTALL_DIR/scripts/"
        ;;

    kiro-cli)
        # ── 9a. 复制 agent.md 到 scripts/ ────────────────────
        #      kiro-cli 的 daily.sh 从 $SCRIPT_DIR/agent.md 读取 agent prompt
        cp "$PLATFORM_DIR/agent.md" "$INSTALL_DIR/scripts/agent.md"
        echo "  ✓ 脚本已复制到 $INSTALL_DIR/scripts/"
        ;;
esac

# ── 10. 创建实例配置 ─────────────────────────────────────────
#       替换 {{INSTANCE_NAME}} 和 {{REPORT_DIR}}，模型配置留待用户编辑
sed \
    -e "s|{{INSTANCE_NAME}}|$INSTANCE_NAME|g" \
    -e "s|{{REPORT_DIR}}|$REPORT_DIR|g" \
    "$PORT_DIR/instance-template/instance.env.template" \
    > "$INSTANCE_DIR/instance.env"

cp "$PORT_DIR/instance-template/scan-config.example.yaml" \
   "$INSTANCE_DIR/scan-config.yaml"

echo "  ✓ 实例配置已写入 $INSTANCE_DIR/"

# ── 11. 平台特定：opencode agent.md 占位符替换 ───────────────
if [ "$PLATFORM" = "opencode" ]; then
    # 从 instance.env 读取 MODEL_DAILY 填入 agent 定义
    # shellcheck disable=SC1090
    source "$INSTANCE_DIR/instance.env"
    sed -e "s|{{INSTALL_DIR}}|$INSTALL_DIR|g" \
        -e "s|{{REPORT_DIR}}|$REPORT_DIR|g" \
        -e "s|{{MODEL_DAILY}}|${MODEL_DAILY:-}|g" \
        "$PLATFORM_DIR/agent.md" \
        > "$OPENCODE_AGENTS_DIR/tech-radar.md"
    echo "  ✓ agent 定义已写入 $OPENCODE_AGENTS_DIR/tech-radar.md"
fi

# ── 12. 可执行权限 ───────────────────────────────────────────
chmod +x "$INSTALL_DIR"/scripts/*.sh
if [ -f "$INSTALL_DIR/core/review-config.sh" ]; then
    chmod +x "$INSTALL_DIR/core/review-config.sh"
fi

# ── 13. crontab（可选）──────────────────────────────────────
echo ""
echo "推荐 crontab 条目（每天 06:00 日报，每周日 20:00 周报，每月 1 日 03:00 月报）："
echo ""
echo "  0 6  * * *   $INSTALL_DIR/scripts/daily.sh   $INSTANCE_DIR"
echo "  0 20 * * 0   $INSTALL_DIR/scripts/weekly.sh  $INSTANCE_DIR"
echo "  0 3  1 * *   $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR"
echo ""
read -rp "自动写入 crontab？[y/N]: " ADD_CRON
if [[ "$ADD_CRON" =~ ^[Yy]$ ]]; then
    (
      crontab -l 2>/dev/null
      echo "0 6  * * *   $INSTALL_DIR/scripts/daily.sh   $INSTANCE_DIR"
      echo "0 20 * * 0   $INSTALL_DIR/scripts/weekly.sh  $INSTANCE_DIR"
      echo "0 3  1 * *   $INSTALL_DIR/scripts/monthly.sh $INSTANCE_DIR"
    ) | crontab -
    echo "  ✓ 已写入 crontab。"
fi

# ── 14. 完成 ─────────────────────────────────────────────────
echo ""
echo "✓ 安装完成！"
echo ""
echo "下一步："
echo "  1. 编辑 $INSTANCE_DIR/scan-config.yaml 配置搜集领域"
echo "  2. 编辑 $INSTANCE_DIR/instance.env 填写模型配置（MODEL_DAILY/WEEKLY/MONTHLY）"
echo "     — 各平台模型格式参考文件内注释"

case "$PLATFORM" in
    claude-code)
        echo "  3. 确认 Claude Code 已安装：claude --version"
        ;;
    opencode)
        echo "  3. 确认 OpenCode 已安装：opencode --version"
        echo "  4. 如需修改 agent 默认模型，编辑：$HOME/.config/opencode/agents/tech-radar.md"
        echo "  5. 可选：部署 web_search 代理（参考 platforms/opencode/README.md）"
        ;;
    kiro-cli)
        echo "  3. 确认 Kiro-CLI 已安装：kiro-cli --version"
        echo "  4. 在 ~/.kiro/agents/ 中注册 agent（参考 platforms/kiro-cli/README.md）"
        ;;
esac

echo ""
echo "  最后：手动测试日报："
echo "    bash $INSTALL_DIR/scripts/daily.sh $INSTANCE_DIR"
