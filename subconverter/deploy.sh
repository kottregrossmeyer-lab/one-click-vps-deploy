#!/usr/bin/env bash
# ============================================================
#  订阅转换服务 · 一键部署脚本  v5.1 (Python, 零依赖)
#  支持 Debian/Ubuntu (apt) 与 RedHat/CentOS/Rocky/Alma (yum/dnf)
#  交互式流程:
#    1) 选择节点类型: 回车/1=仅 VLESS  2=仅 Hysteria2  3=双节点
#       (也可直接传链接跳过本步: bash deploy.sh 'vless://...' ['hysteria2://...']
#        或 SUB_LINK/SUB_LINK2 环境变量, 自动识别协议类型)
#    2) 选择访问方式:
#       1=域名+HTTP-01(正式证书,需开80)  2=公网IP(HTTP+HTTPS双端点)
#       3=域名+DNS-01(正式证书,不用开80,需交互添加TXT记录)
#    3) 选择 HTTPS 端口(默认51200), 交互确认 HTTP 端口
#    4) 自动生成随机 base64 路径(防扫描)
#    5) 安装依赖(仅 nginx, Python3 系统自带) → 签发证书 → 部署
#    6) 打印 HTTP+HTTPS 双订阅地址
#  用法:  sudo bash deploy.sh
#  配套:  server.py (本脚本同目录)
# ============================================================

set -euo pipefail
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"

# 颜色($'...' 存真实 ESC, read -p / echo -e 都能用)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

if [ "$(id -u)" -ne 0 ]; then
  echo "[X] 请用 root 运行:  sudo bash deploy.sh"
  exit 1
fi

APP_DIR=/opt/subconverter
SRV_PORT=31001       # 后端内部端口(仅 127.0.0.1)
WEB_PORT=51200       # 对外 HTTPS 端口(可交互修改, 默认避开 443 网站冲突)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- 0. 包管理器检测 ----------
detect_pm() {
  if   command -v apt-get >/dev/null 2>&1; then PM=apt;  PM_INSTALL="apt-get install -y"; PM_UPDATE="apt-get update -y"
  elif command -v dnf    >/dev/null 2>&1; then PM=dnf;  PM_INSTALL="dnf install -y";      PM_UPDATE="dnf check-update -y"
  elif command -v yum    >/dev/null 2>&1; then PM=yum;  PM_INSTALL="yum install -y";      PM_UPDATE="yum check-update -y"
  else echo "[X] 无法识别包管理器 (需要 apt/dnf/yum 之一)"; exit 1; fi
}
detect_pm

# 进度输出走 stderr (无缓冲, 不会因 SSH 管道卡住不显示)
log_progress() { echo "$*" >&2; }

# ---------- 包安装 (去 >/dev/null, 输出可见, 超时600s) ----------
pkg_install() {
  local pkgs="$1" n=0 holder rc PMOPTS=""
  if [ "$PM" = "apt" ]; then
    PMOPTS="-o Acquire::Retries=2 -o Acquire::http::Timeout=45 -o Acquire::https::Timeout=45"
  else
    PMOPTS="--setopt=timeout=45 --setopt=retries=2"
  fi
  # 预检: 所有包都已安装则直接返回
  _all_ok=1
  for _pkg in $pkgs; do
    case "$_pkg" in
      nginx)   [ -x /usr/sbin/nginx ] || [ -x /usr/bin/nginx ] || { _all_ok=0; break; } ;;
      certbot) [ -x /usr/bin/certbot ] || [ -x /usr/local/bin/certbot ] || { _all_ok=0; break; } ;;
      *)       command -v "$_pkg" >/dev/null 2>&1 || { _all_ok=0; break; } ;;
    esac
  done
  if [ "$_all_ok" = "1" ]; then
    log_progress "      $pkgs 已安装, 跳过"; return 0
  fi

  # 先停掉常见的锁占用者 (unattended-upgrades 最多浪费80秒)
  if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
    log_progress "      (暂停 unattended-upgrades, 装完恢复...)"
    systemctl stop unattended-upgrades 2>/dev/null || true
  fi
  if [ -f /var/lib/dpkg/lock-frontend ] || [ -f /var/lib/dpkg/lock ]; then
    log_progress "      (等待已占用的包管理器锁释放...)"
    while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null; do sleep 2; done
  fi

  log_progress "      (下载+安装中, 视网速可能需要1-10分钟...)"
  while [ "$n" -lt 8 ]; do
    n=$((n+1))
    timeout 600 $PM_INSTALL $PMOPTS $pkgs </dev/null; rc=$?
    # 安装后直接检查二进制是否存在 (不用 command -v, sudo PATH 可能不含 sbin)
    PKG_OK=1
    for _pkg in $pkgs; do
      _bin="$_pkg"
      # nginx 在 Debian 装在 /usr/sbin, command -v 受 sudo PATH 影响可能找不到
      [ "$_pkg" = "nginx" ] && { [ -x /usr/sbin/nginx ] || [ -x /usr/bin/nginx ]; } && continue
      [ "$_pkg" = "certbot" ] && { [ -x /usr/bin/certbot ] || [ -x /usr/local/bin/certbot ]; } && continue
      command -v "$_pkg" >/dev/null 2>&1 || { PKG_OK=0; break; }
    done
    if [ "$PKG_OK" = "1" ]; then
      log_progress "      $pkgs 安装完成"
      # 恢复之前暂停的服务
      systemctl start unattended-upgrades 2>/dev/null || true
      return 0
    fi
    if [ "$rc" -eq 124 ]; then
      log_progress "[X] 包管理器安装超时: $pkgs (镜像源不可达或网络差)"
      log_progress "   解决: 手动 apt-get update / dnf makecache 后重跑"
      return 1
    fi
    holder=$(pgrep -af "unattended-upgrade|apt-get|dpkg|dnf|yum" 2>/dev/null | grep -v "$$" | head -1 | cut -c1-90)
    if [ -z "$holder" ]; then
      log_progress "[X] 安装失败: $pkgs (非锁占用, 多为软件源错误或包不可用)"
      log_progress "   解决: 手动 apt-get update / dnf makecache 看具体报错"
      return 1
    fi
    log_progress "   (包管理器被占用: ${holder}, 等锁 $n/8 ...)"
    sleep 10
  done
  log_progress "[X] 安装失败: $pkgs (锁持续被占用)"
  return 1
}

