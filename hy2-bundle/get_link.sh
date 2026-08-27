#!/bin/bash
set -euo pipefail
if ! command -v jq &> /dev/null; then
    if command -v apt &>/dev/null; then apt update -qq && apt install -y jq; else dnf install -y jq; fi
fi
CONFIG=""
for candidate in /etc/sing-box/config.json /etc/sing-box/*.json; do
  [[ -f "$candidate" ]] || continue
  if jq -e '.inbounds[] | select(.type=="hysteria2" or .type=="vless")' "$candidate" >/dev/null 2>&1; then
    CONFIG="$candidate"; break
  fi
done
[[ -z "$CONFIG" ]] && { echo "找不到 sing-box 配置" >&2; exit 1; }
NODE_NAME="${1:-node}"

# IPv6 地址在 URI 里需加方括号
bracket() { [[ "$1" == *:* ]] && echo "[$1]" || echo "$1"; }

if jq -e '.inbounds[] | select(.type=="vless")' "$CONFIG" >/dev/null 2>&1; then
    # ===== VLESS + Reality =====
    V=$(jq -c '.inbounds[] | select(.type=="vless")' "$CONFIG")
    PORT=$(echo "$V" | jq -r '.listen_port')
    UUID=$(echo "$V" | jq -r '.users[0].uuid')
    FLOW=$(echo "$V" | jq -r '.users[0].flow // "xtls-rprx-vision"')
    SNI=$(echo "$V" | jq -r '.tls.server_name // empty')
    SID=$(echo "$V" | jq -r '.tls.reality.short_id[0] // empty')
    PBK=""
    [[ -f /etc/sing-box/reality_pub ]] && PBK=$(cat /etc/sing-box/reality_pub)
    # 节点连接地址存于 /etc/sing-box/node_host(install.sh 写入),缺省用 SNI
    HOST=""
    [[ -f /etc/sing-box/node_host ]] && HOST=$(cat /etc/sing-box/node_host)
    [[ -z "$HOST" ]] && HOST="$SNI"
    HOST_PART=$(bracket "$HOST")
    LINK="vless://${UUID}@${HOST_PART}:${PORT}?encryption=none&security=reality&sni=${SNI}&fp=chrome&pbk=${PBK}&sid=${SID}&type=tcp&flow=${FLOW}#${NODE_NAME}"
    # 链接只输出到 stdout(便于脚本捕获),横幅走 stderr
    echo "" >&2
    echo "===== 生成的分享链接 =====" >&2
    echo "$LINK"
    echo "" >&2
    exit 0
fi

# ===== Hysteria2 =====
HY2_JSON=$(jq -c '.inbounds[] | select(.type=="hysteria2")' "$CONFIG")
LISTEN_PORT=$(echo "$HY2_JSON" | jq -r '.listen_port')
PASSWORD=$(echo "$HY2_JSON" | jq -r '.users[0].password')
SERVER_NAME=$(echo "$HY2_JSON" | jq -r '.tls.server_name')
ALPN=$(echo "$HY2_JSON" | jq -r '.tls.alpn[0] // "h3"')
OBFS_TYPE=$(echo "$HY2_JSON" | jq -r '.obfs.type // empty')
OBFS_PASSWORD=$(echo "$HY2_JSON" | jq -r '.obfs.password // empty')
CERT_PATH=$(echo "$HY2_JSON" | jq -r '.tls.certificate_path // empty')
# 自签证书(IP直连 / 域名申请失败回退)→ 链接加 insecure=1,客户端导入自动跳过证书校验
IS_SELF="no"
if [[ -n "$CERT_PATH" && -f "$CERT_PATH" ]]; then
  # openssl 输出带 issuer=/subject= 前缀,去掉前缀后再比较
  ISSUER=$(openssl x509 -in "$CERT_PATH" -noout -issuer 2>/dev/null | cut -d= -f2-)
  SUBJECT=$(openssl x509 -in "$CERT_PATH" -noout -subject 2>/dev/null | cut -d= -f2-)
  [[ -n "$ISSUER" && "$ISSUER" == "$SUBJECT" ]] && IS_SELF="yes"
fi
PORT_RANGE=""
# 优先读 install.sh 写入的 port_range(RHEL/firewalld 也能拿到);iptables 探测作兜底
[[ -f /etc/sing-box/port_range ]] && PORT_RANGE=$(cat /etc/sing-box/port_range)
if [[ -z "$PORT_RANGE" ]] && command -v iptables >/dev/null 2>&1; then
  RANGE_LINE=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep -E "udp.*dpts:[0-9]+:[0-9]+.*redir ports ${LISTEN_PORT}" | head -1 || true)
  [[ -n "$RANGE_LINE" ]] && PORT_RANGE=$(echo "$RANGE_LINE" | grep -oP 'dpts:\K[0-9]+:[0-9]+' | tr ':' '-')
fi
if [[ -n "$PORT_RANGE" ]]; then PORT_PART="$PORT_RANGE"; else PORT_PART="$LISTEN_PORT"; fi
HOST_PART=$(bracket "$SERVER_NAME")
INSECURE_FLAG=""
[[ "$IS_SELF" == "yes" ]] && INSECURE_FLAG="&insecure=1"
if [[ -n "$OBFS_TYPE" ]]; then
  LINK="hysteria2://${PASSWORD}@${HOST_PART}:${PORT_PART}/?sni=${SERVER_NAME}&alpn=${ALPN}${INSECURE_FLAG}&obfs=${OBFS_TYPE}&obfs-password=${OBFS_PASSWORD}#${NODE_NAME}"
else
  LINK="hysteria2://${PASSWORD}@${HOST_PART}:${PORT_PART}/?sni=${SERVER_NAME}&alpn=${ALPN}${INSECURE_FLAG}#${NODE_NAME}"
fi
echo "" >&2
echo "===== 生成的分享链接 =====" >&2
echo "$LINK"
echo "" >&2
