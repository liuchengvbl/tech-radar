#!/bin/bash
# tech-radar agent 的 shell 命令过滤
# 拆分复合命令（; && || |），逐个子命令检查
# 黑名单命令 exit 2 拦截，路径受控命令检查白名单路径，其余放行

EVENT=$(cat)
CMD=$(echo "$EVENT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

if [ -z "$CMD" ]; then
    exit 0
fi

BLOCKED="apt apt-get yum dnf brew npm npx ssh scp rsync mkfs fdisk mount umount systemctl service reboot shutdown"
PATH_CONTROLLED="python3 python rm"
URL_CONTROLLED="curl wget"

CONF="$(dirname "$0")/trust-paths.conf"
CURL_DOMAINS_CONF="$(dirname "$0")/curl-allowed-domains.conf"
ALLOWED_PATHS=()
if [ -f "$CONF" ]; then
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$line" ] && continue
        line=$(echo "$line" | sed "s|^~|$HOME|")
        ALLOWED_PATHS+=("$line")
    done < "$CONF"
fi

path_allowed() {
    local p="$1"
    p=$(echo "$p" | sed "s|^~|$HOME|")
    for prefix in "${ALLOWED_PATHS[@]}"; do
        case "$p" in
            ${prefix}*) return 0 ;;
        esac
    done
    return 1
}

domain_allowed() {
    local host="$1"
    # Block internal/loopback addresses
    case "$host" in
        localhost|127.*|0.0.0.0|10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*)
            echo "curl: 禁止访问内网地址 '$host'" >&2; return 2 ;;
    esac
    if [ ! -f "$CURL_DOMAINS_CONF" ]; then
        echo "curl: 域名白名单配置不存在 ($CURL_DOMAINS_CONF)" >&2; return 2
    fi
    while IFS= read -r allowed; do
        allowed=$(echo "$allowed" | sed 's/#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$allowed" ] && continue
        case "$host" in
            *"$allowed") return 0 ;;
        esac
    done < "$CURL_DOMAINS_CONF"
    echo "curl: 域名 '$host' 不在允许列表中" >&2; return 2
}

check_subcmd() {
    local subcmd="$1"
    subcmd=$(echo "$subcmd" | sed 's/#.*$//')
    subcmd=$(echo "$subcmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$subcmd" ] && return 0

    local base=$(echo "$subcmd" | awk '{print $1}' | xargs basename 2>/dev/null)
    [ -z "$base" ] && return 0

    if echo "$subcmd" | grep -qiE '\bpip3?\s+install\b|\bapt(-get)?\s+install\b|\bnpm\s+install\b|\bbrew\s+install\b'; then
        echo "安装命令被禁止" >&2
        return 2
    fi

    for blocked in $BLOCKED; do
        if [ "$base" = "$blocked" ]; then
            echo "命令 '$base' 被禁止" >&2
            return 2
        fi
    done

    for pcmd in $PATH_CONTROLLED; do
        if [ "$base" = "$pcmd" ]; then
            local paths=$(echo "$subcmd" | grep -oE '(/[^ ]+|~/[^ ]+)' | grep -v '^-')
            [ -z "$paths" ] && return 0
            while IFS= read -r p; do
                [ -z "$p" ] && continue
                if ! path_allowed "$p"; then
                    echo "命令 '$base' 的路径 '$p' 不在允许范围内" >&2
                    return 2
                fi
            done <<< "$paths"
            return 0
        fi
    done

    for ucmd in $URL_CONTROLLED; do
        if [ "$base" = "$ucmd" ]; then
            # Extract host from URL argument (https://host/path or http://host/path)
            local url host
            url=$(echo "$subcmd" | grep -oE 'https?://[^ '"'"'"]+' | head -1)
            if [ -z "$url" ]; then
                echo "curl: 未找到 URL 参数" >&2; return 2
            fi
            host=$(echo "$url" | sed 's|https\?://||; s|/.*||; s|:[0-9]*$||')
            domain_allowed "$host"
            return $?
        fi
    done

    return 0
}

while IFS= read -r subcmd; do
    check_subcmd "$subcmd"
    ret=$?
    if [ $ret -ne 0 ]; then
        exit 2
    fi
done < <(echo "$CMD" | sed 's/\$([^)]*)/__SUBSHELL__/g; s/`[^`]*`/__SUBSHELL__/g' | tr ';' '\n' | sed 's/&&/\n/g; s/||/\n/g; s/|/\n/g')

exit 0
