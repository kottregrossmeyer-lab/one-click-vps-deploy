#!/bin/bash
# 新VPS一键部署脚本:交互式配置 -> 建用户 -> 装sing-box -> 证书(HY2自签/LE;VLESS免证书) -> 防火墙 -> SSH加固 -> 吐分享链接
# 支持协议: Hysteria2(UDP+端口跳跃) / VLESS+Reality(TCP免证书);支持 Debian/Ubuntu(apt+ufw) 与 RHEL系 Alma/Rocky(dnf+firewalld)
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "请用 root 运行" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色(用 $'...' 存真实 ESC, 让 read -p 和 echo -e 都能正确显示)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# ========== 发行版检测 ==========
OS_ID=$(grep -E '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' | head -1)
case "$OS_ID" in
    debian|ubuntu) OS_FAMILY="debian"; ADMIN_GROUP="sudo" ;;
    rhel|almalinux|rocky|ol|centos|fedora) OS_FAMILY="rhel"; ADMIN_GROUP="wheel" ;;
    *) echo "不支持的系统: ${OS_ID:-未知}" >&2; exit 1 ;;
esac
echo -e "${CYAN}>> 系统: ${OS_ID} (${OS_FAMILY} 系)${NC}"

# ========== 交互式配置 ==========
echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${CYAN}${BOLD}   sing-box 一键部署脚本 (HY2 / VLESS)${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"
echo ""

read -p "创建新用户? (${YELLOW}y=创建, 回车=跳过${NC}): " CREATE_USER
CREATE_USER=${CREATE_USER:-N}
NEW_USER=""
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    while [[ -z "$NEW_USER" ]]; do
        read -p "用户名: " NEW_USER
        NEW_USER=$(echo "$NEW_USER" | xargs)
        if [[ -z "$NEW_USER" ]]; then
            echo "用户名不能为空" >&2
        elif ! [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo "用户名格式不正确(小写字母/数字/-_开头)" >&2
            NEW_USER=""
        fi
    done
    while true; do
        read -sp "新用户密码: " NEW_PASSWORD
        echo ""
        [[ -n "$NEW_PASSWORD" ]] && break
        echo "密码不能为空"
    done
fi

echo ""
echo -e "协议 (${YELLOW}回车=hy2, 2=vless${NC}):"
echo "  hy2   = Hysteria2 (UDP + 端口跳跃)"
echo "  vless = VLESS + Reality (TCP 免证书)"
read -p "> " PROTO
PROTO=${PROTO:-1}
case "${PROTO,,}" in
    hy2|hysteria|hysteria2) PROTO=1 ;;
    vless|reality) PROTO=2 ;;
esac

# 端口输入辅助函数: 校验数字/范围/占用, 非法或占用自动重输
port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tulnp 2>/dev/null | grep -qE "[:.]${port}( |$)"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulnp 2>/dev/null | grep -qE "[:.]${port}( |$)"
    else
        return 1   # 无法检测, 放行
    fi
}
input_port() {
    local prompt="$1" default="$2"
    local -n out="$3"
    local min="${4:-0}"
    local val
    while true; do
        read -p "$prompt (${YELLOW}回车=$default${NC}): " val
        val=${val:-$default}
        if [[ ! "$val" =~ ^[0-9]+$ ]]; then
            echo "  [X] 端口必须是数字, 重新输入" >&2
            continue
        fi
        if (( val < 1 || val > 65535 )); then
            echo "  [X] 端口必须在 1-65535 之间, 重新输入" >&2
            continue
        fi
        if (( val < min )); then
            echo "  [X] 端口不能小于 $min, 重新输入" >&2
            continue
        fi
        if port_in_use "$val"; then
            echo "  [X] 端口 $val 已被占用, 换一个" >&2
            continue
        fi
        out=$val
        return 0
    done
}

# 端口提示按协议区分: HY2 问监听+跳跃结束两个口; VLESS 只问监听
if [[ "$PROTO" == "2" ]]; then
    input_port "VLESS 监听端口" 443 LISTEN_PORT ""
else
    input_port "Hysteria2 监听端口" 443 LISTEN_PORT ""
    input_port "端口跳跃结束端口" 19999 PORT_END "$LISTEN_PORT"
fi

