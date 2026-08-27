#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
LOG_FILE="${LOG_DIR}/vm-create-$(date +%Y%m%d-%H%M%S).log"
CRED_FILE=""
NORMAL_EXIT=0
DNS_FIX_SCRIPT=""
DNS_FIX_SVC=""

exec > >(tee -a "$LOG_FILE") 2>&1

tput smcup 2>/dev/null || printf '\033[?1049h'

BG='\033[48;5;235m'
FG='\033[38;5;255m'
printf "${BG}${FG}"

rows=$(tput lines)
cols=$(tput cols)
for ((i=0; i<rows; i++)); do
    printf "%${cols}s\n" ""
done
tput cup 0 0

cleanup_screen() {
    printf '\033[0m'
    tput rmcup 2>/dev/null || printf '\033[?1049l'
    rm -f /tmp/mod_*.qcow2 2>/dev/null
    if [[ $NORMAL_EXIT -ne 1 ]]; then
        echo -e "\n\033[1;33mScript did not complete normally. Check the log file for details:\033[0m"
        echo "   Log file: $LOG_FILE"
        if [[ -n "$CRED_FILE" && -f "$CRED_FILE" ]]; then
            echo "   Credentials: $CRED_FILE"
        fi
        echo -e "\n\033[1;33m残留检查(如需):\033[0m"
        echo "   sudo qm status <VMID>   # 检查是否有半成品 VM, 用 qm destroy <VMID> 清理"
        echo "   ls /tmp/mod_*.qcow2     # 定制镜像副本(退出时已自动清理)"
    fi
}
trap cleanup_screen EXIT

