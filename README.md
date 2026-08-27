# one-click-vps-deploy — sing-box / Hysteria2 / VLESS+Reality 一键部署全家桶

> 一套开箱即用的一键脚本：VPS 节点部署、订阅转换服务、PVE 虚拟机创建。零依赖、多发行版、所有凭据部署时现场生成，仓库不含任何密钥。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![ci](https://github.com/kottregrossmeyer-lab/one-click-vps-deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/kottregrossmeyer-lab/one-click-vps-deploy/actions/workflows/ci.yml)

## 简介

三个互为配套的一键部署脚本，覆盖代理节点自建的完整链路：

| # | 脚本 | 用途 |
|---|------|------|
| 1 | `subconverter/setup.sh` | 订阅转换服务（sing-box / Clash / v2rayN） |
| 2 | `hy2-bundle/hy2.sh` | VPS 节点一键部署（Hysteria2 / VLESS+Reality） |
| 3 | `nexus.sh` | PVE 虚拟机一键创建 |

支持系统：Debian 12/13、Ubuntu 20.04–24.04、RHEL 9 / Rocky 9 / AlmaLinux 9（amd64 / arm64）。

---

## ① 订阅转换服务（subconverter）

把 VLESS / Hysteria2 节点链接转换成各客户端可用的订阅配置，按客户端 User-Agent 自动返回：

- **sing-box**（JSON）/ **Clash / Mihomo**（YAML）/ **v2rayN**（Base64）
- 菜单式节点选择：仅 VLESS / 仅 HY2 / 双节点 / **自动检测**（读 `/etc/sing-box/config.json`）
- Hysteria2 **端口跳跃**支持（如 `20000-30000`），自动生成 `hop_interval`
- HTTP + HTTPS 双端点；真证书（certbot 自动申请）/ 自签证书双模式
- Python 零依赖（系统自带 python3 + nginx），无需 Node.js
- 支持命令行直接传节点链接跳过交互菜单

```bash
curl -fsSL -o /tmp/setup.sh https://mirror.notebase.cn/download/setup.sh && sudo bash /tmp/setup.sh
```

## ② VPS 节点一键部署（hy2.sh）

在全新 VPS 上部署 sing-box 节点，交互式选择协议：

- **Hysteria2**（UDP + 端口跳跃）或 **VLESS + Reality**（TCP，免证书）
- 证书：IP 直连自签（免申请）/ 域名自动 Let's Encrypt（DNS 预检 + certbot）
- SSH 加固：禁用 root 密码登录 / 可选公钥注入
- 部署完自动生成分享链接，可一键导入订阅转换服务
- 自动加 1G swap 防小内存 OOM
- 支持 Debian / Ubuntu / Rocky / AlmaLinux，amd64 / arm64

```bash
curl -fsSL -o /tmp/hy2.sh https://mirror.notebase.cn/bundle/hy2.sh && sudo bash /tmp/hy2.sh
```

## ③ PVE 虚拟机一键创建（nexus.sh）

在 PVE 宿主机上创建新虚拟机（QEMU/KVM）：

- 自动识别镜像系统（Debian / RedHat 系）并配置软件源
- 交互式选择网络桥、静态 IP / DHCP
- 自动设置 root 密码、创建 sudo / wheel 用户、可选注入 SSH 公钥
- 系统盘只扩容不缩小，支持多发行版

```bash
curl -fsSL -o /tmp/nexus.sh https://mirror.notebase.cn/download/nexus.sh && sudo bash /tmp/nexus.sh
```

---

## 🔒 安全说明

- **本仓库不含任何密钥 / 密码 / 凭证**。所有密码、节点口令、证书均在部署时于目标机器上现场生成（`openssl rand` / `certbot`）。
- 脚本引用的 `mirror.notebase.cn` 为公开分发点，无需鉴权。
- 注意：Let's Encrypt 单 IP 7 天内最多签发 5 张证书，反复重装测试会触发限速（脚本会自动回退自签）。
- 建议：使用任何一键脚本前先通读源码——这正是开源的意义。

## 贡献

想提功能或修 bug，先看 [CONTRIBUTING.md](CONTRIBUTING.md)。标准 fork + pull request 流程，PR 会自动跑语法检查和密钥扫描（`.github/workflows/ci.yml`），通过才合并。

## 📜 License

[MIT](LICENSE) © 2026 kottregrossmeyer-lab
