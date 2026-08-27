# Contributing

仓库里是三个互相独立的一键脚本:

- `subconverter/` — 订阅转换服务(纯 Python + nginx)
- `hy2-bundle/` — VPS 节点一键部署(sing-box,Hysteria2 / VLESS+Reality)
- `nexus.sh` — PVE 建机脚本

## 流程

标准 GitHub 流程:fork → 改 → pull request。

1. fork 到你自己名下
2. 建分支,改完推到你的 fork
3. 对上游发 PR,说明改了什么、为什么改、怎么验证的

PR 会自动跑语法检查和密钥扫描(`.github/workflows/ci.yml`),不过关不会合并。

## 铁律:别把密钥交进来

这是公开仓库。脚本里所有密码、私钥、证书都必须在部署时现场生成。下面这些文件一律禁止提交,CI 也会拦:

- `*.pem` `*.key` `*.crt` `*.p12` `*.pfx`
- `.env` 及一切环境变量文件
- `id_ed25519*`、`authorized_keys` 等 SSH 私钥/授权文件

## 怎么验证

改完脚本最好在干净系统上跑过再发 PR:

- bash:`bash -n <script>` 过语法;脚本要在 Debian 12 / Ubuntu 22.04+ / Rocky 9 / Alma 9 至少一个上实测安装通过
- 订阅转换:`python3 -m py_compile subconverter/server.py`,生成的 sing-box 配置过 `sing-box check`
- 节点脚本:在全新 VPS 上实测一遍,Hysteria2 和 VLESS+Reality 两种协议都装
- 改过任何 URL / 下载地址,全仓库 grep 一遍,别留死链和旧域名

## 风格

- bash 别滥用 `set -e`,交互式提示用纯 ASCII(防终端乱码)
- 脚本自包含,不依赖非标准外部工具;Python 只用标准库
- 中文提示,英文代码
- 别为改而改;发 PR 前想清楚是不是真解决了问题