if [[ "$PROTO" == "2" ]]; then
    NODE_UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "已生成 VLESS UUID: $NODE_UUID"
    read -p "Reality 目标网站 (${YELLOW}回车=www.bing.com${NC}): " REALITY_TARGET
    REALITY_TARGET=${REALITY_TARGET:-www.bing.com}
    REALITY_SID=$(openssl rand -hex 4)
    echo "已生成 Reality short_id: $REALITY_SID"
else
    read -p "节点密码 (${YELLOW}回车=自动生成${NC}): " NODE_PASSWORD
    if [[ -z "$NODE_PASSWORD" ]]; then
        NODE_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
        echo "已生成节点密码: $NODE_PASSWORD"
    fi
    read -p "混淆密码 (${YELLOW}回车=自动生成${NC}): " OBFS_PASSWORD
    if [[ -z "$OBFS_PASSWORD" ]]; then
        OBFS_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
        echo "已生成混淆密码: $OBFS_PASSWORD"
    fi
fi

read -p "节点名称 (${YELLOW}回车=node${NC}): " NODE_NAME
NODE_NAME=${NODE_NAME:-node}

# ========== 连接地址 ==========
SERVER_IP=$(curl -s -m 5 -4 ifconfig.me 2>/dev/null || curl -s -m 5 -4 ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')

CERT_MODE="none"
if [[ "$PROTO" == "2" ]]; then
    # VLESS Reality 免证书,只需连接地址
    read -p "节点地址 (${YELLOW}回车=自动检测 $SERVER_IP, 可用域名${NC}): " NODE_HOST
    NODE_HOST=${NODE_HOST:-$SERVER_IP}
else
    echo ""
    echo -e "连接方式 (${YELLOW}回车=ip直连, 2=域名${NC}):"
    echo "  ip    = IP 直连 (自签证书, 客户端导入自动跳过校验)"
    echo "  域名  = 自动申请 LE 真证书 (需域名已解析到本机)"
    read -p "> " CONNECT_MODE
    CONNECT_MODE=${CONNECT_MODE:-1}
    case "${CONNECT_MODE,,}" in
        ip|iplink|直连) CONNECT_MODE=1 ;;
        域名|domain|dns) CONNECT_MODE=2 ;;
    esac

    CERT_MODE="self"
    if [[ "$CONNECT_MODE" == "2" ]]; then
        read -p "域名 (如 node.notebase.cn): " NODE_HOST
        NODE_HOST=$(echo "$NODE_HOST" | xargs)
        [[ -n "$NODE_HOST" ]] || { echo "域名不能为空" >&2; exit 1; }

        if [[ "$NODE_HOST" =~ ^[0-9.]+$ || "$NODE_HOST" =~ ^[0-9a-fA-F:]+$ ]]; then
            echo "!! 输入的是 IP,按 IP 直连处理(自签证书)"
            CERT_MODE="self"
        else
            [[ "$NODE_HOST" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || { echo "域名格式不正确" >&2; exit 1; }
            CERT_MODE="le"

            echo -e "${RED}⚠️  请先将 ${NODE_HOST} 的 A 记录指向本机 IP: ${SERVER_IP}${NC}"
            RESOLVED=$(getent hosts "$NODE_HOST" 2>/dev/null | awk '{print $1}' | head -1)
            if [[ -n "$RESOLVED" && "$RESOLVED" != "$SERVER_IP" ]]; then
                echo -e "${RED}⚠️  警告: ${NODE_HOST} 当前解析到 ${RESOLVED},与本机 ${SERVER_IP} 不一致,证书申请会失败${NC}"
                read -p "继续? (${YELLOW}回车=否, y=强续${NC}): " FORCE
                FORCE=${FORCE:-N}
                [[ "$FORCE" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }
            elif [[ -z "$RESOLVED" ]]; then
                echo -e "${RED}⚠️  警告: ${NODE_HOST} 当前解析不到任何地址,证书申请会失败${NC}"
                read -p "继续? (${YELLOW}回车=否, y=强续${NC}): " FORCE
                FORCE=${FORCE:-N}
                [[ "$FORCE" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }
            else
echo -e "${GREEN}>> 域名已指向本机,可申请证书${NC}"
            fi

            read -p "LE 邮箱 (${YELLOW}回车=admin@$NODE_HOST${NC}): " LE_EMAIL
            LE_EMAIL=${LE_EMAIL:-"admin@$NODE_HOST"}
        fi
    else
        read -p "节点地址 (${YELLOW}回车=自动检测 $SERVER_IP${NC}): " NODE_HOST
        NODE_HOST=${NODE_HOST:-$SERVER_IP}
    fi
fi

# 证书路径(仅HY2需要)
if [[ "$CERT_MODE" == "le" ]]; then
    CERT_PATH="/etc/letsencrypt/live/$NODE_HOST/fullchain.pem"
    KEY_PATH="/etc/letsencrypt/live/$NODE_HOST/privkey.pem"
elif [[ "$CERT_MODE" == "self" ]]; then
    CERT_PATH="/etc/sing-box/self.crt"
    KEY_PATH="/etc/sing-box/self.key"
fi

# ========== SSH 登录方式选择(仅创建用户时需要) ==========
SSH_MODE=""
PUB_KEY=""
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
echo ""
echo -e "SSH 方式 (${YELLOW}回车=密码, 2=密钥${NC}):"
echo "  密码  = 禁止 root, 普通用户密码登录"
echo "  密钥  = 粘贴公钥, 仅密钥登录 (更安全)"
read -p "> " SSH_MODE
SSH_MODE=${SSH_MODE:-1}
case "${SSH_MODE,,}" in
    密码|pass|password) SSH_MODE=1 ;;
    密钥|key|pubkey) SSH_MODE=2 ;;
esac

if [[ "$SSH_MODE" == "2" ]]; then
    while [[ -z "$PUB_KEY" ]]; do
        read -p "粘贴 SSH 公钥 (ssh-ed25519/ssh-rsa 开头): " PUB_KEY
        PUB_KEY=$(echo "$PUB_KEY" | xargs)
        if [[ -n "$PUB_KEY" ]] && ! [[ "$PUB_KEY" =~ ^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519|sk-ecdsa-sha2-nistp256) ]]; then
            echo "公钥格式不正确,请重新粘贴" >&2
            PUB_KEY=""
        fi
    done
echo -e "${GREEN}>> 已记录公钥${NC}"
    fi
else
    echo ">> 未创建用户,跳过 SSH 配置"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}${BOLD}  配置确认：${NC}"
