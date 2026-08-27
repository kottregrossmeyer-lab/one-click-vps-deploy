#!/bin/bash
# sing-box 节点一键部署引导 (HY2 / VLESS)
# 用法: curl -fsSL -o /tmp/hy2.sh https://mirror.notebase.cn/bundle/hy2.sh && sudo bash /tmp/hy2.sh
# 流程: 检查/条件更新部署包(有新版才重下) → 解压 → 运行 install.sh
# 想强制重新下载: rm -f /tmp/hy2-bundle.tar.gz 再跑
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "请用 root/sudo 运行: sudo bash $0" >&2; exit 1; }

# 极简系统可能没有 curl/tar, 先确保装好
if ! command -v tar >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo ">> 安装 curl + tar..."
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y tar curl >/dev/null 2>&1 || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y tar curl >/dev/null 2>&1 || true
  fi
fi

PKG=/tmp/hy2-bundle.tar.gz
URL="https://mirror.notebase.cn/bundle/hy2-bundle.tar.gz"

echo "=============================================="
echo "   sing-box 节点一键部署 (HY2 / VLESS)"
echo "=============================================="

echo "[1/2] 检查/更新部署包..."
if [[ -s "$PKG" ]] && tar tzf "$PKG" >/dev/null 2>&1; then
  # 已存在且有效: 用 curl -z 条件下载, 服务器有新版才更新(If-Modified-Since)
  if curl -z "$PKG" -fSL --max-time 120 -o "$PKG" "$URL" 2>/dev/null; then
    echo "  部署包已就绪 ($(du -h "$PKG" 2>/dev/null | cut -f1), 有新版本会自动更新)"
  else
    echo "  部署包已存在, 跳过下载 (连接失败时沿用旧包)"
  fi
else
  echo "  下载部署包 (约24MB, 请稍候)..."
  rm -f "$PKG"
  curl -# -fSL --retry 2 --retry-delay 2 -o "$PKG" "$URL"
fi

echo "[2/2] 解压并启动部署..."
rm -rf /tmp/hy2-bundle
tar xzf "$PKG" -C /tmp

exec bash /tmp/hy2-bundle/install.sh