# ---------- certbot 辅助 ----------
certbot_ge_53() {
  local cb v major minor
  cb=$(command -v certbot 2>/dev/null || true)
  [ -x "$cb" ] || cb=/usr/local/bin/certbot
  [ -x "$cb" ] || return 1
  v=$("$cb" --version 2>/dev/null | awk '{print $2}')
  [ -n "$v" ] || return 1
  major="${v%%.*}"; minor="${v#*.}"; minor="${minor%%.*}"
  [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 3 ]; }
}
install_certbot_pip() {
  local PY=python3
  # certbot 5.x 需要 Python>=3.10; RHEL 默认 3.9, 先补装 python3.11
  if [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
    if ! command -v python3.11 >/dev/null 2>&1; then
      log_progress "      (安装 python3.11, certbot 5.x 需要 Python>=3.10...)"
      timeout 180 $PM_INSTALL python3.11 python3.11-pip </dev/null || true
    fi
    command -v python3.11 >/dev/null 2>&1 && PY=python3.11
  fi
  # Ubuntu python3<3.10(如 20.04=3.8)时, 需要额外 python3.11 才能装 certbot 5.x
  if [ "$PM" = "apt" ]; then
    if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' >/dev/null 2>&1; then
      if ! command -v python3.11 >/dev/null 2>&1 && [ ! -x /opt/python3.11/bin/python3.11 ]; then
        log_progress "      (Ubuntu python3 过旧, 尝试 deadsnakes PPA 装 python3.11...)"
        timeout 180 $PM_INSTALL software-properties-common </dev/null || true
        timeout 120 add-apt-repository -y ppa:deadsnakes/ppa </dev/null || true
        timeout 180 $PM_UPDATE </dev/null || true
        timeout 180 $PM_INSTALL python3.11 python3.11-venv python3.11-distutils </dev/null || true
      fi
      if command -v python3.11 >/dev/null 2>&1; then
        PY=python3.11
      elif [ ! -x /opt/python3.11/bin/python3.11 ]; then
        log_progress "      (deadsnakes 不可用, 下载预编译 python3.11...)"
        timeout 120 $PM_INSTALL jq curl </dev/null || true
        local SB_VER SB_ASSET
        SB_VER=$(curl -fsSL --max-time 30 https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest 2>/dev/null | jq -r .tag_name 2>/dev/null)
        SB_ASSET=$(curl -fsSL --max-time 30 https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest 2>/dev/null | jq -r ".assets[].name" 2>/dev/null | grep -E "^cpython-3\.11\..*x86_64-unknown-linux-gnu-install_only\.tar\.gz$" | head -1)
        if [ -n "$SB_ASSET" ]; then
          curl -fSL --max-time 300 -o /tmp/py311.tgz "https://github.com/astral-sh/python-build-standalone/releases/download/$SB_VER/$SB_ASSET" 2>/dev/null || true
          mkdir -p /opt/python3.11 && tar xzf /tmp/py311.tgz -C /opt/python3.11 --strip-components=1 2>/dev/null || true
          rm -f /tmp/py311.tgz
        fi
        [ -x /opt/python3.11/bin/python3.11 ] && PY=/opt/python3.11/bin/python3.11
      fi
      # 清理 python3.8 的坏 certbot(版本不兼容会崩), 避免残留干扰
      if [ "$PY" != "python3" ]; then
        rm -f /usr/local/bin/certbot
        rm -rf /usr/local/lib/python3.8/dist-packages/certbot* /usr/local/lib/python3.8/dist-packages/acme* 2>/dev/null || true
      fi
    fi
  fi
  { command -v pip3 >/dev/null 2>&1 || { log_progress "      (安装 pip3...)"; timeout 120 $PM_INSTALL python3-pip </dev/null || true; }; } || true
  # 确保选中的解释器有 pip 模块(包名按解释器区分; Ubuntu 系统 python3 通常是 3.10/3.12, 够 certbot 5.x)
  if ! $PY -m pip --version >/dev/null 2>&1; then
    if [[ "$PY" == *python3.11* ]]; then
      timeout 120 $PM_INSTALL python3.11-pip </dev/null || true
      $PY -m ensurepip --upgrade >/dev/null 2>&1 || true   # deadsnakes/standalone 等无 pip 包时兜底
    else
      timeout 120 $PM_INSTALL python3-pip </dev/null || true
    fi
  fi
  # 逐个尝试: 清华优先(国内快), 各带/不带 --break-system-packages(兼容 Ubuntu 24.04 PEP668 外管环境 和 老 pip)
  timeout 90 $PY -m pip install --break-system-packages -q -i https://pypi.tuna.tsinghua.edu.cn/simple "certbot>=5.3" >/dev/null 2>&1 || \
  timeout 90 $PY -m pip install -q -i https://pypi.tuna.tsinghua.edu.cn/simple "certbot>=5.3" >/dev/null 2>&1 || \
  timeout 90 $PY -m pip install --break-system-packages -q -i https://pypi.org/simple "certbot>=5.3" >/dev/null 2>&1 || \
  timeout 90 $PY -m pip install -q -i https://pypi.org/simple "certbot>=5.3" >/dev/null 2>&1 || \
  timeout 90 $PY -m pip install --break-system-packages -q "certbot>=5.3" >/dev/null 2>&1 || true
  # pip 可能装了包但没生成 CLI 脚本(偶发), 校验/强制重装补脚本
  local cb="$(command -v certbot 2>/dev/null || true)"
  [ -x "$cb" ] || cb=/usr/local/bin/certbot
  if [ ! -x "$cb" ]; then
    log_progress "      (certbot 脚本未生成, force-reinstall 重试...)"
    timeout 120 $PY -m pip install --force-reinstall -q -i https://pypi.tuna.tsinghua.edu.cn/simple certbot >/dev/null 2>&1 || true
  fi
  # 预编译 python(绝对路径) 的 certbot 在它的 bin 下, 软链到 PATH
  if [[ "$PY" == /* ]] && [ -x "$(dirname "$PY")/certbot" ]; then
    ln -sf "$(dirname "$PY")/certbot" /usr/local/bin/certbot 2>/dev/null || true
  fi
  return 0
}
setup_renew_timer() {
  local cbin; cbin="$(command -v certbot)"
  tee /etc/systemd/system/certbot-renew.service >/dev/null <<EOF
[Unit]
Description=Renew Let's Encrypt short-lived certificates
[Service]
Type=oneshot
ExecStart=$cbin renew --quiet --deploy-hook "systemctl reload nginx"
EOF
  tee /etc/systemd/system/certbot-renew.timer >/dev/null <<EOF
[Unit]
Description=Twice-daily Let's Encrypt renewal
[Timer]
OnCalendar=*-*-* 03,15:23:00
RandomizedDelaySec=1800
Persistent=true
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now certbot-renew.timer >/dev/null 2>&1
}

# ============================================================
echo "======================================================"
echo "   订阅转换服务 · 一键部署   [包管理器: $PM]"
echo "======================================================"
echo "  [!] 建议先手动更新包管理器, 避免安装超时:"
echo "      Debian/Ubuntu:  sudo apt-get update"
echo "      RHEL/AlmaLinux: sudo dnf makecache"
echo "      首次运行如遇超时, 更新后重跑即可。"
echo ""

# ---------- 1. 节点类型 (参数/环境变量优先, 否则交互菜单) ----------
# 支持: bash deploy.sh 'vless://...' ['hysteria2://...']
#       或 SUB_LINK / SUB_LINK2 环境变量; 自动识别协议类型
is_vless_url() { [[ "$1" == vless://* ]]; }
is_hy2_url()   { [[ "$1" == hysteria2://* ]] || [[ "$1" == hy2://* ]]; }

# ---------- 选项4: 自动检测 /etc/sing-box/config.json 出分享链接 ----------
# 仅 singbox 客户端; 健壮性: 检测不到/缺 jq 只提示, 绝不 exit, 回菜单手动粘贴
auto_detect_links() {
  command -v jq >/dev/null 2>&1 || { echo -e "   ${YELLOW}[!]${NC} 未安装 jq, 无法自动检测, 请手动粘贴链接"; return 1; }

  local CONFIG=""
  for c in /etc/sing-box/config.json /etc/sing-box/*.json; do
    [ -f "$c" ] || continue
    if jq -e '.inbounds[] | select(.type=="hysteria2" or .type=="vless")' "$c" >/dev/null 2>&1; then
      CONFIG="$c"; break
    fi
  done
  [ -n "$CONFIG" ] || { echo -e "   ${YELLOW}[!]${NC} 在 /etc/sing-box/ 下未找到 hysteria2/vless 节点配置, 请手动粘贴链接"; return 1; }
  echo -e "   ${GREEN}[OK]${NC} 找到节点配置: $CONFIG"

  local NODE_HOST="$(cat /etc/sing-box/node_host 2>/dev/null || true)"

  # ---- Hysteria2 inbound ----
  local HY2_JSON
  HY2_JSON="$(jq -c '.inbounds[] | select(.type=="hysteria2")' "$CONFIG" 2>/dev/null | head -1 || true)"
  if [ -n "$HY2_JSON" ]; then
    local HPORT HPASS HSNI HALPN HOBFS HOBFSPASS PRANGE HPORT_PART
    HPORT=$(echo "$HY2_JSON" | jq -r '.listen_port' 2>/dev/null || echo "")
    HPASS=$(echo "$HY2_JSON" | jq -r '.users[0].password' 2>/dev/null || echo "")
    HSNI=$(echo "$HY2_JSON" | jq -r '.tls.server_name' 2>/dev/null || echo "")
    HALPN=$(echo "$HY2_JSON" | jq -r '.tls.alpn[0] // "h3"' 2>/dev/null || echo "h3")
    HOBFS=$(echo "$HY2_JSON" | jq -r '.obfs.type // empty' 2>/dev/null || echo "")
    HOBFSPASS=$(echo "$HY2_JSON" | jq -r '.obfs.password // empty' 2>/dev/null || echo "")
    # 端口跳跃: 优先 /etc/sing-box/port_range(hy2 安装时存, 红帽 firewalld 用), 其次 iptables 探测
    PRANGE="$(cat /etc/sing-box/port_range 2>/dev/null || true)"
    if [ -z "$PRANGE" ] && command -v iptables >/dev/null 2>&1; then
      PRANGE="$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep -E "udp.*dpts:[0-9]+:[0-9]+.*redir ports ${HPORT}" | head -1 | grep -oE 'dpts:[0-9]+:[0-9]+' | head -1 | cut -d: -f2 || true)"
    fi
    HPORT_PART="${PRANGE:-$HPORT}"
    if [ -n "$HOBFS" ]; then
      RAW_HY2="hysteria2://${HPASS}@${NODE_HOST:-$HSNI}:${HPORT_PART}/?sni=${HSNI}&alpn=${HALPN}&obfs=${HOBFS}&obfs-password=${HOBFSPASS}#node"
    else
      RAW_HY2="hysteria2://${HPASS}@${NODE_HOST:-$HSNI}:${HPORT_PART}/?sni=${HSNI}&alpn=${HALPN}#node"
    fi
    echo -e "   ${GREEN}[OK]${NC} 自动检测到 Hysteria2 节点${PRANGE:+ (端口跳跃 $PRANGE)}"
  fi

  # ---- VLESS (Reality) inbound ----
  local VLESS_JSON
  VLESS_JSON="$(jq -c '.inbounds[] | select(.type=="vless")' "$CONFIG" 2>/dev/null | head -1 || true)"
  if [ -n "$VLESS_JSON" ]; then
    local VPORT VUUID VFLOW VSNI VSID VPUB
    VPORT=$(echo "$VLESS_JSON" | jq -r '.listen_port' 2>/dev/null || echo "")
    VUUID=$(echo "$VLESS_JSON" | jq -r '.users[0].uuid' 2>/dev/null || echo "")
    VFLOW=$(echo "$VLESS_JSON" | jq -r '.users[0].flow // "xtls-rprx-vision"' 2>/dev/null || echo "xtls-rprx-vision")
    VSNI=$(echo "$VLESS_JSON" | jq -r '.tls.server_name // .tls.reality.handshake.server // ""' 2>/dev/null || echo "")
    VSID=$(echo "$VLESS_JSON" | jq -r '.tls.reality.short_id[0] // .tls.reality.short_id // ""' 2>/dev/null || echo "")
    VPUB="$(cat /etc/sing-box/reality_pub 2>/dev/null || true)"
    if [ -n "$VPUB" ] && [ -n "$VSNI" ] && [ -n "$VUUID" ]; then
      RAW_VLESS="vless://${VUUID}@${NODE_HOST:-$VSNI}:${VPORT}?encryption=none&security=reality&sni=${VSNI}&fp=chrome&pbk=${VPUB}&sid=${VSID}&type=tcp&flow=${VFLOW}#node"
      echo -e "   ${GREEN}[OK]${NC} 自动检测到 VLESS 节点"
    else
      echo -e "   ${YELLOW}[!]${NC} 检测到 VLESS 但缺 Reality 公钥(/etc/sing-box/reality_pub), 该节点请手动粘贴"
    fi
  fi

  [ -n "$RAW_HY2" ] || [ -n "$RAW_VLESS" ] || { echo -e "   ${YELLOW}[!]${NC} 未能生成任何链接, 请手动粘贴"; return 1; }
  return 0
}

RAW_VLESS=""
RAW_HY2=""
# 收集候选链接: 命令行参数优先, 缺省用 SUB_LINK/SUB_LINK2 环境变量
if [ -n "${1:-}" ]; then
  LINK_A="$1"; LINK_B="${2:-}"
else
  LINK_A="${SUB_LINK:-}"; LINK_B="${SUB_LINK2:-}"
fi

if is_vless_url "$LINK_A" && is_hy2_url "$LINK_B"; then
  RAW_VLESS="$LINK_A"; RAW_HY2="$LINK_B"
  echo -e "${CYAN}[1]${NC} 已识别双节点 (VLESS + Hysteria2)"
elif is_hy2_url "$LINK_A" && is_vless_url "$LINK_B"; then
  RAW_VLESS="$LINK_B"; RAW_HY2="$LINK_A"
  echo -e "${CYAN}[1]${NC} 已识别双节点 (VLESS + Hysteria2)"
elif is_vless_url "$LINK_A"; then
  RAW_VLESS="$LINK_A"
  echo -e "${CYAN}[1]${NC} 已识别 VLESS 节点"
elif is_hy2_url "$LINK_A"; then
  RAW_HY2="$LINK_A"
  echo -e "${CYAN}[1]${NC} 已识别 Hysteria2 节点"
elif [ -n "$LINK_A" ]; then
  echo "[!] 链接 '$LINK_A' 无法识别 (需 vless:// 或 hysteria2:// 开头), 进入交互选择"
fi

if [ -z "$RAW_VLESS" ] && [ -z "$RAW_HY2" ]; then
  echo ""
  echo -e "${CYAN}[1]${NC} 节点类型 (${YELLOW}回车=vless, 2=hy2, 3=双, 4=自动${NC}):"
  echo -e "    ${BLUE}1) 仅 VLESS${NC}"
  echo -e "    ${BLUE}2) 仅 Hysteria2${NC} (支持端口跳跃)"
  echo -e "    ${BLUE}3) 双节点${NC} (VLESS + Hysteria2)"
  echo -e "    ${BLUE}4) 自动检测${NC} (读取 /etc/sing-box/config.json, 仅 singbox 客户端)"
  while [ -z "$RAW_VLESS" ] && [ -z "$RAW_HY2" ]; do
    read -rp "   ${CYAN}> ${NC}${YELLOW}(回车/1=vless, 2=hy2, 3=双)${NC}: " NODE_SEL
    case "$NODE_SEL" in
      ""|1)
        read -rp "   ${CYAN}>${NC} 粘贴 VLESS 链接: " RAW_VLESS
        if is_vless_url "$RAW_VLESS"; then
          echo -e "   ${GREEN}[OK]${NC} 仅 VLESS"
        else
          echo -e "   ${RED}[X]${NC} VLESS 链接必须以 vless:// 开头, 重来"; RAW_VLESS=""
        fi
        ;;
      2)
        read -rp "   ${CYAN}>${NC} 粘贴 Hysteria2 链接 (端口跳跃如 host:20000-30000): " RAW_HY2
        if is_hy2_url "$RAW_HY2"; then
          echo -e "   ${GREEN}[OK]${NC} 仅 Hysteria2"
        else
          echo -e "   ${RED}[X]${NC} Hysteria2 链接必须以 hysteria2:// 或 hy2:// 开头, 重来"; RAW_HY2=""
        fi
        ;;
      3)
        read -rp "   ${CYAN}>${NC} 粘贴 VLESS 链接: " RAW_VLESS
        if ! is_vless_url "$RAW_VLESS"; then
          echo -e "   ${RED}[X]${NC} VLESS 链接必须以 vless:// 开头, 重来"; RAW_VLESS=""; continue
        fi
        read -rp "   请粘贴 Hysteria2 链接 (端口跳跃如 host:20000-30000): " RAW_HY2
        if is_hy2_url "$RAW_HY2"; then
          echo "   [OK] 双节点 (VLESS + Hysteria2), 客户端内可切换"
        else
          echo "   [X] Hysteria2 链接必须以 hysteria2:// 或 hy2:// 开头, 重来"; RAW_VLESS=""; RAW_HY2=""
        fi
        ;;
      4)
        echo -e "   ${BLUE}→ 自动检测 /etc/sing-box/config.json${NC}"
        if auto_detect_links; then
          if [ -n "$RAW_VLESS" ] && [ -n "$RAW_HY2" ]; then
            echo "   [OK] 自动检测到双节点 (VLESS + Hysteria2)"
          elif [ -n "$RAW_HY2" ]; then
            echo "   [OK] 自动检测到 Hysteria2"
          elif [ -n "$RAW_VLESS" ]; then
            echo "   [OK] 自动检测到 VLESS"
          fi
        else
          echo "   [i] 检测未成功, 请手动粘贴链接 (或重选菜单)"
        fi
        ;;
      *) echo "   [X] 无效选择 (回车/1=VLESS, 2=HY2, 3=双节点, 4=自动检测)" ;;
    esac
  done
fi

# ---------- 2. 访问方式 ----------
echo ""
echo -e "${CYAN}[2]${NC} 访问方式 (${YELLOW}回车=公网IP, 1/3=域名${NC}):"
echo -e "    ${BLUE}1) 域名 + HTTP-01${NC} (正式证书, 需域名已解析且开放80)"
echo -e "    ${BLUE}2) 公网 IP${NC} (HTTP+HTTPS 双端点, 真证书失败自动回退自签) ${YELLOW}<-- 回车默认${NC}"
echo -e "    ${BLUE}3) 域名 + DNS-01${NC} (正式证书, 不用开80, 需添加 TXT 记录)"
MODE=""
while [ -z "$MODE" ]; do
  read -rp "   ${CYAN}>${NC} ${YELLOW}(回车=公网IP, 1/3=域名)${NC}: " ACCESS
  case "$ACCESS" in
    ""|2)
      read -rp "   ${CYAN}>${NC} 本机公网 IP (${YELLOW}回车=自动检测${NC}): " PUBIP
      if [ -z "$PUBIP" ]; then
        echo "   (正在自动检测公网 IP...)"
        PUBIP=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null || curl -s --max-time 8 ifconfig.me 2>/dev/null || true)
      fi
      if [[ "$PUBIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        MODE=2
      else
        echo -e "   ${RED}[X]${NC} 未取得有效 IP (得到: '$PUBIP'), 请手动输入"
      fi
      ;;
    1|3)
      read -rp "   ${CYAN}>${NC} 域名 (如 sub.example.com): " DOMAIN
      if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
        MODE="$ACCESS"
      else
        echo -e "   ${RED}[X]${NC} 域名格式不对, 重来"
      fi
      ;;
    *) echo -e "   ${RED}[X]${NC} 无效选择, 回车=公网IP / 1或3=域名" ;;
  esac
done

# ---------- 3. HTTPS 端口 (交互确认, 检测占用) ----------
echo ""
while true; do
  read -rp "${CYAN}[3]${NC} HTTPS 端口 (${YELLOW}回车=51200${NC}): " PORT_INPUT
  if [ -n "$PORT_INPUT" ]; then
    if [[ "$PORT_INPUT" =~ ^[0-9]+$ ]] && [ "$PORT_INPUT" -ge 1 ] && [ "$PORT_INPUT" -le 65535 ]; then
      WEB_PORT="$PORT_INPUT"
    else
      echo -e "   ${RED}[X]${NC} 端口无效 (1-65535), 重来"
      continue
    fi
  fi
  if ss -tlnp 2>/dev/null | grep -q ":${WEB_PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${WEB_PORT} "; then
    echo "   [!] 端口 $WEB_PORT 已被占用(可能是网站), 请换一个"
  else
    break
  fi
done

# ---------- HTTP 端口 (交互确认, 检测占用) ----------
HTTP_PORT=$((WEB_PORT + 1))
echo ""
echo -e "   HTTP 端点端口 (${YELLOW}回车=$HTTP_PORT${NC}) ${CYAN}(自签证书直接用此端口导入, 无需跳过验证)${NC}:"
while true; do
  read -rp "   ${CYAN}>${NC} ${YELLOW}(回车=默认)${NC}: " HTTP_INPUT
  if [ -n "$HTTP_INPUT" ]; then
    if [[ "$HTTP_INPUT" =~ ^[0-9]+$ ]] && [ "$HTTP_INPUT" -ge 1 ] && [ "$HTTP_INPUT" -le 65535 ]; then
      HTTP_PORT="$HTTP_INPUT"
    else
      echo -e "   ${RED}[X]${NC} 端口无效 (1-65535), 重来"
      continue
    fi
  fi
  if ss -tlnp 2>/dev/null | grep -q ":${HTTP_PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${HTTP_PORT} "; then
    echo -e "   ${YELLOW}[!]${NC} 端口 $HTTP_PORT 已被占用, 请换一个"
  else
    break
  fi
done
echo -e "   ${GREEN}HTTPS: $WEB_PORT${NC}  |  ${GREEN}HTTP: $HTTP_PORT${NC}"

# ---------- 4. 随机 base64 路径 ----------
B64PATH="$(head -c 18 /dev/urandom | base64 | tr -d '=\n' | tr '/+' '_-')"
echo ""
echo -e "${CYAN}[4]${NC} 已生成随机 base64 路径: ${MAGENTA}/$B64PATH${NC}"

# ---------- 5. 依赖 (仅 nginx + python3) ----------
echo ""
echo -e "${CYAN}[5]${NC} 安装依赖 (仅 nginx, Python3 系统自带无需安装)..."
export DEBIAN_FRONTEND=noninteractive

# 修复之前可能因超时残留的破损包 (仅 Debian)
if [ "$PM" = "apt" ]; then
  dpkg --configure -a 2>/dev/null || true
fi

# 更新包列表
log_progress "  -> 更新包列表..."
timeout 120 $PM_UPDATE || log_progress "  [!] 包列表更新超时, 继续尝试..."

# RedHat: 先启用 EPEL
if [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
  rpm -q epel-release >/dev/null 2>&1 || { log_progress "  -> 安装 EPEL..."; timeout 60 $PM_INSTALL epel-release || true; }
fi

# 安装 nginx (唯一需要装的包)
if ! command -v nginx >/dev/null 2>&1; then
  log_progress "  -> 安装 nginx (唯一依赖, 约2MB, 视网速需1-5分钟)..."
  pkg_install nginx || { echo "[X] nginx 安装失败, 部署中止"; exit 1; }
  log_progress "  [OK] nginx 安装完毕"
else
  log_progress "  [OK] nginx 已就绪"
fi

# certbot (域名模式才需要)
if [ "$MODE" != "2" ] && ! command -v certbot >/dev/null 2>&1; then
  log_progress "  -> 安装 certbot..."
  pkg_install certbot || { echo "[X] certbot 安装失败"; exit 1; }
fi

# 选择 Python: server.py 需要 >=3.7 (ThreadingHTTPServer); EL8 默认 python3=3.6 会崩
# 优先 python3.11(install_certbot_pip 也会装它), 其次满足 3.7+ 的 python3, 都没有则补装
if command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3.11)"
elif python3 -c 'import http.server; assert hasattr(http.server, "ThreadingHTTPServer")' >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
else
  log_progress "  -> 安装 python3.11 (server.py 需要 Python>=3.7, 当前 python3 过旧/缺失)..."
  timeout 180 $PM_INSTALL python3.11 python3.11-pip </dev/null || true
  PYTHON_BIN="$(command -v python3.11 || command -v python3 || true)"
fi
if [ -z "$PYTHON_BIN" ]; then
  echo "[X] 找不到可用的 python3 (需 >=3.7)" >&2
  exit 1
fi
log_progress "  [OK] 基础环境就绪 (nginx + $PYTHON_BIN)"

# 启动 nginx
log_progress "  -> 启动 nginx..."
systemctl enable --now nginx >/dev/null 2>&1 || true
sleep 1
if ! systemctl is-active nginx >/dev/null 2>&1; then
  echo "[X] nginx 启动失败, 日志如下:" >&2
  journalctl -u nginx -n 15 --no-pager >&2 2>&1 || true
  echo "[X] 部署中止 (nginx 未运行, 订阅无法工作)" >&2
  exit 1
fi

# ---------- 6. 应用目录 ----------
mkdir -p "$APP_DIR"
cp "$SCRIPT_DIR/server.py" "$APP_DIR/server.py"
{
  printf '{\n'
  [ -n "$RAW_VLESS" ] && printf '  "rawVlessUrl": "%s",\n' "$RAW_VLESS"
  [ -n "$RAW_HY2" ] && printf '  "rawHy2Url": "%s",\n' "$RAW_HY2"
  printf '  "port": %s\n' "$SRV_PORT"
  printf '}\n'
} > "$APP_DIR/config.json"
chmod 644 "$APP_DIR/config.json" "$APP_DIR/server.py"

# ---------- 6.5 提前放行 80 端口 (LE HTTP-01 验证需要; 否则首次部署证书必失败) ----------
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null 2>&1
  log_progress "   (已提前放行 80/tcp 供证书验证)"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=80/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  log_progress "   (已提前放行 80/tcp 供证书验证)"
fi

# ---------- 7. 证书 ----------
echo -e "${CYAN}[6]${NC} 准备证书..."
CERT=""; CERTKEY=""
REAL_OK=0
case "$MODE" in
  2) # 公网 IP: 优先真证书, 失败回退自签名
    if ! certbot_ge_53; then
      log_progress "   (pip 安装 certbot >=5.3, 首次较慢请耐心等待...)"
      install_certbot_pip
    fi
    if certbot_ge_53; then
      log_progress "   (为公网 IP $PUBIP 申请 Let's Encrypt 证书, 需80端口可公网访问...)"
      if timeout 180 certbot certonly --standalone --ip-address "$PUBIP" \
           --preferred-profile shortlived --preferred-challenges http-01 \
           --non-interactive --agree-tos --register-unsafely-without-email \
           --pre-hook "systemctl stop nginx" \
           --post-hook "systemctl start nginx" \
           --deploy-hook "systemctl reload nginx" >/dev/null 2>&1; then
        CERT_DIR="$(ls -td /etc/letsencrypt/live/*/ 2>/dev/null | head -1)"
        CERT="${CERT_DIR}fullchain.pem"
        CERTKEY="${CERT_DIR}privkey.pem"
        REAL_OK=1
        setup_renew_timer
      else
        log_progress "   [注意] Let's Encrypt 真证书申请失败, 回退自签名证书"
        log_progress "     (常见原因: 云安全组未放行 80 端口 / IP 不可达)"
        systemctl start nginx >/dev/null 2>&1 || true
      fi
    else
      log_progress "   [注意] 无法安装 certbot >=5.3, 使用自签名证书"
    fi
    if [ "$REAL_OK" != "1" ]; then
      mkdir -p /etc/nginx/ssl
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout /etc/nginx/ssl/sub.key -out /etc/nginx/ssl/sub.crt \
        -subj "/CN=$PUBIP" -addext "subjectAltName=IP:$PUBIP" >/dev/null 2>&1
      CERT=/etc/nginx/ssl/sub.crt
      CERTKEY=/etc/nginx/ssl/sub.key
    fi
    ;;
  1) # 域名 + HTTP-01
    mkdir -p /var/www/html
    tee /etc/nginx/conf.d/sub-acme.conf >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 404; }
}
EOF
    nginx -t && systemctl reload nginx
    log_progress "   (certbot HTTP-01 正在为 $DOMAIN 申请证书...)"
    timeout 240 certbot certonly --webroot -w /var/www/html -d "$DOMAIN" \
      --non-interactive --agree-tos --register-unsafely-without-email || {
        echo "[X] certbot 申请失败 (域名解析/80端口放行?)"
        rm -f /etc/nginx/conf.d/sub-acme.conf
        exit 1
      }
    rm -f /etc/nginx/conf.d/sub-acme.conf
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    CERTKEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    REAL_OK=1
    ;;
  3) # 域名 + DNS-01
    echo "   (certbot DNS-01 将为 $DOMAIN 申请证书...)"
    echo "   [注意] 按提示添加 DNS TXT 记录后回车继续"
    timeout 240 certbot certonly --manual --preferred-challenges dns -d "$DOMAIN" \
      --agree-tos --register-unsafely-without-email --manual-public-ip-logging-ok || {
        echo "[X] DNS-01 申请失败, 请检查 TXT 记录"
        exit 1
      }
    CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
    CERTKEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    REAL_OK=1
    ;;
