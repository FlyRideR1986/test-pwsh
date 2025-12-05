# ECH-Tunnel

基于 WebSocket 的安全隧道代理，支持 TCP 转发、SOCKS5 和 HTTP 代理，采用 ECH 技术隐藏 SNI。

## 核心优势：预连接架构

| 特性 | 传统模式 | 预连接模式 |
|------|----------|------------|
| 首包延迟 | 200-500ms（需握手） | 1-10ms**（直接复用） |
| 连接稳定性 | 每次新建 | **预先建立，稳定可靠 |
| 故障感知 | 请求时才发现 | 实时检测，提前预警 |

传统模式：用户请求 → 建TCP → TLS握手 → WS握手 → 发送数据（慢）
预连接：  程序启动 → 预建N个连接 → 用户请求 → 直接发送（快）

## 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| -l | 监听地址（必填） | - |
| -f | 服务端地址（客户端必填） | - |
| -ip | 指定连接 IP | - |
| -cert / -key | TLS 证书/密钥 | 自动生成 |
| -token | 认证令牌 | - |
| -cidr | IP 白名单 | 0.0.0.0/0,::/0 |
| -dns | DoH 服务器 | dns.alidns.com/dns-query |
| -ech | ECH 查询域名 | cloudflare-ech.com |
| -n | 预连接通道数 | 3 |

## 使用示例

### 服务端

# 基本启动（自签名证书）
ech-tunnel -l wss://0.0.0.0:8443/tunnel

# 使用证书 + 认证
ech-tunnel -l wss://0.0.0.0:443/tunnel -cert cert.pem -key key.pem -token secret123

### 客户端

# SOCKS5/HTTP 代理
ech-tunnel -l proxy://127.0.0.1:1080 -f wss://server.com:8443/tunnel

# 带认证的代理
ech-tunnel -l proxy://user:pass@127.0.0.1:1080 -f wss://server.com:8443/tunnel -token secret123

# TCP 端口转发（支持多规则）
ech-tunnel -l tcp://127.0.0.1:8080/example.com:80,127.0.0.1:3389/192.168.1.100:3389 -f wss://server.com:8443/tunnel

# 高并发场景（增加通道数）
ech-tunnel -l proxy://127.0.0.1:1080 -f wss://server.com:8443/tunnel -n 10

## 国内 DoH 服务器

| 提供商 | 地址 |
|--------|------|
| 阿里云（默认） | dns.alidns.com/dns-query |
| 腾讯 DNSPod | doh.pub/dns-query |
| 360 安全 DNS | doh.360.cn/dns-query |

## 故障排查

**ECH 查询失败**：更换 DoH -dns doh.pub/dns-query

**连接超时**：增加通道数 -n 5 或检查网络

**认证失败**：确认 -token 两端一致









# Workers.js

第一步，将workrs.txt的代码完整复制粘贴到workers里面
第二步，启动ech-workers客户端，启动参数-h看帮助文件
第三步，实在是搞不明白怎么玩，等过两天去油管看看有没有up主折腾这个。


Usage of ./ech-workers:
  -dns string
        ECH 查询 DNS 服务器 (default "119.29.29.29:53")
  -ech string
        ECH 查询域名 (default "cloudflare-ech.com")
  -f string
        服务端地址 (格式: x.x.workers.dev:443)
  -ip string
        指定服务端 IP（绕过 DNS 解析）
  -l string
        代理监听地址 (支持 SOCKS5 和 HTTP) (default "127.0.0.1:30000")
  -token string
        身份验证令牌