echo -e "${CYAN}  系统: $OS_ID ($OS_FAMILY 系)${NC}"
echo -e "${CYAN}  协议: $([ "$PROTO" = "2" ] && echo "VLESS+Reality (TCP)" || echo "Hysteria2 (UDP+端口跳跃)")${NC}"
echo -e "${CYAN}  用户名: $([ -n "$NEW_USER" ] && echo "$NEW_USER" || echo "(未创建新用户)")${NC}"
echo -e "${CYAN}  监听端口: $LISTEN_PORT${NC}"
if [[ "$PROTO" == "2" ]]; then
    echo -e "${CYAN}  节点地址: $NODE_HOST${NC}"
    echo -e "${CYAN}  UUID: $NODE_UUID${NC}"
    echo -e "${CYAN}  Reality目标: $REALITY_TARGET / short_id: $REALITY_SID${NC}"
else
    echo -e "${CYAN}  端口跳跃: $LISTEN_PORT-$PORT_END${NC}"
    echo -e "${CYAN}  连接方式: $([ "$CERT_MODE" = "le" ] && echo "域名($NODE_HOST,申请LE证书)" || echo "IP直连($NODE_HOST,自签证书)")${NC}"
    echo -e "${CYAN}  节点密码: $NODE_PASSWORD${NC}"
    echo -e "${CYAN}  混淆密码: $OBFS_PASSWORD${NC}"
fi
echo -e "${CYAN}  节点名称: $NODE_NAME${NC}"
echo -e "${CYAN}  SSH 方式: $([ -n "$SSH_MODE" ] && ([ "$SSH_MODE" = "2" ] && echo "密钥登录(已记录公钥)" || echo "密码登录") || echo "跳过(未创建用户)")${NC}"
echo -e "${CYAN}========================================${NC}"
read -p "确认? (${YELLOW}回车=继续, n=取消${NC}): " CONFIRM
CONFIRM=${CONFIRM:-Y}
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "已取消"; exit 1; }

# ========== 1. 创建用户 ==========
echo -e "${CYAN}===== 1. 创建新用户 =====${NC}"
USER_CREATED=0
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    if ! id "$NEW_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$NEW_USER"
        echo "$NEW_USER:${NEW_PASSWORD}" | chpasswd
        echo -e "${GREEN}>> 已创建用户 $NEW_USER${NC}"
    else
        echo -e "${GREEN}>> 用户 $NEW_USER 已存在,跳过创建${NC}"
    fi
    USER_CREATED=1
