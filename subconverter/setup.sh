#!/usr/bin/env bash
# ============================================================
#  订阅转换服务 · 一键自动部署引导脚本
#  用法:  curl -fsSL -o /tmp/setup.sh <下载地址>/setup.sh && sudo bash /tmp/setup.sh
#         可直接带订阅链接 (自动识别协议类型, 跳过节点选择):
#            ... && sudo bash /tmp/setup.sh 'vless://...' ['hysteria2://...']
#         或用 SUB_LINK / SUB_LINK2 环境变量
#  流程:  下载部署包 → 解压 → 自动进入 deploy.sh 部署
# ============================================================
set -euo pipefail

URL="${BASE_URL:-https://mirror.notebase.cn/download}"

echo "=============================================="
echo "   订阅转换服务 · 自动部署"
echo "=============================================="

echo "[1/3] 下载部署包 (15KB, 国内1-3秒 / 海外可能较慢, 请稍候)..."
for attempt in 1 2 3; do
  if curl -fSL --retry 2 --retry-delay 2 --connect-timeout 30 --max-time 120 \
      --progress-bar -o /tmp/subconverter-deploy.tar.gz "$URL/subconverter-deploy.tar.gz"; then
    break
  fi
  echo "   (第 ${attempt} 次下载失败, 重试...)"
  sleep 2
done

if [ ! -s /tmp/subconverter-deploy.tar.gz ]; then
  echo "[X] 下载失败 (可能超过每日下载次数限制, 或网络不通)"
  echo "    提示: 检查是否能访问 $URL"
  exit 1
fi

echo "[2/3] 解压..."
mkdir -p /tmp/subconverter
tar -xzf /tmp/subconverter-deploy.tar.gz -C /tmp/subconverter
cd /tmp/subconverter

echo "[3/3] 开始交互式部署..."
echo "------------------------------------------------"
if [ -n "${1:-}" ]; then
  echo "  已提供订阅链接, 自动识别节点类型, 直接进入下一步。"
  echo "  (链接: $1${2:+  +  $2})"
else
  echo "  接下来按提示:"
  echo "    [1] 选节点类型: 回车/1=仅VLESS  2=仅Hysteria2  3=双节点"
  echo "    [2] 访问方式选 2 (公网 IP)"
  echo "    [3] 输入公网 IP + HTTPS 端口 (HTTP 端口会自动建议)"
  echo "    [4] 部署完成自动打印 HTTP+HTTPS 双订阅地址"
fi
echo "------------------------------------------------"
sudo bash deploy.sh "$@"
