#!/bin/bash
# sing-box 节点一键部署引导 (HY2 / VLESS)
# 用法: curl -fsSL -o /tmp/hy2.sh https://mirror.notebase.cn/bundle/hy2.sh && sudo bash /tmp/hy2.sh
# 流程: 检查/条件更新部署包(有新版才重下) → 解压 → 运行 install.sh
# 想强制重新下载: rm -f /tmp/hy2-bundle.tar.gz 再跑
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 root/sudo 运行: sudo bash $0" >&2; exit 1; }

# 极简系统可能没有 curl/tar。装不上就停，别拿一个半截包继续。
if ! command -v tar >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo ">> 安装 curl + tar..."
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y tar curl
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq || true
    apt-get install -y tar curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y tar curl
  fi
fi
command -v tar >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 || {
  echo "[X] 系统里没有 curl 或 tar，而且自动安装失败。请先装上再跑。" >&2
  exit 1
}

PKG=/tmp/hy2-bundle.tar.gz
URL="https://mirror.notebase.cn/bundle/hy2-bundle.tar.gz"

echo "=============================================="
echo "   sing-box 节点一键部署 (HY2 / VLESS)"
echo "=============================================="
echo "[提示] 较老的系统(如 Debian 9 / Ubuntu 18 / CentOS 7-8 等已 EOL 的发行版)可能在装包阶段报错 —— 多为软件源已下线所致, 请自行排查; 建议 Debian 11+ / Ubuntu 20.04+ / RHEL 9 系。"

# 下到旁边的临时文件，确认是完整 tar 才替换。中途断线不会把已经能用的旧包写坏。
fetch_pkg() {
  local dest="$1" use_z="$2" tmp="${dest}.part" i=1
  while [[ $i -le 4 ]]; do
    rm -f "$tmp"
    local args=(-fSL --retry 2 --retry-delay 2 --connect-timeout 20 --max-time 180 -o "$tmp")
    [[ "$use_z" == "1" && -s "$dest" ]] && args+=(-z "$dest")
    if curl "${args[@]}" "$URL"; then
      if [[ -s "$tmp" ]] && tar tzf "$tmp" >/dev/null 2>&1; then
        mv -f "$tmp" "$dest"
        return 0
      fi
      # 服务器说没有更新(304)或写出了空文件：旧包还在就继续用
      if [[ "$use_z" == "1" && -s "$dest" ]] && tar tzf "$dest" >/dev/null 2>&1; then
        rm -f "$tmp"
        return 0
      fi
    fi
    rm -f "$tmp"
    echo "  第 ${i} 次没下完整，$((i*3)) 秒后再试..."
    sleep $((i*3))
    i=$((i+1))
  done
  return 1
}

echo "[1/2] 检查/更新部署包..."
if [[ -s "$PKG" ]] && tar tzf "$PKG" >/dev/null 2>&1; then
  if fetch_pkg "$PKG" 1; then
    echo "  部署包已就绪 ($(du -h "$PKG" 2>/dev/null | cut -f1)，有新版本会自动更新)"
  else
    echo "  更新失败，沿用本机已有的完整包"
  fi
else
  echo "  下载部署包 (约24MB, 请稍候)..."
  rm -f "$PKG"
  if ! fetch_pkg "$PKG" 0; then
    echo "[X] 部署包下载失败。检查能不能打开: $URL" >&2
    exit 1
  fi
  echo "  部署包已就绪 ($(du -h "$PKG" | cut -f1))"
fi

tar tzf "$PKG" >/dev/null 2>&1 || { echo "[X] 部署包损坏，删掉 /tmp/hy2-bundle.tar.gz 后重跑" >&2; exit 1; }

echo "[2/2] 解压并启动部署..."
rm -rf /tmp/hy2-bundle
tar xzf "$PKG" -C /tmp

exec bash /tmp/hy2-bundle/install.sh