else
    echo ">> 跳过创建用户 (回车选择)"
fi

# ========== 2. 安装必要软件 ==========
echo -e "${CYAN}===== 2. 安装必要软件 =====${NC}"

# 自动加 swap(小内存<1G + 无swap + 磁盘够时, 防 dnf/apt makecache OOM)
ensure_swap() {
    local mem_mb disk_free_mb
    mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
    # 已有 swap 或内存足够就跳过
    swapon --show 2>/dev/null | grep -q swap && return 0
    [ -n "$mem_mb" ] && [ "$mem_mb" -ge 1024 ] && return 0
    # 磁盘剩余不足 1.5G 就不建
    disk_free_mb=$(df -m / 2>/dev/null | awk 'NR==2{print $4}')
    [ -n "$disk_free_mb" ] && [ "$disk_free_mb" -lt 1536 ] && { echo ">> 磁盘剩余不足, 跳过加 swap"; return 0; }
    echo ">> 内存 ${mem_mb}MB 且无 swap, 创建 1G swapfile 防安装 OOM..."
    dd if=/dev/zero of=/swapfile bs=1M count=1024 2>/dev/null || return 1
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1 || { rm -f /swapfile; return 1; }
    swapon /swapfile >/dev/null 2>&1 || { rm -f /swapfile; return 1; }
    # 写 fstab(幂等, 已存在不重复)
    grep -q "^/swapfile " /etc/fstab 2>/dev/null || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo ">> 已启用 swap"
    return 0
}
ensure_swap

# 等包管理器锁释放(OpenWrt 风格: 最多 N 秒, 超时才优雅停/最后手段 kill)
wait_pkg_lock() {
    local max_wait="$1" waited=0 lock_paths="$2"
echo -e "${GREEN}>> 等待包管理器锁释放 (最多 ${max_wait}s)...${NC}"
    while [[ $waited -lt $max_wait ]]; do
        if ! fuser $lock_paths 2>/dev/null; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo "!! 锁超 ${max_wait}s 未释放, 停用自动更新服务后再等 5s..."
    systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer packagekit dnf-automatic 2>/dev/null || true
    sleep 5
    local holder
    holder=$(fuser $lock_paths 2>/dev/null | awk '{print $1}' | head -1)
    if [[ -n "$holder" ]]; then
        echo "!! 仍有进程持锁 (PID $holder), 强制结束..."
        kill -9 "$holder" 2>/dev/null || true
        sleep 2
    fi
    dpkg --configure -a 2>/dev/null || true
    return 0
}

# 禁用自动更新(代理节点不需要, 避免占锁/半夜重启)
disable_auto_update() {
    if [[ "$OS_FAMILY" == "debian" ]]; then
        systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
        systemctl disable unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    else
        systemctl stop packagekit dnf-automatic 2>/dev/null || true
        systemctl disable packagekit dnf-automatic 2>/dev/null || true
    fi
}

if [[ "$OS_FAMILY" == "debian" ]]; then
    disable_auto_update
    wait_pkg_lock 120 "/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock"
    dpkg --configure -a 2>/dev/null || true
    apt update -qq
    apt install -y sudo ufw jq openssl
else
    disable_auto_update
    wait_pkg_lock 120 "/var/lib/dnf/*.lock"
    # 首次 dnf 元数据下载慢, 预缓存(一次性代价, 之后安装快)
echo -e "${GREEN}>> 首次刷新 dnf 仓库元数据 (视网速需 1-3 分钟, 请稍候)...${NC}"
    timeout 300 dnf -y makecache >/dev/null 2>&1 || true
    dnf install -y epel-release
    # EL9 启用 CRB 以满足部分 EPEL 包依赖(config-manager 缺失时忽略)
    dnf config-manager --set-enabled crb 2>/dev/null || true
    timeout 180 dnf -y makecache >/dev/null 2>&1 || true
    # openssl 已有就不装(避免升级导致 sshd OpenSSL 版本不匹配而锁死)
    command -v openssl >/dev/null 2>&1 || dnf install -y openssl
    dnf install -y sudo jq
    # 保险: 若 sshd 因 OpenSSL 版本不匹配无法启动, 自动重装 openssh-server(防止 root 被锁死)
    if ! systemctl is-active --quiet sshd; then
        systemctl start sshd 2>/dev/null || true
        if ! systemctl is-active --quiet sshd && journalctl -u sshd -n 10 --no-pager 2>/dev/null | grep -q "OpenSSL version mismatch"; then
            echo ">> sshd OpenSSL 版本不匹配, 重装 openssh-server..."
            dnf reinstall -y openssh-server
            systemctl enable --now sshd
        fi
    fi
