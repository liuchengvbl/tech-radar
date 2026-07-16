#!/bin/bash
# tech-radar agent 的 write 路径过滤
# 允许列表从配置文件读取，每行一个路径前缀（支持 ~ 展开）
# 配置文件不存在时拒绝所有写入

CONFIG="$(dirname "$0")/trust-paths.conf"

if [ ! -f "$CONFIG" ]; then
    echo "写入路径配置文件 $CONFIG 不存在，拒绝所有写入" >&2
    exit 2
fi

EVENT=$(cat)
# Claude Code 的 Write 工具使用 file_path 字段（Kiro 用 path）
FILE_PATH=$(echo "$EVENT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)
FILE_PATH=$(echo "$FILE_PATH" | sed "s|^~|$HOME|")

while IFS= read -r prefix; do
    [[ -z "$prefix" || "$prefix" == \#* ]] && continue
    prefix=$(echo "$prefix" | sed "s|^~|$HOME|")
    case "$FILE_PATH" in
        ${prefix}*) exit 0 ;;
    esac
done < "$CONFIG"

echo "写入路径 '$FILE_PATH' 不在允许范围内" >&2
exit 2
