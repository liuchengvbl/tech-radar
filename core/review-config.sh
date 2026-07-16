#!/bin/bash
# Review and apply monthly config proposal
# Usage: ./review-config.sh [MONTH]
# Example: ./review-config.sh 2026-04

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RADAR_HOME="$(dirname "$SCRIPT_DIR")"
INSTANCE_DIR="${INSTANCE_DIR:-$RADAR_HOME/../sensor}"
source "$INSTANCE_DIR/instance.env"
SCAN_CONFIG="$INSTANCE_DIR/scan-config.yaml"

MONTH=${1:-$(date +%Y-%m)}
PROPOSAL="$REPORT_DIR/monthly/$MONTH-config-proposal.yaml"

if [ ! -f "$PROPOSAL" ]; then
    echo "未找到 $MONTH 的配置修改建议：$PROPOSAL"
    exit 1
fi

echo "=========================================="
echo "  月度配置修改建议审核 — $MONTH"
echo "=========================================="
echo ""
echo "月报位置：$REPORT_DIR/monthly/$MONTH.md"
echo "建议文件：$PROPOSAL"
echo "当前配置：$SCAN_CONFIG"
echo ""
echo "--- 差异对比 ---"
echo ""
diff --color -u "$SCAN_CONFIG" "$PROPOSAL" || true
echo ""
echo "=========================================="
echo "操作选项："
echo "  1) 打开两个文件进行手动合并（推荐）"
echo "  2) 直接采纳全部建议（覆盖当前配置）"
echo "  3) 跳过本月，不做修改"
echo "=========================================="
read -p "请选择 [1/2/3]: " choice

case $choice in
    1)
        echo "正在打开文件..."
        vimdiff "$SCAN_CONFIG" "$PROPOSAL" 2>/dev/null || \
        echo "请手动编辑：$SCAN_CONFIG"
        ;;
    2)
        cp "$SCAN_CONFIG" "$SCAN_CONFIG.bak.$(date +%Y%m%d)"
        cp "$PROPOSAL" "$SCAN_CONFIG"
        echo "已采纳全部建议。旧配置备份在 $SCAN_CONFIG.bak.$(date +%Y%m%d)"
        ;;
    3)
        echo "已跳过。"
        ;;
    *)
        echo "无效选择。"
        exit 1
        ;;
esac