fi

# ========== 3. 配置免密 sudo(仅创建用户时) ==========
if [[ "$USER_CREATED" == "1" ]]; then
echo -e "${CYAN}===== 3. $NEW_USER 加入 ${ADMIN_GROUP} 组 + 免密 =====${NC}"
    usermod -aG "$ADMIN_GROUP" "$NEW_USER"
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
    chmod 440 "/etc/sudoers.d/$NEW_USER"
    visudo -cf "/etc/sudoers.d/$NEW_USER"
fi

# ========== 4. 配置命令别名(ip 原生彩色,不依赖 grc) ==========
echo -e "${CYAN}===== 4. 配置 ip 彩色别名 =====${NC}"
GRC_ALIASES="alias ip='ip -c'"

for user_home in /root "/home/$NEW_USER"; do
  BASHRC="$user_home/.bashrc"
  if [[ -f "$BASHRC" ]] && ! grep -q "alias ip='ip -c'" "$BASHRC"; then
    echo "" >> "$BASHRC"
    echo "$GRC_ALIASES" >> "$BASHRC"
echo -e "${GREEN}>> 已写入 $BASHRC${NC}"
  fi
done

# ========== 5. 写入用户 SSH 公钥(密钥登录且创建用户时) ==========
if [[ "$SSH_MODE" == "2" && "$USER_CREATED" == "1" ]]; then
echo -e "${CYAN}===== 5. 写入 SSH 公钥给 $NEW_USER =====${NC}"
  mkdir -p "/home/$NEW_USER/.ssh"
  echo "$PUB_KEY" > "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 700 "/home/$NEW_USER/.ssh"
  chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
echo -e "${GREEN}>> SSH 公钥已写入 $NEW_USER${NC}"
fi

# ========== 6. 部署 sing-box ==========
echo -e "${CYAN}===== 6. 部署 sing-box =====${NC}"
mkdir -p /etc/sing-box
if [[ "$OS_FAMILY" == "rhel" ]]; then
echo -e "${GREEN}>> RHEL 在线安装 sing-box ...${NC}"
    case "$(uname -m)" in
        x86_64) SB_ARCH="amd64" ;;
        aarch64) SB_ARCH="arm64" ;;
        *) echo "不支持的架构: $(uname -m)" >&2; exit 1 ;;
    esac
    # 优先从 hk 自家域名拉(国内快);GitHub 兜底
    if ! curl -fSL -o /tmp/sing-box.tar.gz "https://mirror.notebase.cn/bundle/singbox/sing-box-linux-${SB_ARCH}.tar.gz"; then
