# Tailscale 远程访问

如果你只是想让**自己的手机远程访问自己的电脑**，Tailscale 往往是这套项目最省事的接入方式。

它不是应用内部协议的一部分，而是网络层方案：

- 项目仍然监听本机 HTTP 端口
- Tailscale 负责把这台主机放进一个私有 Tailnet
- 手机加入同一个 Tailnet 后，直接访问主机的 Tailscale IP 即可

## 适用场景

推荐在下面这种场景使用 Tailscale：

- 这是你自己的电脑
- 这是你自己的手机
- 不想暴露公网域名
- 不想处理 Cloudflare Tunnel、域名、TLS 和额外账号配置

如果你要把服务发给更多外部用户访问，Cloudflare Tunnel 更适合。

## 前提条件

目标电脑上需要：

- Tailscale 已安装并登录
- Codex HAPI Web 后端已启动
- 后端监听在可访问地址上，默认是 `0.0.0.0:3113`

手机上需要：

- 安装并登录同一个 Tailnet 的 Tailscale

## 使用步骤

### 1. 在电脑上启动后端

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-backend.ps1
```

### 2. 获取当前机器的 Tailscale 地址

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\show-tailscale-url.ps1
```

这个脚本会输出类似：

```text
http://100.x.x.x:3113
```

### 3. 在手机上访问

确保手机已经接入同一个 Tailnet，然后打开脚本输出的地址即可。

## 优点

- 不需要公网域名
- 不需要 Cloudflare Tunnel
- 不需要额外 HTTPS 证书配置
- 很适合“我远程访问我自己的电脑”

## 限制

- 手机和电脑都必须登录同一个 Tailnet
- 外部用户不能直接访问，除非他们也加入你的 Tailnet
- 它更适合私人远程使用，不适合面向公开用户发布

## 备注

这套项目里的桌面线程刷新仍然是**在电脑本机上执行**的，Tailscale 只是帮你把网页访问通到这台机器，并不会改变桌面刷新脚本对 Windows、本地桌面会话和官方 Codex Desktop 的依赖。