C_RESET='\033[0m\033[48;5;235m\033[38;5;255m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_CYAN='\033[36m'
C_BRIGHT_RED='\033[1;31m'
C_BRIGHT_GREEN='\033[1;32m'
C_BRIGHT_YELLOW='\033[1;33m'
C_BRIGHT_BLUE='\033[1;34m'
C_BRIGHT_MAGENTA='\033[1;35m'
C_BRIGHT_CYAN='\033[1;36m'

STEP_WIDTH=76

strip_ansi() {
    local rendered
    rendered=$(printf '%b' "$1")
    sed 's/\x1b\[[0-9;]*m//g' <<< "$rendered"
}

visible_width() {
    local str="$1"
    local width=""
    if command -v python3 &>/dev/null; then
        width=$(python3 -c "import unicodedata, sys; s=sys.argv[1]; print(sum(2 if unicodedata.east_asian_width(c) in ('F','W') else 1 for c in s))" "$str" 2>/dev/null)
    elif command -v perl &>/dev/null; then
        width=$(perl -CSA -Mutf8 -e '
            my $s = shift;
            my $wide = () = $s =~ /\p{East_Asian_Width=Wide}|\p{East_Asian_Width=Fullwidth}|\p{Emoji_Presentation}/g;
            print length($s) + $wide;
        ' "$str" 2>/dev/null)
    fi
    if [[ -z "$width" ]]; then
        width=$(LC_ALL=en_US.UTF-8 wc -L 2>/dev/null <<< "$str" | tr -d '[:space:]')
    fi
    if [[ -z "$width" ]]; then
        width=${#str}
    fi
    echo "$width"
}

box_top() {
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s┌" ""
    printf '─%.0s' $(seq 1 $((STEP_WIDTH - 2)))
    printf "┐\n"
}

box_sep() {
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s├" ""
    printf '─%.0s' $(seq 1 $((STEP_WIDTH - 2)))
    printf "┤\n"
}

box_bottom() {
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s└" ""
    printf '─%.0s' $(seq 1 $((STEP_WIDTH - 2)))
    printf "┘\n"
}

box_line() {
    local text="$1"
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    local right_col=$((pad + STEP_WIDTH))
    printf "%${pad}s│ %b" "" "$text"
    printf "\033[%dG│\n" "$right_col"
}

box_line_center() {
    local text="$1"
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    local stripped
    stripped=$(echo -e "$text" | sed "s/\x1b\[[0-9;]*m//g")
    local visible_len=$(visible_width "$stripped")
    local content_width=$((STEP_WIDTH - 2))
    local total_space=$((content_width - visible_len))
    [ "$total_space" -lt 0 ] && total_space=0
    local left_space=$((total_space / 2))
    local right_space=$((total_space - left_space))
    local right_col=$((pad + STEP_WIDTH))
    printf "%${pad}s│" ""
    printf "%${left_space}s%b%${right_space}s" "" "$text" ""
    printf "\033[%dG│\n" "$right_col"
}

plain_line() {
    local text="$1"
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s%b\n" "" "$text"
}

run_with_countdown() {
    local countdown="$1" label="$2" logfile="$3"
    shift 3
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    local SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local si=0
    "$@" >"$logfile" 2>&1 &
    local pid=$!
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt $countdown ] && kill -0 $pid 2>/dev/null; do
        local remaining=$((countdown - (SECONDS - start)))
        [ $remaining -lt 0 ] && remaining=0
        printf "\r%${pad}s\033[K${C_BRIGHT_BLUE} ${label}... ${SPIN[$si]}${C_RESET}  ${C_DIM}剩余 %d 秒${C_RESET}" "" "$remaining"
        si=$(( (si+1) % ${#SPIN[@]} ))
        sleep 1
    done
    if kill -0 $pid 2>/dev/null; then
        printf "\r%${pad}s\033[K${C_BRIGHT_YELLOW} ${label}已超时, 仍在等待...${C_RESET}" ""
    fi
    local rc=0
    if wait $pid; then
        rc=0
    else
        rc=$?
    fi
    printf "\r\033[K"
    return $rc
}

box_blank() {
    box_line ""
}

box_input() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local cols=$(tput cols)
    local pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s│ %b" "" "$prompt"
    read -r REPLY
    if [ -n "$default" ]; then
        printf -v "$var_name" '%s' "${REPLY:-$default}"
    else
        printf -v "$var_name" '%s' "$REPLY"
    fi
}

ISO_DIR="/var/lib/vz/template/iso"
STORAGE="vm-storage"
DATA_STORAGE="vm-storage"

logo_lines=(
    "${C_BRIGHT_RED}███╗   ██╗${C_BRIGHT_GREEN}███████╗${C_BRIGHT_YELLOW}██╗  ██╗${C_BRIGHT_MAGENTA}██║   ██║${C_BRIGHT_CYAN}███████╗${C_RESET}"
    "${C_BRIGHT_RED}████╗  ██║${C_BRIGHT_GREEN}██╔════╝${C_BRIGHT_YELLOW}╚██╗██╔╝${C_BRIGHT_MAGENTA}██║   ██║${C_BRIGHT_CYAN}██╔════╝${C_RESET}"
    "${C_BRIGHT_RED}██╔██╗ ██║${C_BRIGHT_GREEN}█████╗  ${C_BRIGHT_YELLOW} ╚███╔╝ ${C_BRIGHT_MAGENTA}██║   ██║${C_BRIGHT_CYAN}███████╗${C_RESET}"
    "${C_BRIGHT_RED}██║╚██╗██║${C_BRIGHT_GREEN}██╔══╝  ${C_BRIGHT_YELLOW} ██╔██╗ ${C_BRIGHT_MAGENTA}██║   ██║${C_BRIGHT_CYAN}╚════██║${C_RESET}"
    "${C_BRIGHT_RED}██║ ╚████║${C_BRIGHT_GREEN}███████╗${C_BRIGHT_YELLOW}██╔╝ ██╗${C_BRIGHT_MAGENTA}╚██████╔╝${C_BRIGHT_CYAN}███████║${C_RESET}"
    "${C_BRIGHT_RED}╚═╝  ╚═══╝${C_BRIGHT_GREEN}╚══════╝${C_BRIGHT_YELLOW}╚═╝  ╚═╝${C_BRIGHT_MAGENTA} ╚═════╝ ${C_BRIGHT_CYAN}╚══════╝${C_RESET}"
)
clear
rows=$(tput lines)
cols=$(tput cols)
logo_rows=7
for ((i=0; i<(rows-logo_rows)/2; i++)); do
    printf "%${cols}s\n" ""
done
for line in "${logo_lines[@]}"; do
    stripped=$(strip_ansi "$line")
    width=$(visible_width "$stripped")
    tcols=$(tput cols)
    pad=$(( (tcols - width) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s%b\n" "" "$line"
done
echo ""

sleep 3

clear
printf "${BG}${FG}"

box_top
box_line_center "${C_BRIGHT_CYAN}Interactive VM creation script${C_RESET}"
box_sep
box_line "  ${C_BRIGHT_GREEN}[+]${C_RESET} Debian 12 · Debian 13"
box_line "  ${C_BRIGHT_GREEN}[+]${C_RESET} Ubuntu 22.04 · Ubuntu 24.04"
box_line "  ${C_BRIGHT_GREEN}[+]${C_RESET} Rocky 9 · AlmaLinux 9 · CentOS Stream 9"
box_line "  ${C_YELLOW}[-]${C_RESET} 其他 Linux (基础环境预置DHCP,系统配置需通过串口手动完成)"
box_line "  ${C_DIM}已验证环境: Proxmox Virtual Environment 8.4.19 · 内核 6.8.12-28-pve${C_RESET}"
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 0${C_BRIGHT_CYAN} · 环境检查${C_RESET}"
box_sep
if ! command -v virt-customize &>/dev/null; then
    box_line "${C_YELLOW}[!]  未找到 virt-customize，正在安装 libguestfs-tools ...${C_RESET}"
    box_bottom
    apt update >/dev/null 2>&1 && apt install -y libguestfs-tools >/dev/null 2>&1
    box_top
    box_line "${C_GREEN}[OK] libguestfs-tools 安装完成${C_RESET}"
    box_bottom
else
    box_line "${C_GREEN}[OK] virt-customize 已就绪${C_RESET}"
    box_bottom
fi

box_top
box_line "${C_BRIGHT_RED}步骤 1${C_BRIGHT_CYAN} · 选择镜像${C_RESET}"
box_sep
box_line "${C_BRIGHT_BLUE}扫描镜像文件 (${ISO_DIR})...${C_RESET}"
mapfile -t ISO_LIST < <(find "$ISO_DIR" -maxdepth 1 -type f \( -name "*.iso" -o -name "*.qcow2" -o -name "*.img" \) -exec basename {} \;)
if [ ${#ISO_LIST[@]} -eq 0 ]; then
    box_line "${C_RED}[ERR] 错误: 在 ${ISO_DIR} 下未找到任何镜像！${C_RESET}"
    exit 1
fi

box_blank
box_line "${C_BRIGHT_BLUE}可用的系统镜像列表:${C_RESET}"
box_blank

for i in "${!ISO_LIST[@]}"; do
    filename="${ISO_LIST[$i]}"
    box_line "   ${C_CYAN}[${i}]${C_RESET} ${C_BRIGHT_YELLOW}${filename}${C_RESET}"
done

box_blank
while true; do
    box_input "${C_BRIGHT_BLUE}请输入对应编号 [0-$(( ${#ISO_LIST[@]} - 1 ))] (默认=0): ${C_RESET}" ISO_CHOICE "0"
    if [[ "$ISO_CHOICE" =~ ^[0-9]+$ ]] && [ "$ISO_CHOICE" -lt "${#ISO_LIST[@]}" ]; then
        SELECTED_ISO="${ISO_LIST[$ISO_CHOICE]}"
        SELECTED_PATH="${ISO_DIR}/${SELECTED_ISO}"
        box_line "${C_GREEN}>> 已选择: ${C_BRIGHT_YELLOW}${SELECTED_ISO}${C_RESET}"
        break
    else
        box_line "${C_YELLOW}[!] 输入编号无效，请重新输入。${C_RESET}"
    fi
done

box_blank
IS_DEBIAN_QCOW=0
IS_RHEL_QCOW=0
IS_UBUNTU_QCOW=0
IS_IMG=0
if [[ "$SELECTED_ISO" == *.img ]]; then
    IS_IMG=1
    box_line "${C_YELLOW}[!]  检测到 .img 镜像，跳过注入与扩容，直接启动${C_RESET}"
elif [[ "$SELECTED_ISO" == *.iso ]]; then
    box_line "${C_YELLOW}[!]  检测到 .iso 安装镜像，跳过注入，直接启动虚拟机${C_RESET}"
else
    box_line "${C_BRIGHT_BLUE} 检测镜像真实系统 (virt-cat /etc/os-release)...${C_RESET}"
    OS_RELEASE=$(virt-cat -a "$SELECTED_PATH" /etc/os-release 2>/dev/null || true)
    if [ -n "$OS_RELEASE" ]; then
        OS_ID=$(echo "$OS_RELEASE" | grep -E '^ID=' | head -1 | cut -d= -f2- | tr -d '"' | tr 'A-Z' 'a-z' || true)
        OS_CODENAME=$(echo "$OS_RELEASE" | grep -E '^VERSION_CODENAME=' | head -1 | cut -d= -f2- | tr -d '"' || true)
        case "$OS_ID" in
            ubuntu)
                IS_UBUNTU_QCOW=1
                box_line "${C_GREEN}[OK] 检测到 Ubuntu，将进行离线注入${C_RESET}" ;;
            debian)
                IS_DEBIAN_QCOW=1
                box_line "${C_GREEN}[OK] 检测到 Debian 系镜像，将进行离线注入${C_RESET}" ;;
            almalinux|rocky|centos|rhel|fedora)
                IS_RHEL_QCOW=1
                box_line "${C_GREEN}[OK] 检测到 RedHat 系镜像 (dnf/yum)，将进行离线注入${C_RESET}" ;;
            *)
                box_line "${C_YELLOW}[!]  未知系统镜像，跳过注入，直接启动虚拟机${C_RESET}" ;;
        esac
    else
        box_line "${C_YELLOW}[!]  无法读取镜像系统信息，跳过注入，直接启动虚拟机${C_RESET}"
    fi
fi
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 2${C_BRIGHT_CYAN} · 存储空间检测${C_RESET}"
box_sep
box_line "${C_BRIGHT_BLUE}当前可用空间:${C_RESET}"
STORAGE_FREE=$(pvesm status -content images 2>/dev/null | awk 'NR>1 && $3=="active" {printf "   %-14s 可用 %.1f G\n", $1, $6/1048576}' || true)
mapfile -t STORAGE_ARR <<< "$STORAGE_FREE"
if [ "${#STORAGE_ARR[@]}" -gt 0 ]; then
    for sline in "${STORAGE_ARR[@]}"; do
        box_line "${C_DIM}${sline}${C_RESET}"
    done
else
    box_line "  ${C_DIM}(未能获取存储信息)${C_RESET}"
fi
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 3${C_BRIGHT_CYAN} · 虚拟机 ID${C_RESET}"
box_sep
while true; do
    box_input "${C_BRIGHT_BLUE}VMID（回车自动分配）: ${C_RESET}" VMID_INPUT ""
    if [[ -z "$VMID_INPUT" ]]; then
        VMID=$(pvesh get /cluster/nextid)
        box_line "${C_GREEN}>> 自动分配 VMID: ${VMID}${C_RESET}"
        break
    elif [[ "$VMID_INPUT" =~ ^[0-9]+$ ]] && [ "$VMID_INPUT" -ge 100 ]; then
        if qm status "$VMID_INPUT" &>/dev/null; then
            box_line "${C_YELLOW}  [!] VMID ${VMID_INPUT} 已存在，请换一个${C_RESET}"
        else
            VMID=$VMID_INPUT
            box_line "${C_GREEN}>> VMID: ${VMID}${C_RESET}"
            break
        fi
    else
        box_line "${C_YELLOW}  请输入 100 以上的数字${C_RESET}"
    fi
done
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 4${C_BRIGHT_CYAN} · 基本规格${C_RESET}"
box_sep
box_input "${C_BRIGHT_BLUE}主机名 (默认 vm-${VMID}): ${C_RESET}" HOSTNAME "vm-${VMID}"
box_input "${C_BRIGHT_BLUE}CPU 核数 (默认 4): ${C_RESET}" CORES "4"
box_input "${C_BRIGHT_BLUE}内存大小 (MB, 默认 2048): ${C_RESET}" MEM "2048"
if [ "$IS_IMG" -eq 1 ]; then
    DEFAULT_DISK=0
else
    DEFAULT_DISK=4
fi
box_input "${C_BRIGHT_BLUE}系统盘大小 (GB, 默认 ${DEFAULT_DISK}): ${C_RESET}" DISK "${DEFAULT_DISK}"
box_input "${C_BRIGHT_BLUE}数据盘大小 (GB, 0=不要, 默认 0): ${C_RESET}" DATA_DISK "0"
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 5${C_BRIGHT_CYAN} · 网桥与 MAC 配置${C_RESET}"
box_sep
box_line "${C_BRIGHT_BLUE} 自动检测宿主网桥...${C_RESET}"
mapfile -t BRIDGE_LIST < <(ip -o link show type bridge 2>/dev/null | awk -F'[ :]+' '{print $2}' | grep '^vmbr')
if [ ${#BRIDGE_LIST[@]} -eq 0 ]; then
    box_line "${C_RED}[ERR] 未检测到任何 vmbr 网桥，请先在 PVE 网络里创建网桥再运行！${C_RESET}"
    box_bottom
    exit 1
fi
box_blank
box_line "${C_BRIGHT_BLUE}检测到 ${#BRIDGE_LIST[@]} 个网桥，请选择:${C_RESET}"
box_blank
for i in "${!BRIDGE_LIST[@]}"; do
    BR_NAME="${BRIDGE_LIST[$i]}"
    BR_IP=$(ip -4 -o addr show dev "$BR_NAME" 2>/dev/null | awk '{print $4}' | head -1)
    if [ -n "$BR_IP" ]; then
        box_line "   ${C_CYAN}[$i]${C_RESET} ${C_BRIGHT_YELLOW}${BR_NAME}${C_RESET}  ${C_DIM}(${BR_IP})${C_RESET}"
    else
        box_line "   ${C_CYAN}[$i]${C_RESET} ${C_BRIGHT_YELLOW}${BR_NAME}${C_RESET}"
    fi
done
box_blank
LAST_BR_IDX=$(( ${#BRIDGE_LIST[@]} - 1 ))
NET0_ARG=""
NET1_ARG=""
while true; do
    box_input "${C_BRIGHT_BLUE}选择主网桥 [0-$LAST_BR_IDX] (回车=0): ${C_RESET}" BR_CHOICE "0"
    if [[ "$BR_CHOICE" =~ ^[0-9]+$ ]] && [ "$BR_CHOICE" -le "$LAST_BR_IDX" ]; then
        NET0_ARG="virtio,bridge=${BRIDGE_LIST[$BR_CHOICE]}"
        box_line "${C_GREEN}>> 主网桥: ${C_BRIGHT_YELLOW}${BRIDGE_LIST[$BR_CHOICE]}${C_RESET}"
        break
    else
        box_line "${C_YELLOW}[!] 无效选择，请输入 0-$LAST_BR_IDX${C_RESET}"
    fi
done
box_blank
box_input "${C_BRIGHT_BLUE}是否添加第二网卡(双网桥)? (y/N, 回车=N): ${C_RESET}" ADD_NET1 "n"
if [[ "$ADD_NET1" =~ ^[Yy]$ ]]; then
    box_line "${C_BRIGHT_BLUE}选择第二网桥:${C_RESET}"
    for i in "${!BRIDGE_LIST[@]}"; do
        BR_NAME="${BRIDGE_LIST[$i]}"
        marker=""
        [ "$BR_NAME" = "${NET0_ARG##*=}" ] && marker=" (已选)"
        box_line "   ${C_CYAN}[$i]${C_RESET} ${C_BRIGHT_YELLOW}${BR_NAME}${C_RESET}${C_DIM}${marker}${C_RESET}"
    done
    box_blank
    while true; do
        box_input "${C_BRIGHT_BLUE}选择第二网桥 [0-$LAST_BR_IDX] (回车=取消): ${C_RESET}" BR_CHOICE2 ""
        if [ -z "$BR_CHOICE2" ]; then
            box_line "${C_YELLOW}>> 已取消第二网卡${C_RESET}"
            NET1_ARG=""
            break
        elif [[ "$BR_CHOICE2" =~ ^[0-9]+$ ]] && [ "$BR_CHOICE2" -le "$LAST_BR_IDX" ]; then
            BR1="${BRIDGE_LIST[$BR_CHOICE2]}"
            if [ "$BR1" = "${NET0_ARG##*=}" ]; then
                box_line "${C_YELLOW}[!] 不能与主网桥相同，请重新选择${C_RESET}"
            else
                NET1_ARG="virtio,bridge=${BR1}"
                box_line "${C_GREEN}>> 第二网桥: ${C_BRIGHT_YELLOW}${BR1}${C_RESET}"
                break
            fi
        else
            box_line "${C_YELLOW}[!] 无效选择，请输入 0-$LAST_BR_IDX${C_RESET}"
        fi
    done
fi
box_line "${C_GREEN}>> 网桥配置: net0=${NET0_ARG} ${NET1_ARG:+net1=${NET1_ARG}}${C_RESET}"
box_blank
box_line "${C_BRIGHT_BLUE}MAC 地址配置:${C_RESET}"
box_line "${C_YELLOW}   留空回车将自动生成标准的随机 MAC。${C_RESET}"
while true; do
    box_input "${C_BRIGHT_BLUE}自定义 MAC 地址 (回车=自动生成): ${C_RESET}" MAC_INPUT ""
    if [[ -z "$MAC_INPUT" ]]; then
        MAC_ADDR=$(printf 'BC:24:11:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
        box_line "${C_GREEN}>> 已自动生成 MAC: ${MAC_ADDR}${C_RESET}"
        break
    elif [[ "$MAC_INPUT" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        MAC_ADDR=$(echo "$MAC_INPUT" | tr 'a-f' 'A-F')
        box_line "${C_GREEN}>> 使用自定义 MAC: ${MAC_ADDR}${C_RESET}"
        break
    else
        box_line "${C_YELLOW}[!] 格式不正确，应为 XX:XX:XX:XX:XX:XX，请重试。${C_RESET}"
    fi
done
NET0_ARG="${NET0_ARG},macaddr=${MAC_ADDR}"
BR0="${NET0_ARG#virtio,bridge=}"
BR0="${BR0%%,macaddr=*}"
BR1=""
[ -n "$NET1_ARG" ] && BR1="${NET1_ARG#virtio,bridge=}"
box_line "${C_GREEN}>> 最终网卡: ${C_BRIGHT_YELLOW}${BR0}${C_RESET} (${MAC_ADDR})${NET1_ARG:+${C_GREEN} + ${C_BRIGHT_YELLOW}${BR1}${C_RESET}}${C_RESET}"
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 6${C_BRIGHT_CYAN} · 网络 IP 模式${C_RESET}"
box_sep
box_line "${C_BRIGHT_BLUE}网络 IP 模式:${C_RESET}"
STATIC_IP=""
GATEWAY=""
DNS1=""
DNS2=""
if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    box_line "${C_CYAN}  0) DHCP (自动获取)${C_RESET}"
    box_line "${C_CYAN}  1) 静态 IP (手动填写)${C_RESET}"
    box_input "${C_BRIGHT_BLUE}请输入 [0/1] (回车=0): ${C_RESET}" IP_MODE "0"
else
    box_line "${C_YELLOW}  [!] 此镜像未定制，仅支持 DHCP 自动获取 IP${C_RESET}"
    IP_MODE=0
fi
if [ "$IP_MODE" -eq 1 ]; then
    while true; do
        box_input "${C_BRIGHT_BLUE}请输入静态 IP (如 10.10.10.10/24): ${C_RESET}" IP_INPUT ""
        if [[ -z "$IP_INPUT" ]]; then
            box_line "${C_YELLOW}[!] IP 地址不能为空，请重新输入。${C_RESET}"
            continue
        fi
        if [[ "$IP_INPUT" =~ / ]]; then
            STATIC_IP="$IP_INPUT"
            break
        else
            box_input "${C_BRIGHT_BLUE}请输入掩码位数 (回车=24): ${C_RESET}" CIDR_INPUT "24"
            if [[ "$CIDR_INPUT" =~ ^[0-9]+$ ]] && [ "$CIDR_INPUT" -ge 0 ] && [ "$CIDR_INPUT" -le 32 ]; then
                STATIC_IP="${IP_INPUT}/${CIDR_INPUT}"
                break
            else
                box_line "${C_YELLOW}[!] 掩码位数必须在 0-32 之间，请重新输入。${C_RESET}"
            fi
        fi
    done
    box_input "${C_BRIGHT_BLUE}请输入默认网关 (如 10.10.10.1): ${C_RESET}" GATEWAY ""
    box_input "${C_BRIGHT_BLUE}请输入首选 DNS (回车=223.5.5.5): ${C_RESET}" DNS1 "223.5.5.5"
    box_input "${C_BRIGHT_BLUE}请输入备用 DNS (回车=119.29.29.29): ${C_RESET}" DNS2 "119.29.29.29"
fi
box_bottom

if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 7${C_BRIGHT_CYAN} · 用户与密码 (自动生成强密码)${C_RESET}"
    box_sep
    box_input "${C_BRIGHT_BLUE}新用户名 (默认 admin): ${C_RESET}" NEW_USER "admin"
    if command -v openssl &>/dev/null; then
        NEW_PASS=$(openssl rand -base64 12 | tr -d '=')
    else
        NEW_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    fi
    box_line "${C_GREEN}[OK] 已为用户 ${NEW_USER} 生成 16 位强密码${C_RESET}"

    CRED_FILE="${LOG_DIR}/vm${VMID}-credentials.txt"
    {
        echo "VMID: $VMID"
        echo "Hostname: $HOSTNAME"
        echo "Username: $NEW_USER"
        echo "Password: $NEW_PASS"
    } > "$CRED_FILE"
    chmod 600 "$CRED_FILE"

    box_bottom
else
    NEW_USER=""
    NEW_PASS=""
fi

if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 8${C_BRIGHT_CYAN} · SSH 密钥登录 (可选)${C_RESET}"
    box_sep
    box_input "${C_BRIGHT_BLUE}是否配置 SSH 密钥登录？(y/N): ${C_RESET}" ENABLE_SSH_ASK "n"
    if [[ "$ENABLE_SSH_ASK" =~ ^[Yy]$ ]]; then
        box_line "${C_BRIGHT_BLUE}请粘贴 SSH 公钥（支持 Ctrl+V / 鼠标右键）:${C_RESET}"
        box_line "${C_YELLOW} 粘贴后内容会自动隐藏，直接按 Enter 回车即可${C_RESET}"
        box_sep

        printf "   ${C_BRIGHT_YELLOW}请粘贴公钥: ${C_RESET}\n"
        read -rs SSH_PUBKEY
        printf '\033[1A\033[2K'
        if [ -n "$SSH_PUBKEY" ]; then
            box_line "${C_DIM}   （已接收 ${#SSH_PUBKEY} 个字符）${C_RESET}"
        fi

        if [[ "$SSH_PUBKEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-) ]]; then
            ENABLE_SSH_KEY=1

            KEY_TYPE=$(echo "$SSH_PUBKEY" | awk '{print $1}')
            KEY_BODY=$(echo "$SSH_PUBKEY" | awk '{print $2}')
            KEY_COMMENT=$(echo "$SSH_PUBKEY" | awk '{print $3}')

            SHORT_KEY="${KEY_TYPE} ${KEY_BODY:0:10}...${KEY_BODY: -6} ${KEY_COMMENT}"

            box_line "${C_GREEN} 已识别公钥: ${C_BRIGHT_YELLOW}${SHORT_KEY}${C_RESET}"
            box_line "${C_GREEN}[OK] SSH 密钥登录已启用${C_RESET}"
        else
            box_line "${C_YELLOW}[!]  公钥格式无效或为空，改用默认密码登录。${C_RESET}"
            ENABLE_SSH_KEY=0
        fi
        box_bottom
    else
        ENABLE_SSH_KEY=0
        box_line "${C_YELLOW}[!]  未配置 SSH 密钥，使用密码登录。${C_RESET}"
        box_bottom
    fi
else
    ENABLE_SSH_KEY=0
fi

EXTRA_PACKAGES=""
if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED} 额外预装${C_BRIGHT_CYAN} · 可选${C_RESET}"
    box_sep
    box_line "${C_BRIGHT_BLUE}默认已预装:${C_RESET}"
    if [ "$IS_DEBIAN_QCOW" -eq 1 ]; then
        box_line "  ${C_DIM}qemu-guest-agent curl wget git htop vim nano tmux${C_RESET}"
        box_line "  ${C_DIM}net-tools dnsutils unzip lsof grc iftop btop${C_RESET}"
        box_line "  ${C_DIM}rsync jq tree tcpdump sysstat netcat ifupdown${C_RESET}"
    elif [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
        box_line "  ${C_DIM}qemu-guest-agent curl wget git htop vim nano tmux${C_RESET}"
        box_line "  ${C_DIM}net-tools dnsutils unzip lsof grc iftop btop locales${C_RESET}"
        box_line "  ${C_DIM}rsync jq tree tcpdump sysstat netcat-openbsd${C_RESET}"
    else
        box_line "  ${C_DIM}qemu-guest-agent curl wget git htop vim-enhanced nano tmux${C_RESET}"
        box_line "  ${C_DIM}net-tools bind-utils unzip lsof util-linux-user iftop btop${C_RESET}"
        box_line "  ${C_DIM}rsync jq tree tcpdump sysstat ncat${C_RESET}"
    fi
    box_blank
    box_input "${C_BRIGHT_BLUE}需要额外安装软件？(y/N, 回车=N): ${C_RESET}" ADD_EXTRA "n"
    if [[ "$ADD_EXTRA" =~ ^[Yy]$ ]]; then
        box_input "${C_BRIGHT_BLUE}请输入软件包名(逗号/空格分隔): ${C_RESET}" EXTRA_PACKAGES ""
        EXTRA_PACKAGES=$(echo "$EXTRA_PACKAGES" | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
        if [ -n "$EXTRA_PACKAGES" ]; then
            box_line "${C_GREEN}>> 将额外安装: ${C_BRIGHT_YELLOW}${EXTRA_PACKAGES}${C_RESET}"
        else
            box_line "${C_YELLOW}[!]  未输入包名，跳过额外安装${C_RESET}"
        fi
    fi
    box_bottom
fi

# 磁盘空间检查（离线定制需复制镜像到 /tmp + virt-customize 临时空间）
if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    IMG_SIZE=$(stat -c%s "$SELECTED_PATH" 2>/dev/null || echo 0)
    TMP_FREE=$(df --output=avail -B1 /tmp 2>/dev/null | tail -1 | tr -d ' ')
    if [ "$TMP_FREE" -lt $((IMG_SIZE + 1073741824)) ]; then
        box_top
        box_line "${C_RED}[ERR] /tmp 空间不足，无法离线定制${C_RESET}"
        box_line "  镜像 ${SELECTED_ISO} 大小 $((IMG_SIZE / 1048576))M，需额外 ~1G 临时空间"
        box_line "  /tmp 仅剩 $((TMP_FREE / 1048576))M"
        box_line "${C_YELLOW}  请清理 /tmp 或释放根分区后重试${C_RESET}"
        box_bottom
        exit 1
    fi
fi

FINAL_IMPORT_PATH="$SELECTED_PATH"
if [ "$IS_DEBIAN_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 9${C_BRIGHT_CYAN} · 离线镜像定制 (virt-customize)${C_RESET}"
    box_sep
    box_line "${C_BRIGHT_BLUE}>> [1/4] 离线修改镜像中...${C_RESET}"
    box_line "${C_YELLOW} 正在离线定制镜像，通常需要 2-3 分钟，请耐心等待...${C_RESET}"

    TMP_IMG="/tmp/mod_${VMID}.qcow2"
    cp "$SELECTED_PATH" "$TMP_IMG"

    VIRT_CUSTOMIZE_OPTS=(
        -a "$TMP_IMG"
        --hostname "$HOSTNAME"
        --root-password "password:$NEW_PASS"
        --run-command "rm -f /etc/apt/sources.list && touch /etc/apt/sources.list"
        --run-command "rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources"
        --run-command "cat > /etc/apt/sources.list.d/debian.sources << 'EOF'
Types: deb
URIs: http://mirrors.tuna.tsinghua.edu.cn/debian
Suites: ${OS_CODENAME} ${OS_CODENAME}-updates ${OS_CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: ${OS_CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF"
        --run-command "apt-get update"
        --install "qemu-guest-agent,curl,wget,git,htop,vim,nano,tmux,net-tools,dnsutils,unzip,lsof,grc,iftop,btop,ifupdown,locales,rsync,jq,tree,tcpdump,sysstat,netcat-openbsd"
        --run-command "sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen && locale-gen"
        --run-command "systemctl enable qemu-guest-agent"
        --run-command "sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&net.ifnames=0 biosdevname=0 /' /etc/default/grub && update-grub"
        --run-command "useradd -m -N $NEW_USER 2>/dev/null || true; echo '$NEW_USER:$NEW_PASS' | chpasswd && usermod -aG sudo $NEW_USER && chsh -s /bin/bash $NEW_USER"
        --run-command "echo '$HOSTNAME' > /etc/hostname"
        --run-command "cat >> /home/$NEW_USER/.bashrc << 'BASHEOF'
alias ip='grc ip'
export PS1='\[\033[01;32m\]\u@\H\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
BASHEOF"
        --run-command "touch /etc/cloud/cloud-init.disabled || true"
        --run-command "ssh-keygen -A"
    )

    if [ "$ENABLE_SSH_KEY" -eq 1 ]; then
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /home/$NEW_USER/.ssh && echo '$SSH_PUBKEY' > /home/$NEW_USER/.ssh/authorized_keys && chmod 700 /home/$NEW_USER/.ssh && chmod 600 /home/$NEW_USER/.ssh/authorized_keys && chown -R $NEW_USER: /home/$NEW_USER/.ssh"
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
            --run-command "systemctl enable ssh"
        )
    else
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
        )
    fi

    if [ -n "$STATIC_IP" ]; then
        DNS_FIX_SCRIPT="/usr/local/sbin/fix-resolv-conf.sh"
        DNS_FIX_SVC="fix-resolv-conf.service"
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address ${STATIC_IP}
    gateway ${GATEWAY}
EOF"
            --run-command "systemctl disable --now systemd-networkd 2>/dev/null || true"
            --run-command "systemctl disable --now systemd-resolved 2>/dev/null || true"
            --run-command "systemctl mask systemd-resolved 2>/dev/null || true"
            --run-command "cat > /usr/local/sbin/fix-resolv-conf.sh << 'FIXEOF'
chattr -i /etc/resolv.conf 2>/dev/null || true
rm -f /etc/resolv.conf
cat > /etc/resolv.conf << DNS_EOF
nameserver ${DNS1}
nameserver ${DNS2}
DNS_EOF
chattr +i /etc/resolv.conf 2>/dev/null || true
FIXEOF"
            --run-command "chmod +x /usr/local/sbin/fix-resolv-conf.sh"
            --run-command "cat > /etc/systemd/system/fix-resolv-conf.service << 'SVCEOF'
[Unit]
Description=Force static DNS into resolv.conf on first real boot
DefaultDependencies=no
After=local-fs.target
Before=network-pre.target sysinit.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/sbin/fix-resolv-conf.sh
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
SVCEOF"
            --run-command "systemctl enable fix-resolv-conf.service"
        )
    else
        DNS_FIX_SCRIPT="/usr/local/sbin/fix-resolv-conf-dhcp.sh"
        DNS_FIX_SVC="fix-resolv-conf-dhcp.service"
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF"
            --run-command "systemctl disable --now systemd-networkd 2>/dev/null || true"
            --run-command "systemctl mask systemd-networkd 2>/dev/null || true"
            --run-command "systemctl disable --now systemd-resolved 2>/dev/null || true"
            --run-command "systemctl mask systemd-resolved 2>/dev/null || true"
            --run-command "cat > /usr/local/sbin/fix-resolv-conf-dhcp.sh << 'FIXEOF'
mkdir -p /run/systemd/resolve
touch /run/systemd/resolve/stub-resolv.conf 2>/dev/null || true
chattr -i /etc/resolv.conf 2>/dev/null || true
if [ -e /etc/resolv.conf ] || [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf
fi
install -m 644 /dev/null /etc/resolv.conf
cat > /etc/resolv.conf << DNS_EOF
nameserver ${DNS1}
nameserver ${DNS2}
DNS_EOF
FIXEOF"
            --run-command "chmod +x /usr/local/sbin/fix-resolv-conf-dhcp.sh"
            --run-command "cat > /etc/systemd/system/fix-resolv-conf-dhcp.service << 'SVCEOF'
[Unit]
Description=Ensure resolv.conf is a plain writable file before dhclient runs on first real boot
DefaultDependencies=no
After=local-fs.target
Before=networking.service
Requires=local-fs.target
Conflicts=shutdown.target

[Service]
Type=oneshot
ExecStart=/bin/bash /usr/local/sbin/fix-resolv-conf-dhcp.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF"
            --run-command "systemctl enable fix-resolv-conf-dhcp.service"
        )
    fi

    VC_LOG="${LOG_DIR}/virt-customize-${VMID}.log"
    if ! run_with_countdown 200 "离线定制" "$VC_LOG" virt-customize "${VIRT_CUSTOMIZE_OPTS[@]}"; then
        box_line "${C_RED}[ERR] virt-customize 修改失败，请检查镜像或日志。${C_RESET}"
        box_line "${C_YELLOW}   详细错误: ${VC_LOG}${C_RESET}"
        box_bottom
        tail -n 40 "$VC_LOG"
        rm -f "$TMP_IMG"
        exit 1
    fi
    FINAL_IMPORT_PATH="$TMP_IMG"
    box_line "${C_GREEN}[OK] 离线定制完成${C_RESET}"
    box_bottom
elif [ "$IS_RHEL_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 9${C_BRIGHT_CYAN} · 离线镜像定制 (virt-customize / RedHat)${C_RESET}"
    box_sep
    box_line "${C_BRIGHT_BLUE}>> [1/4] 离线修改镜像中...${C_RESET}"
    box_line "${C_YELLOW} 正在离线定制镜像，通常需要 2-3 分钟，请耐心等待...${C_RESET}"

    TMP_IMG="/tmp/mod_${VMID}.qcow2"
    cp "$SELECTED_PATH" "$TMP_IMG"

    case "$OS_ID" in
        almalinux)
            REPO_BASE="http://mirrors.huaweicloud.com/almalinux/\$releasever"
            REPO_KEY="RPM-GPG-KEY-AlmaLinux-9" ;;
        rocky)
            REPO_BASE="http://mirrors.ustc.edu.cn/rocky/\$releasever"
            REPO_KEY="RPM-GPG-KEY-Rocky-9" ;;
        centos)
            REPO_BASE="http://mirrors.tuna.tsinghua.edu.cn/centos-stream/9-stream"
            REPO_KEY="RPM-GPG-KEY-centosofficial" ;;
        *)
            REPO_BASE="http://mirrors.huaweicloud.com/almalinux/\$releasever"
            REPO_KEY="RPM-GPG-KEY-AlmaLinux-9" ;;
    esac

    VIRT_CUSTOMIZE_OPTS=(
        -a "$TMP_IMG"
        --hostname "$HOSTNAME"
        --root-password "password:$NEW_PASS"
        --run-command "rm -f /etc/yum.repos.d/*.repo"
        --run-command "cat > /etc/yum.repos.d/nexus.repo << 'EOF'
[baseos]
name=BaseOS
baseurl=${REPO_BASE}/BaseOS/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${REPO_KEY}

[appstream]
name=AppStream
baseurl=${REPO_BASE}/AppStream/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${REPO_KEY}

[crb]
name=CRB
baseurl=${REPO_BASE}/CRB/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/${REPO_KEY}
EOF"
        --run-command "cat > /etc/yum.repos.d/epel.repo << 'EOF'
[epel]
name=Extra Packages for Enterprise Linux
baseurl=http://mirrors.tuna.tsinghua.edu.cn/epel/9/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9
EOF"
        --run-command "curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9 http://mirrors.tuna.tsinghua.edu.cn/epel/RPM-GPG-KEY-EPEL-9 && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-9"
        --run-command "dnf clean all && dnf makecache"
        --run-command "dnf install -y qemu-guest-agent curl wget git htop vim-enhanced nano tmux net-tools bind-utils unzip lsof util-linux-user glibc-langpack-zh iftop btop rsync jq tree tcpdump sysstat nmap-ncat"
        --run-command "systemctl enable qemu-guest-agent"
        --run-command "sed -i s/^SELINUX=enforcing/SELINUX=permissive/ /etc/selinux/config"
        --run-command "sed -i 's/^GRUB_CMDLINE_LINUX=\"/&net.ifnames=0 biosdevname=0 /' /etc/default/grub && grub2-mkconfig -o /boot/grub2/grub.cfg"
        --run-command "useradd -m -N $NEW_USER 2>/dev/null || true; echo '$NEW_USER:$NEW_PASS' | chpasswd && usermod -aG wheel $NEW_USER && chsh -s /bin/bash $NEW_USER"
        --run-command "echo '$HOSTNAME' > /etc/hostname"
        --run-command "cat >> /home/$NEW_USER/.bashrc << 'BASHEOF'
command -v grc >/dev/null 2>&1 && alias ip='grc ip'
export PS1='\[\033[01;32m\]\u@\H\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
BASHEOF"
        --run-command "touch /etc/cloud/cloud-init.disabled || true"
        --run-command "ssh-keygen -A"
    )

    if [ "$ENABLE_SSH_KEY" -eq 1 ]; then
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /home/$NEW_USER/.ssh && echo '$SSH_PUBKEY' > /home/$NEW_USER/.ssh/authorized_keys && chmod 700 /home/$NEW_USER/.ssh && chmod 600 /home/$NEW_USER/.ssh/authorized_keys && chown -R $NEW_USER: /home/$NEW_USER/.ssh"
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
            --run-command "systemctl enable sshd"
        )
    else
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
        )
    fi

    if [ -n "$STATIC_IP" ]; then
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /etc/NetworkManager/system-connections && cat > /etc/NetworkManager/system-connections/eth0.nmconnection << 'EOF'
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true
autoconnect-priority=100

[ipv4]
method=manual
address1=${STATIC_IP},${GATEWAY}
dns=${DNS1};${DNS2}

[ipv6]
method=auto
EOF"
            --run-command "chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection"
            --run-command "systemctl enable NetworkManager"
        )
    else
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /etc/NetworkManager/system-connections && cat > /etc/NetworkManager/system-connections/eth0.nmconnection << 'EOF'
[connection]
id=eth0
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
EOF"
            --run-command "chmod 600 /etc/NetworkManager/system-connections/eth0.nmconnection"
            --run-command "systemctl enable NetworkManager"
        )
    fi

    VC_LOG="${LOG_DIR}/virt-customize-${VMID}.log"
    if ! run_with_countdown 200 "离线定制" "$VC_LOG" virt-customize --selinux-relabel "${VIRT_CUSTOMIZE_OPTS[@]}"; then
        box_line "${C_RED}[ERR] virt-customize 修改失败，请检查镜像或日志。${C_RESET}"
        box_line "${C_YELLOW}   详细错误: ${VC_LOG}${C_RESET}"
        box_bottom
        tail -n 40 "$VC_LOG"
        rm -f "$TMP_IMG"
        exit 1
    fi
    FINAL_IMPORT_PATH="$TMP_IMG"
    box_line "${C_GREEN}[OK] 离线定制完成${C_RESET}"
    box_bottom
elif [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 9${C_BRIGHT_CYAN} · 离线镜像定制 (virt-customize / Ubuntu)${C_RESET}"
    box_sep
    box_line "${C_BRIGHT_BLUE}>> [1/4] 离线修改镜像中...${C_RESET}"
    box_line "${C_YELLOW} 正在离线定制镜像，通常需要 2-3 分钟，请耐心等待...${C_RESET}"

    TMP_IMG="/tmp/mod_${VMID}.qcow2"
    cp "$SELECTED_PATH" "$TMP_IMG"

    VIRT_CUSTOMIZE_OPTS=(
        -a "$TMP_IMG"
        --hostname "$HOSTNAME"
        --root-password "password:$NEW_PASS"
        --run-command "rm -f /etc/apt/sources.list && touch /etc/apt/sources.list"
        --run-command "rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources"
        --run-command "cat > /etc/apt/sources.list.d/ubuntu.sources << 'EOF'
Types: deb
URIs: http://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: ${OS_CODENAME} ${OS_CODENAME}-updates ${OS_CODENAME}-backports ${OS_CODENAME}-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF"
        --run-command "apt-get update"
        --install "qemu-guest-agent,curl,wget,git,htop,vim,nano,tmux,net-tools,dnsutils,unzip,lsof,grc,iftop,btop,locales,rsync,jq,tree,tcpdump,sysstat,netcat-openbsd"
        --run-command "systemctl enable qemu-guest-agent"
        --run-command "sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=\"/&net.ifnames=0 biosdevname=0 /' /etc/default/grub && update-grub"
        --run-command "useradd -m -N $NEW_USER 2>/dev/null || true; echo '$NEW_USER:$NEW_PASS' | chpasswd && usermod -aG sudo $NEW_USER && chsh -s /bin/bash $NEW_USER"
        --run-command "echo '$HOSTNAME' > /etc/hostname"
        --run-command "cat >> /home/$NEW_USER/.bashrc << 'BASHEOF'
command -v grc >/dev/null 2>&1 && alias ip='grc ip'
export PS1='\[\033[01;32m\]\u@\H\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
BASHEOF"
        --run-command "touch /etc/cloud/cloud-init.disabled || true"
        --run-command "ssh-keygen -A"
        --run-command "systemctl enable ssh"
    )

    if [ "$ENABLE_SSH_KEY" -eq 1 ]; then
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /home/$NEW_USER/.ssh && echo '$SSH_PUBKEY' > /home/$NEW_USER/.ssh/authorized_keys && chmod 700 /home/$NEW_USER/.ssh && chmod 600 /home/$NEW_USER/.ssh/authorized_keys && chown -R $NEW_USER: /home/$NEW_USER/.ssh"
            --run-command "rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
        )
    else
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "rm -f /etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
            --run-command "sed -i '/^PasswordAuthentication/d' /etc/ssh/sshd_config && echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
            --run-command "sed -i '/^PermitRootLogin/d' /etc/ssh/sshd_config && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config"
        )
    fi

    if [ -n "$STATIC_IP" ]; then
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /etc/netplan && cat > /etc/netplan/01-netcfg.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      match:
        driver: virtio_net
      dhcp4: false
      addresses: [${STATIC_IP}]
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS1}, ${DNS2}]
EOF"
        )
    else
        VIRT_CUSTOMIZE_OPTS+=(
            --run-command "mkdir -p /etc/netplan && cat > /etc/netplan/01-netcfg.yaml << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      match:
        driver: virtio_net
      dhcp4: true
EOF"
        )
    fi

    VC_LOG="${LOG_DIR}/virt-customize-${VMID}.log"
    if ! run_with_countdown 200 "离线定制" "$VC_LOG" virt-customize "${VIRT_CUSTOMIZE_OPTS[@]}"; then
        box_line "${C_RED}[ERR] virt-customize 修改失败，请检查镜像或日志。${C_RESET}"
        box_line "${C_YELLOW}   详细错误: ${VC_LOG}${C_RESET}"
        box_bottom
        tail -n 40 "$VC_LOG"
        rm -f "$TMP_IMG"
        exit 1
    fi
    FINAL_IMPORT_PATH="$TMP_IMG"
    box_line "${C_GREEN}[OK] 离线定制完成${C_RESET}"
    box_bottom
else
    box_top
    box_line "${C_YELLOW}>> [1/4] 跳过离线修改，直接导入镜像...${C_RESET}"
    box_bottom
fi

if [ -n "$EXTRA_PACKAGES" ]; then
    box_top
    box_line "${C_BRIGHT_RED}步骤 9.5${C_BRIGHT_CYAN} · 安装额外软件${C_RESET}"
    box_sep
    box_line "${C_BRIGHT_BLUE}>> 额外安装: ${C_BRIGHT_YELLOW}${EXTRA_PACKAGES}${C_RESET}"
    EXTRA_LOG="${LOG_DIR}/virt-customize-extra-${VMID}.log"
    if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
        EXTRA_CMD="DEBIAN_FRONTEND=noninteractive apt-get install -y ${EXTRA_PACKAGES}"
    else
        EXTRA_CMD="dnf install -y ${EXTRA_PACKAGES}"
    fi
    EXTRA_OPTS=(-a "$FINAL_IMPORT_PATH" --run-command "$EXTRA_CMD")
    [ "$IS_RHEL_QCOW" -eq 1 ] && EXTRA_OPTS+=(--selinux-relabel)
    if ! virt-customize "${EXTRA_OPTS[@]}" >"$EXTRA_LOG" 2>&1; then
        box_line "${C_YELLOW}[!] 额外软件安装失败(已自动跳过,不影响开机)${C_RESET}"
        box_line "${C_DIM}   失败原因见: ${EXTRA_LOG}${C_RESET}"
        box_bottom
        tail -n 12 "$EXTRA_LOG" 2>/dev/null
    else
        box_line "${C_GREEN}[OK] 额外软件安装完成${C_RESET}"
        box_bottom
    fi
fi

box_top
box_line "${C_BRIGHT_RED}步骤 10${C_BRIGHT_CYAN} · 创建虚拟机硬件${C_RESET}"
box_sep
HAS_ESP=$(virt-filesystems -a "$SELECTED_PATH" --long 2>/dev/null | grep -c 'vfat' || true)
if [ "$HAS_ESP" -gt 0 ]; then
    BIOS_OPTS=(--bios ovmf --efidisk0 "${STORAGE}:0,efitype=4m,pre-enrolled-keys=1")
else
    BIOS_OPTS=(--bios seabios)
fi
box_line "${C_BRIGHT_BLUE}>> [2/4] 创建虚拟机硬件...${C_RESET}"

qm create "$VMID" \
  --name "$HOSTNAME" \
  --machine q35 \
  "${BIOS_OPTS[@]}" \
  --cpu host --cores "$CORES" --memory "$MEM" \
  --scsihw virtio-scsi-single \
  --net0 "$NET0_ARG" \
  --serial0 socket --vga std \
  --agent enabled=1 --ostype l26 >/dev/null 2>&1

[ -n "$NET1_ARG" ] && qm set "$VMID" --net1 "$NET1_ARG" >/dev/null 2>&1

box_line "${C_GREEN}[OK] 硬件创建完成${C_RESET}"
box_bottom

box_top
box_line "${C_BRIGHT_RED}步骤 11${C_BRIGHT_CYAN} · 导入磁盘${C_RESET}"
box_sep
box_line "${C_BRIGHT_BLUE}>> [3/4] 导入磁盘...${C_RESET}"

if [[ "$SELECTED_ISO" == *.iso ]]; then
    qm set "$VMID" --ide2 "local:iso/${SELECTED_ISO},media=cdrom" >/dev/null 2>&1
    qm set "$VMID" --scsi0 "${STORAGE}:${DISK},discard=on,ssd=1,cache=writeback" >/dev/null 2>&1
    qm set "$VMID" --boot "order=ide2;scsi0" >/dev/null 2>&1
else
    qm importdisk "$VMID" "$FINAL_IMPORT_PATH" "$STORAGE" -format qcow2 >/dev/null 2>&1 || true
    UNUSED=$(qm config "$VMID" | grep unused | head -1 | awk '{print $2}' || true)
    qm set "$VMID" --scsi0 "${UNUSED},discard=on,ssd=1,cache=writeback" >/dev/null 2>&1
    if [ "$IS_IMG" -eq 0 ] && [ "$DISK" -gt 0 ]; then
        CUR_GB=$(qm config "$VMID" | grep '^scsi0:' | grep -oE 'size=[0-9]+G' | head -1 | grep -oE '[0-9]+' || true)
        if [ -n "$CUR_GB" ] && [ "$DISK" -gt "$CUR_GB" ]; then
            qm resize "$VMID" scsi0 "${DISK}G" >/dev/null 2>&1 || true
            box_line "${C_GREEN}>> 系统盘已扩容至 ${DISK}G${C_RESET}"
        elif [ -n "$CUR_GB" ]; then
            box_line "${C_YELLOW}[!] 目标系统盘 ${DISK}G ≤ 镜像自带 ${CUR_GB}G，跳过扩容（PVE 不支持缩小）${C_RESET}"
        else
            qm resize "$VMID" scsi0 "${DISK}G" >/dev/null 2>&1 || true
        fi
    fi
    qm set "$VMID" --boot "order=scsi0" >/dev/null 2>&1
    [ "$FINAL_IMPORT_PATH" != "$SELECTED_PATH" ] && rm -f "$FINAL_IMPORT_PATH"
fi
if [ "$DATA_DISK" -gt 0 ]; then
    qm set "$VMID" --scsi1 "${DATA_STORAGE}:${DATA_DISK},format=qcow2" >/dev/null 2>&1
fi
box_line "${C_GREEN}[OK] 磁盘导入完成${C_RESET}"
box_bottom

plain_line "${C_BRIGHT_BLUE}>> [4/4] 启动虚拟机...${C_RESET}"
qm start "$VMID" >/dev/null 2>&1

FINAL_IP=""
if [ -n "$STATIC_IP" ]; then
    FINAL_IP="${STATIC_IP%%/*}"
    box_top
    box_line "${C_GREEN}>> 静态 IP 已配置: ${FINAL_IP}${C_RESET}"
    box_bottom
else
    set +e
    cols=$(tput cols)
    pad=$(( (cols - STEP_WIDTH) / 2 ))
    [ "$pad" -lt 0 ] && pad=0

    SECONDS=0
    MAX_WAIT=70
    SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    si=0
    FINAL_IP=""
    VM_MAC=$(qm config "$VMID" 2>/dev/null | grep -oE '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' | head -1 | tr 'A-F' 'a-f' || true)
    IP_TMP="/tmp/vmip-${VMID}-$$"

    (
        while true; do
            ip=$(timeout 2 qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -vE '^(127\.|169\.254)' | head -1 || true)
            if [ -z "$ip" ] && [ -n "$VM_MAC" ]; then
                ip=$(ip neigh show 2>/dev/null | grep -i "$VM_MAC" | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
            fi
            if [ -n "$ip" ]; then
                echo "$ip" > "$IP_TMP"
                break
            fi
            sleep 2
        done
    ) &
    BG_PID=$!

    while [ "$SECONDS" -lt "$MAX_WAIT" ] && [ ! -s "$IP_TMP" ]; do
        printf "\r%${pad}s\033[K${C_BRIGHT_BLUE} 等待网络就绪 ${SPIN[$si]}${C_RESET}  ${C_DIM}剩余 %d 秒${C_RESET}" "" "$((MAX_WAIT - SECONDS))"
        si=$(( (si+1) % ${#SPIN[@]} ))
        sleep 1
    done

    kill "$BG_PID" 2>/dev/null
    wait "$BG_PID" 2>/dev/null || true
    FINAL_IP=$(cat "$IP_TMP" 2>/dev/null)
    rm -f "$IP_TMP"
    printf "\r\033[K"
    set -e

    box_top
    if [ -z "$FINAL_IP" ]; then
        box_line "${C_YELLOW}[!] 未能自动获取到 IP 地址${C_RESET}"
        if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
            box_line "${C_YELLOW}  请稍等片刻，然后按以下步骤手动获取：${C_RESET}"
            box_line "${C_BRIGHT_BLUE}  1. 查看登录密码: cat /var/log/vm${VMID}-credentials.txt${C_RESET}"
            box_line "${C_BRIGHT_BLUE}  2. 通过串口登录: qm terminal ${VMID}${C_RESET}"
            box_line "${C_YELLOW}  3. 登录后输入 'ip a' 即可看到 IP 地址${C_RESET}"
        else
            box_line "${C_YELLOW}  此镜像未定制，请通过串口进入自行配置：${C_RESET}"
            box_line "${C_BRIGHT_BLUE}  qm terminal ${VMID}${C_RESET}"
            box_line "${C_YELLOW}  进入后先配置网络，再输入 'ip a' 查看 IP 地址${C_RESET}"
        fi
    else
        box_line "${C_GREEN}>> 成功获取到 IP 地址: ${FINAL_IP}${C_RESET}"
    fi
    box_bottom
fi

sparkle_lines=(
    "${C_BRIGHT_YELLOW}.  .  .  .  .  .  .  .  .  .  .${C_RESET}"
    "${C_BRIGHT_MAGENTA}*         *         *         *${C_RESET}"
    "${C_BRIGHT_CYAN}.     .     .     .     .     .     .${C_RESET}"
    "${C_BRIGHT_RED}*         *         *         *         *${C_RESET}"
    "${C_BRIGHT_GREEN}.     .     .     .     .     .     .${C_RESET}"
    "${C_BRIGHT_YELLOW}*         *         *         *         *         *${C_RESET}"
)
for line in "${sparkle_lines[@]}"; do
    stripped=$(strip_ansi "$line")
    width=$(visible_width "$stripped")
    tcols=$(tput cols)
    pad=$(( (tcols - width) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf "%${pad}s%b\n" "" "$line"
done
echo ""

RESET='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
GREEN='\033[38;5;114m'; CYAN='\033[38;5;80m'; YELLOW='\033[38;5;179m'
RED='\033[38;5;210m'; GRAY='\033[38;5;240m'; WHITE='\033[38;5;253m'
W=66
dw() { python3 -c "import unicodedata,sys; s=sys.argv[1]; print(sum(2 if unicodedata.east_asian_width(c) in ('F','W') else 1 for c in s))" "$1" 2>/dev/null; }
repeat() { local ch="$1" n="$2" out="" i; for (( i=0; i<n; i++ )); do out+="$ch"; done; printf "%s" "$out"; }
row() { local colored="$1" plain="$2" w pad; w=$(dw "$plain"); pad=$((W-w)); (( pad < 0 )) && pad=0; echo -e "${GRAY}│${RESET} ${colored}$(repeat ' ' $pad) ${GRAY}│${RESET}"; }
blank_row() { echo -e "${GRAY}│${RESET}$(repeat ' ' $((W+2)))${GRAY}│${RESET}"; }
top_border() { echo -e "${GRAY}┌$(repeat '─' $((W+2)))┐${RESET}"; }
mid_border() { echo -e "${GRAY}├$(repeat '─' $((W+2)))┤${RESET}"; }
bot_border() { echo -e "${GRAY}└$(repeat '─' $((W+2)))┘${RESET}"; }
rrow() { local colored="$1" plain="$2" w pad; w=$(dw "$plain"); pad=$((W-w)); (( pad < 0 )) && pad=0; echo -e "${RED}│${RESET} ${colored}$(repeat ' ' $pad) ${RED}│${RESET}"; }
rtop() { echo -e "${RED}┌$(repeat '─' $((W+2)))┐${RESET}"; }
rbot() { echo -e "${RED}└$(repeat '─' $((W+2)))┘${RESET}"; }
PANEL_W=$((W+4))
LEFT_PAD=$(( ( $(tput cols 2>/dev/null || echo 100) - PANEL_W) / 2 )); (( LEFT_PAD < 0 )) && LEFT_PAD=0
MARGIN="$(repeat ' ' $LEFT_PAD)"
emit() { printf "%s" "$MARGIN"; echo -e "$1"; }

echo ""
if [ -n "$FINAL_IP" ]; then
    emit "${GREEN}${BOLD}[OK]${RESET}   ${WHITE}成功获取到 IP 地址: ${BOLD}${FINAL_IP}${RESET}"
else
    emit "${RED}${BOLD}[ERR]${RESET}   ${WHITE}未获取到 IP 地址${RESET}"
fi
echo ""

emit "$(top_border)"
title="READY TO GO"
tag="VM-${VMID} · RUNNING"
tw=$(dw "$title"); gw=$(dw "$tag")
gap=$(( W - tw - gw )); (( gap < 0 )) && gap=0
emit "$(echo -e "${GRAY}│${RESET} ${BOLD}${WHITE}${title}${RESET}$(repeat ' ' $gap)${GREEN}${tag}${RESET} ${GRAY}│${RESET}")"
emit "$(mid_border)"
emit "$(blank_row)"
emit "$(row "${YELLOW}资源信息${RESET}" "资源信息")"
emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "VMID" "$VMID")" "$(printf "%-12s%s" "VMID" "$VMID")")"
emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "Hostname" "$HOSTNAME")" "$(printf "%-12s%s" "Hostname" "$HOSTNAME")")"
emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "CPU / RAM" "${CORES} core / ${MEM} MB")" "$(printf "%-12s%s" "CPU / RAM" "${CORES} core / ${MEM} MB")")"
emit "$(row "$(printf "${YELLOW}%-12s${RESET}${CYAN}%s${RESET}" "Bridge" "${BR0}${NET1_ARG:+ + ${BR1}}")" "$(printf "%-12s%s" "Bridge" "${BR0}${NET1_ARG:+ + ${BR1}}")")"
emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "MAC" "$MAC_ADDR")" "$(printf "%-12s%s" "MAC" "$MAC_ADDR")")"
if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    emit "$(blank_row)"
    emit "$(row "${YELLOW}连接信息${RESET}" "连接信息")"
    emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "User" "$NEW_USER")" "$(printf "%-12s%s" "User" "$NEW_USER")")"
    emit "$(row "$(printf "${YELLOW}%-12s${RESET}${RED}${BOLD}%s${RESET}" "Password" "$NEW_PASS")" "$(printf "%-12s%s" "Password" "$NEW_PASS")")"
    if [ "$ENABLE_SSH_KEY" -eq 1 ]; then
        emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "Auth" "SSH Key only")" "$(printf "%-12s%s" "Auth" "SSH Key only")")"
    else
        emit "$(row "$(printf "${YELLOW}%-12s${RESET}%s" "Auth" "Password login")" "$(printf "%-12s%s" "Auth" "Password login")")"
    fi
fi
if [ -n "$FINAL_IP" ]; then
    emit "$(blank_row)"
    IW=$(( W - 6 ))
    ssh_user="${NEW_USER:-root}"
    ssh_plain="ssh ${ssh_user}@${FINAL_IP}"
    sw=$(dw "$ssh_plain"); spad=$(( IW - sw )); (( spad < 0 )) && spad=0
    emit "$(echo -e "${GRAY}│${RESET}  ${GRAY}┌$(repeat '─' $((IW+2)))┐${RESET}  ${GRAY}│${RESET}")"
    emit "$(echo -e "${GRAY}│${RESET}  ${GRAY}│${RESET} ${CYAN}${ssh_plain}${RESET}$(repeat ' ' $spad) ${GRAY}│${RESET}  ${GRAY}│${RESET}")"
    emit "$(echo -e "${GRAY}│${RESET}  ${GRAY}└$(repeat '─' $((IW+2)))┘${RESET}  ${GRAY}│${RESET}")"
fi
emit "$(blank_row)"
emit "$(bot_border)"
echo ""

if [ "$IS_DEBIAN_QCOW" -eq 1 ] || [ "$IS_RHEL_QCOW" -eq 1 ] || [ "$IS_UBUNTU_QCOW" -eq 1 ]; then
    if [ "$ENABLE_SSH_KEY" -ne 1 ]; then
        emit "$(rtop)"
        emit "$(rrow "${BOLD}!  当前使用密码 SSH 登录，建议尽快修改密码。${RESET}" "!  当前使用密码 SSH 登录，建议尽快修改密码。")"
        emit "$(rrow "${DIM}首次登录后请立即执行 passwd 更新凭据。${RESET}" "首次登录后请立即执行 passwd 更新凭据。")"
        emit "$(rbot)"
        echo ""
    else
        emit "${GREEN}[OK]${RESET} ${WHITE}SSH 密钥登录已启用。${RESET}"
        echo ""
    fi
fi

if [ "$IS_RHEL_QCOW" -eq 1 ]; then
    emit "${DIM}${GRAY}SELinux 已设为 permissive（宽松模式），仅记录不拦截${RESET}"
    emit "${DIM}${GRAY}如需恢复 enforcing 可在 VM 内自行开启${RESET}"
    echo ""
fi

emit "${GREEN}[OK]${RESET} ${DIM}脚本执行完成，请保存好密码后按 Ctrl+C 退出。${RESET}"
emit "${DIM}${GRAY}Powered by PVE 极速开机脚本 · $(date '+%Y-%m-%d %H:%M:%S')${RESET}"
echo ""

if [ "$IS_DEBIAN_QCOW" -eq 0 ] && [ "$IS_RHEL_QCOW" -eq 0 ] && [ "$IS_UBUNTU_QCOW" -eq 0 ]; then
    box_top
    box_line "${C_YELLOW}[i] 此镜像未定制，请通过串口自行配置${C_RESET}"
    box_line "  ${C_BRIGHT_BLUE}qm terminal ${VMID}${C_RESET}"
    box_bottom
fi


NORMAL_EXIT=1

sleep 888