esac

# ---------- 8. nginx 配置 ----------
echo -e "${CYAN}[7]${NC} 写入 nginx 配置..."
case "$MODE" in
  2)
    tee /etc/nginx/conf.d/subscription.conf >/dev/null <<EOF
limit_req_zone \$binary_remote_addr zone=subconv:10m rate=20r/m;

# HTTP (自签证书无需跳过验证, 直接用 http 导入)
server {
    listen $HTTP_PORT;
    server_name _;

    location = /$B64PATH {
        limit_req zone=subconv burst=10 nodelay;
        proxy_pass http://127.0.0.1:$SRV_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
    location / { return 404; }
}

# HTTPS
server {
    listen $WEB_PORT ssl;
    server_name _;
    ssl_certificate     $CERT;
    ssl_certificate_key $CERTKEY;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = /$B64PATH {
        limit_req zone=subconv burst=10 nodelay;
        proxy_pass http://127.0.0.1:$SRV_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
    location / { return 404; }
}
EOF
    ;;
  1|3)
    tee /etc/nginx/conf.d/subscription.conf >/dev/null <<EOF
limit_req_zone \$binary_remote_addr zone=subconv:10m rate=20r/m;

server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 404; }
}

server {
    listen $WEB_PORT ssl;
    server_name $DOMAIN;
    ssl_certificate     $CERT;
    ssl_certificate_key $CERTKEY;
    ssl_protocols TLSv1.2 TLSv1.3;

    location = /$B64PATH {
        limit_req zone=subconv burst=10 nodelay;
        proxy_pass http://127.0.0.1:$SRV_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
    location / { return 404; }
}
EOF
    ;;
esac

nginx -t && systemctl restart nginx 2>/dev/null || true
sleep 1
if ! systemctl is-active nginx >/dev/null 2>&1; then
  echo "[X] nginx 配置应用失败, 日志如下:" >&2
  journalctl -u nginx -n 10 --no-pager >&2 2>&1 || true
  exit 1
fi

# ---------- 9. systemd 服务 ----------
echo -e "${CYAN}[8]${NC} 配置 systemd 服务..."
tee /etc/systemd/system/subconverter.service >/dev/null <<EOF
[Unit]
Description=subconverter subscription converter (VLESS/Hysteria2, Python)
After=network.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$PYTHON_BIN $APP_DIR/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
if [ ! -f /etc/systemd/system/subconverter.service ]; then
  echo "[X] subconverter.service 单元写入失败" >&2
  exit 1
fi
systemctl daemon-reload
systemctl enable --now subconverter.service >/dev/null 2>&1 || true
systemctl restart subconverter.service >/dev/null 2>&1 || true
sleep 2
if ! systemctl is-active subconverter >/dev/null 2>&1; then
  echo "[X] subconverter 服务启动失败, 日志如下:" >&2
  journalctl -u subconverter -n 15 --no-pager >&2 2>&1 || true
  exit 1
fi

# ---------- 10. 防火墙 ----------
echo -e "${CYAN}[9]${NC} 防火墙处理..."
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null 2>&1
  ufw allow "$WEB_PORT/tcp" >/dev/null 2>&1
  ufw allow "$HTTP_PORT/tcp" >/dev/null 2>&1
  echo "   (ufw 已放行 80/tcp, $WEB_PORT/tcp, $HTTP_PORT/tcp)"
elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --permanent --add-port=80/tcp   >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=$WEB_PORT/tcp >/dev/null 2>&1 || true
  firewall-cmd --permanent --add-port=$HTTP_PORT/tcp >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null 2>&1 || true
  echo "   (firewalld 已放行 80/tcp, $WEB_PORT/tcp, $HTTP_PORT/tcp)"
else
  echo "   (未检测到 ufw/firewalld, 请自行确认防火墙/云安全组)"
fi
if [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    command -v semanage >/dev/null 2>&1 || { log_progress "      (安装 SELinux 工具...)"; timeout 120 $PM_INSTALL policycoreutils-python-utils </dev/null || true; }
    setsebool -P httpd_can_network_connect 1 2>/dev/null && echo "   (SELinux: 已允许 nginx 代理本地后端)"
    semanage port -a -t http_port_t -p tcp "$WEB_PORT" 2>/dev/null && echo "   (SELinux: 已放行 $WEB_PORT/tcp)"
    semanage port -a -t http_port_t -p tcp "$HTTP_PORT" 2>/dev/null && echo "   (SELinux: 已放行 $HTTP_PORT/tcp)"
    # SELinux 端口放行后需重载 nginx 才能绑定新端口
    nginx -t && systemctl reload nginx 2>/dev/null || true
  fi
fi

# ---------- 11. 自检 ----------
echo ""
echo -e "${CYAN}[10]${NC} 自检..."
BASE_URL="https://${DOMAIN:-$PUBIP}:${WEB_PORT}"
BASE_URL_HTTP="http://${DOMAIN:-$PUBIP}:${HTTP_PORT}"

CHK=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" -A "sing-box/1.9" "https://127.0.0.1:$WEB_PORT/$B64PATH")
if [ "$CHK" = "200" ]; then
  echo "   [OK] HTTPS 端点正常 (HTTP $CHK)"
else
  echo "   [X] HTTPS 自检失败 (HTTP $CHK), 订阅不可用, 部署中止" >&2
  echo "      (排查: systemctl status nginx / subconverter, journalctl -u subconverter -n 20)" >&2
  exit 1
fi

CHK2=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -A "sing-box/1.9" "http://127.0.0.1:$HTTP_PORT/$B64PATH")
if [ "$CHK2" = "200" ]; then
  echo "   [OK] HTTP 端点正常 (HTTP $CHK2)"
else
  echo "   [X] HTTP 自检失败 (HTTP $CHK2), 订阅不可用, 部署中止" >&2
  exit 1
fi

CHK404=$(curl -sk --max-time 10 -o /dev/null -w "%{http_code}" "https://127.0.0.1:$WEB_PORT/")
[ "$CHK404" = "404" ] && echo "   [OK] 其他路径返回 404, 防扫描生效" || echo "   [注意] 其他路径返回 $CHK404"

# ---------- 12. 输出 ----------
echo ""
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}        ✓ 部署完成 ✓${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
echo ""
if [ "$MODE" = "2" ]; then
  echo -e "  ${GREEN}📥 HTTP 订阅地址${NC} ${YELLOW}(自签证书用这个, 无需跳过验证)${NC}:"
  echo -e "    ${MAGENTA}${BOLD}$BASE_URL_HTTP/$B64PATH${NC}"
  echo ""
  echo -e "  ${GREEN}🔒 HTTPS 订阅地址${NC}:"
  echo -e "    ${MAGENTA}${BOLD}$BASE_URL/$B64PATH${NC}"
else
  echo -e "  ${GREEN}📥 订阅地址${NC} ${YELLOW}(填入客户端, 自动识别格式)${NC}:"
  echo -e "    ${MAGENTA}${BOLD}$BASE_URL/$B64PATH${NC}"
fi
echo ""
echo -e "  ${CYAN}支持客户端:${NC}"
echo -e "    ${BLUE}- sing-box / SFI / SFA${NC} -> 自动返回 JSON 配置"
echo -e "    ${BLUE}- Clash / Mihomo / Stash${NC} -> 自动返回 YAML 配置"
echo -e "    ${BLUE}- v2rayN 等通用订阅${NC} -> 自动返回 base64 订阅"
echo "      (也可用 ?target=singbox 或 ?target=clash 强制指定)"
if [ -n "$RAW_VLESS" ] && [ -n "$RAW_HY2" ]; then
  echo -e "  ${GREEN}[OK]${NC} 已配置双节点 (VLESS + Hysteria2), 客户端内可切换"
elif [ -n "$RAW_HY2" ]; then
  echo -e "  ${GREEN}[OK]${NC} 已配置 Hysteria2 节点"
else
  echo -e "  ${GREEN}[OK]${NC} 已配置 VLESS 节点"
fi
echo ""
echo -e "  ${YELLOW}⚠️  请务必到云控制台安全组放行以下端口:${NC}"
echo -e "      ${BLUE}TCP $WEB_PORT${NC}   [HTTPS 订阅]"
echo -e "      ${BLUE}TCP $HTTP_PORT${NC}  [HTTP 订阅]"
if [ "$MODE" = "1" ] || [ "$MODE" = "3" ] || { [ "$MODE" = "2" ] && [ "$REAL_OK" = "1" ]; }; then
  echo -e "      ${BLUE}TCP 80${NC}          [证书申请/续期]"
fi
echo ""
if [ "$MODE" = "2" ]; then
  if [ "$REAL_OK" = "1" ]; then
    echo -e "  ${GREEN}[OK]${NC} 已为公网 IP $PUBIP 申请 ${GREEN}LE 真证书${NC}, HTTPS 无需跳过验证"
    echo -e "  ${YELLOW}[注意]${NC} 证书有效期约 6.6 天, 自动续期已配置 (certbot-renew.timer)"
  else
    echo -e "  ${YELLOW}[注意]${NC} 自签名证书: HTTPS 需要客户端跳过验证"
    echo -e "      sing-box: tls.insecure=true / Clash: skip-cert-verify: true"
    echo -e "      v2rayN: 勾选跳过证书验证"
    echo -e "      ${YELLOW}**或者直接用 HTTP 端点 (上面第一个链接), 无需任何额外设置**${NC}"
  fi
elif [ "$MODE" = "3" ]; then
  echo -e "  ${YELLOW}[注意]${NC} DNS-01 证书续期需要手动添加 TXT 记录"
fi
echo ""
echo -e "  ${CYAN}如需重置: 重新运行本脚本会生成新路径并覆盖配置。${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"