echo -e "${GREEN}>> hk 下载失败,回退 GitHub ...${NC}"
        SB_VERSION=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
        SB_VER=${SB_VERSION#v}
        curl -fSL -o /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${SB_VERSION}/sing-box-${SB_VER}-linux-${SB_ARCH}.tar.gz" \
            || curl -fSL -o /tmp/sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/${SB_VERSION}/sing-box-${SB_VER}-linux-${SB_ARCH}-glibc.tar.gz"
    fi
    tar xzf /tmp/sing-box.tar.gz -C /tmp
    # hk 包内层直接是 sing-box 二进制;GitHub 包带版本目录,find 兜底
    SBIN=$(find /tmp -maxdepth 3 -name sing-box -type f 2>/dev/null | head -1)
    [[ -n "$SBIN" ]] || { echo "!! 未找到 sing-box 二进制" >&2; exit 1; }
    install -m 755 "$SBIN" /usr/bin/sing-box
    rm -f /tmp/sing-box.tar.gz
else
    install -m 755 "$SCRIPT_DIR/bin/sing-box" /usr/bin/sing-box
fi

# VLESS Reality 密钥对 + 记录连接地址
if [[ "$PROTO" == "2" ]]; then
echo -e "${GREEN}>> 生成 Reality 密钥对 ...${NC}"
    KEYPAIR=$(sing-box generate reality-keypair)
    REALITY_PRV=$(echo "$KEYPAIR" | awk '/PrivateKey/{print $2}')
    REALITY_PUB=$(echo "$KEYPAIR" | awk '/PublicKey/{print $2}')
    echo "$REALITY_PUB" > /etc/sing-box/reality_pub
else
    echo "${LISTEN_PORT}-${PORT_END}" > /etc/sing-box/port_range
fi
echo "$NODE_HOST" > /etc/sing-box/node_host

# ========== 7. 配置证书(HY2需要;VLESS免) ==========
echo -e "${CYAN}===== 7. 配置证书 =====${NC}"
if [[ "$CERT_MODE" == "none" ]]; then
echo -e "${GREEN}>> VLESS Reality 免证书${NC}"
elif [[ "$CERT_MODE" == "le" ]]; then
echo -e "${GREEN}>> 正在申请 Let's Encrypt 证书 ($NODE_HOST) ...${NC}"
    if [[ "$OS_FAMILY" == "debian" ]]; then apt install -y certbot; else dnf install -y certbot; fi
    if certbot certonly --standalone --non-interactive --agree-tos -m "$LE_EMAIL" \
        -d "$NODE_HOST" --deploy-hook "systemctl try-restart sing-box"; then
echo -e "${GREEN}>> LE 证书已颁发: $NODE_HOST${NC}"
    else
        echo -e "${RED}!! LE 证书申请失败,回退自签证书(客户端导入链接自动跳过证书校验)${NC}"
        CERT_MODE="self"
        CERT_PATH="/etc/sing-box/self.crt"
        KEY_PATH="/etc/sing-box/self.key"
    fi
fi
if [[ "$CERT_MODE" == "self" ]]; then
    if [[ "$NODE_HOST" =~ ^[0-9.]+$ || "$NODE_HOST" =~ ^[0-9a-fA-F:]+$ ]]; then
        SAN="IP:$NODE_HOST"
    else
        SAN="DNS:$NODE_HOST"
    fi
echo -e "${GREEN}>> 生成自签证书 ($SAN, 3650天) ...${NC}"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$KEY_PATH" -out "$CERT_PATH" \
        -subj "/CN=$NODE_HOST" -addext "subjectAltName=$SAN"
fi

# ========== 8. 修改并部署 sing-box 配置 ==========
echo -e "${CYAN}===== 8. 修改并部署 sing-box 配置 =====${NC}"
if [[ "$PROTO" == "2" ]]; then
    cp "$SCRIPT_DIR/sing-box/config-vless.json" /etc/sing-box/config.json
    TMP_CONFIG=$(mktemp)
    jq --arg lp "$LISTEN_PORT" --arg uid "$NODE_UUID" --arg sn "$REALITY_TARGET" \
       --arg pk "$REALITY_PRV" --arg sid "$REALITY_SID" \
       '(.inbounds[0].listen_port) = ($lp | tonumber)
        | (.inbounds[0].users[0].uuid) = $uid
        | (.inbounds[0].tls.server_name) = $sn
        | (.inbounds[0].tls.reality.handshake.server) = $sn
        | (.inbounds[0].tls.reality.private_key) = $pk
        | (.inbounds[0].tls.reality.short_id[0]) = $sid' \
       /etc/sing-box/config.json > "$TMP_CONFIG"
    mv "$TMP_CONFIG" /etc/sing-box/config.json
else
    cp "$SCRIPT_DIR/sing-box/config.json" /etc/sing-box/config.json
    TMP_CONFIG=$(mktemp)
    jq --arg lp "$LISTEN_PORT" \
       --arg np "$NODE_PASSWORD" \
       --arg op "$OBFS_PASSWORD" \
       --arg sn "$NODE_HOST" \
       --arg cert "$CERT_PATH" \
       --arg key "$KEY_PATH" \
       '(.inbounds[0].listen_port) = ($lp | tonumber)
        | (.inbounds[0].users[0].password) = $np
        | (.inbounds[0].obfs.password) = $op
        | (.inbounds[0].tls.server_name) = $sn
        | (.inbounds[0].tls.certificate_path) = $cert
        | (.inbounds[0].tls.key_path) = $key' \
       /etc/sing-box/config.json > "$TMP_CONFIG"
    mv "$TMP_CONFIG" /etc/sing-box/config.json
fi

# ========== 9. 部署 systemd service 并启动 ==========
echo -e "${CYAN}===== 9. 部署 systemd service 并启动 =====${NC}"
cp "$SCRIPT_DIR/systemd/sing-box.service" /etc/systemd/system/sing-box.service
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

sleep 2
if ! systemctl is-active --quiet sing-box; then
  echo "!! sing-box 启动失败，日志如下：" >&2
  journalctl -u sing-box -n 30 --no-pager
  exit 1
fi
echo -e "${GREEN}>> sing-box 已启动${NC}"

# ========== 10-12. 配置防火墙 ==========
if [[ "$OS_FAMILY" == "debian" ]]; then
echo -e "${CYAN}===== 10. 配置 ufw 端口 =====${NC}"
    ufw allow 22/tcp
    if [[ "$PROTO" == "2" ]]; then
        ufw allow "${LISTEN_PORT}/tcp"
    else
        ufw allow "${LISTEN_PORT}:${PORT_END}/udp"
        if [[ "$CERT_MODE" == "le" ]]; then
            ufw allow 80/tcp   # certbot http-01 续期需要
        fi

echo -e "${CYAN}===== 11. 写入 NAT 端口跳跃规则 =====${NC}"
        BEFORE_RULES=/etc/ufw/before.rules
        if [[ -f "$BEFORE_RULES" ]]; then
          sed -i '/^\*nat$/,/^COMMIT$/d' "$BEFORE_RULES"
        fi
        TMP=$(mktemp)
        cat << NAT_EOF > "$TMP"
*nat
:PREROUTING ACCEPT [0:0]
-A PREROUTING -p udp --dport ${LISTEN_PORT}:${PORT_END} -j REDIRECT --to-ports ${LISTEN_PORT}
COMMIT
NAT_EOF
        if [[ -f "$BEFORE_RULES" ]]; then
          cat "$TMP" "$BEFORE_RULES" > "${BEFORE_RULES}.new"
          mv "${BEFORE_RULES}.new" "$BEFORE_RULES"
        else
          cat "$TMP" "$SCRIPT_DIR/ufw/before.rules.orig" > "$BEFORE_RULES"
        fi
        rm -f "$TMP"
    fi
echo -e "${CYAN}===== 12. 启用 ufw =====${NC}"
    ufw --force enable
    ufw reload
else
echo -e "${CYAN}===== 10. 配置 firewalld =====${NC}"
    if ! systemctl is-active --quiet firewalld; then
        dnf install -y firewalld
        systemctl enable --now firewalld
    fi
    firewall-cmd --permanent --add-service=ssh   # 兜底防锁死
    if [[ "$PROTO" == "2" ]]; then
        firewall-cmd --permanent --add-port="${LISTEN_PORT}/tcp"
    else
        # 清掉旧的 UDP 端口跳跃规则(重跑换端口时避免残留指向旧口)
        for old_rule in $(firewall-cmd --permanent --list-forward-ports 2>/dev/null | grep "proto=udp"); do
            firewall-cmd --permanent --remove-forward-port="$old_rule" >/dev/null 2>&1 || true
        done
        firewall-cmd --permanent --add-masquerade
        firewall-cmd --permanent --add-forward-port="port=${LISTEN_PORT}-${PORT_END}:proto=udp:toport=${LISTEN_PORT}"
        firewall-cmd --permanent --add-port="${LISTEN_PORT}-${PORT_END}/udp"
        firewall-cmd --permanent --add-port="${LISTEN_PORT}/udp"
        if [[ "$CERT_MODE" == "le" ]]; then
            firewall-cmd --permanent --add-port=80/tcp
        fi
    fi
    firewall-cmd --reload
fi

# ========== 13. SSH 安全加固(仅创建用户时) ==========
if [[ "$USER_CREATED" == "1" ]]; then
echo -e "${CYAN}===== 13. SSH 安全加固 =====${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

# 两种模式都禁止 root 任何方式 SSH 登录
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
grep -q "^PermitRootLogin" "$SSHD_CONFIG" || echo "PermitRootLogin no" >> "$SSHD_CONFIG"

if [[ "$SSH_MODE" == "2" ]]; then
    # 密钥登录:仅允许密钥
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG"
    grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
    grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG" || echo "ChallengeResponseAuthentication no" >> "$SSHD_CONFIG"
echo -e "${GREEN}>> SSH 已加固：禁止 root 登录、仅允许密钥登录${NC}"
else
    # 密码登录:禁止 root,允许普通用户密码
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD_CONFIG"
    grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
    grep -q "^ChallengeResponseAuthentication" "$SSHD_CONFIG" || echo "ChallengeResponseAuthentication yes" >> "$SSHD_CONFIG"
echo -e "${GREEN}>> SSH 已加固：禁止 root 任何方式登录,普通用户可密码登录${NC}"
fi

# 两种模式都保留公钥认证
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
grep -q "^PubkeyAuthentication" "$SSHD_CONFIG" || echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"

systemctl restart sshd
else
    echo ">> 跳过 SSH 加固 (未创建新用户, 保持原 SSH 访问)"
fi

# ========== 14. 生成分享链接 ==========
echo -e "${CYAN}===== 14. 生成分享链接 =====${NC}"
chmod +x "$SCRIPT_DIR/get_link.sh"
SHARE_LINK=$("$SCRIPT_DIR/get_link.sh" "$NODE_NAME")
echo ""
echo -e "${CYAN}${BOLD}========================================${NC}"
echo -e "${GREEN}${BOLD}        ✓ 节点部署完成 ✓${NC}"
echo -e "${CYAN}${BOLD}========================================${NC}"
echo ""
echo -e "  ${GREEN}📥 分享链接 ${YELLOW}(填入客户端, 自动识别协议)${NC}:"
echo -e "    ${MAGENTA}${BOLD}${SHARE_LINK}${NC}"
echo ""

echo ""
echo -e "${CYAN}===== 部署完成 =====${NC}"
if [[ "$USER_CREATED" == "1" ]]; then
    echo "$NEW_USER 密码: ${NEW_PASSWORD}"
fi
echo "sing-box 状态: $(systemctl is-active sing-box)"
if [[ "$OS_FAMILY" == "debian" ]]; then
    echo "ufw 状态: $(ufw status | head -1)"
else
    echo "firewalld 状态: $(systemctl is-active firewalld)"
fi

# ========== 15. (SERVER_IP 已在连接地址处检测) ==========
SERVER_IP=${SERVER_IP:-$(curl -s -m 5 -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')}

# ========== 16. 询问是否生成订阅链接 ==========
echo ""
read -p "生成订阅链接? (${YELLOW}回车=是, n=否${NC}): " GEN_SUB
GEN_SUB=${GEN_SUB:-Y}

if [[ "$GEN_SUB" =~ ^[Yy]$ ]]; then
echo -e "${GREEN}>> 正在拉取并执行订阅配置脚本...${NC}"
  # 先清掉残留(旧文件/目录都会让 curl 写失败报 23)
  rm -rf /tmp/setup.sh
  if curl -fsSL -o /tmp/setup.sh https://mirror.notebase.cn/download/setup.sh; then
    # setup.sh 只认位置参数 $1(不读 SUB_LINK 环境变量),按前缀自动识别协议
    if [[ -n "$SHARE_LINK" ]]; then
      sudo bash /tmp/setup.sh "$SHARE_LINK"
    else
      sudo bash /tmp/setup.sh
    fi
  else
    echo "!! 订阅脚本下载失败，跳过此步" >&2
  fi
fi

# ========== 17. 恢复自动更新(部署期间已暂停防占锁) ==========
echo ""
echo -e "${CYAN}===== 17. 恢复系统自动更新 =====${NC}"
if [[ "$OS_FAMILY" == "debian" ]]; then
    systemctl enable --now unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null
echo -e "${GREEN}>> 已恢复: unattended-upgrades + apt-daily 定时更新${NC}"
else
    systemctl enable --now packagekit dnf-automatic 2>/dev/null || true
echo -e "${GREEN}>> 已恢复: packagekit + dnf-automatic${NC}"
fi

echo ""
echo -e "${YELLOW}${BOLD}⚠️  SSH 访问提醒:${NC}"
if [[ "$USER_CREATED" == "0" ]]; then
    echo -e "${YELLOW}⚠️  未创建新用户,请用 root 或已有用户登录${NC}"
elif [[ "$SSH_MODE" == "2" ]]; then
    echo -e "${YELLOW}⚠️  密码登录已关闭,请先测试密钥登录: ssh ${NEW_USER}@${SERVER_IP}${NC}"
else
    echo -e "${YELLOW}⚠️  root 已禁止登录,请用新用户密码登录: ssh ${NEW_USER}@${SERVER_IP}${NC}"
fi
echo -e "${YELLOW}⚠️  确认能正常登录后再关闭当前会话，避免被锁在门外${NC}"
