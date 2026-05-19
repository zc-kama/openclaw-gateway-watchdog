# OpenClaw Gateway 看门狗

这是一个给 OpenClaw Gateway 用的外部看门狗。它会先检查本机 gateway、再检查微信等通道 URL、最后检查通用网络；只有判断“不是全局断网，而是通道/gateway 自己卡住”时才会重启，避免网络波动时乱重启。

## 一键安装

在 WSL/Linux 里进入本目录运行：

```bash
bash install-watchdog.sh
```

默认就能用，交互提示里直接回车即可。无人值守安装：

```bash
bash install-watchdog.sh --yes
```

如果你有自己的通道健康检查地址：

```bash
bash install-watchdog.sh --channel-url "https://你的通道地址/health"
```

安装脚本会自动完成这些事：

- 把脚本复制到 `~/.local/share/openclaw-gateway-watchdog`;
- 自动生成配置 `~/.config/openclaw-gateway-watchdog/watchdog.env`;
- 自动生成用户级 systemd 服务 `gateway-watchdog`;
- 如果当前系统没有 user systemd，就先用后台进程兜底启动。

## 日常管理

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
systemctl --user restart gateway-watchdog
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

卸载并删除配置/日志：

```bash
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh --purge
```

## 可选配置

普通用户不用改。需要高级配置时编辑：

```text
~/.config/openclaw-gateway-watchdog/watchdog.env
```

常用项：

```bash
CHANNEL_URL="https://ilinkai.weixin.qq.com"
GATEWAY_HEALTH_URL="http://127.0.0.1:18789/healthz"
GATEWAY_SERVICE="openclaw-gateway"
RESTART_COMMAND="systemctl --user restart openclaw-gateway"
NETWORK_URLS="https://www.baidu.com https://www.qq.com https://api.weixin.qq.com"
```

## 相比原版优化了什么

- 不再写死 `/home/zc/.openclaw/workspace`，从当前目录安装。
- 自动生成缺失的 `gateway-watchdog.service`。
- 不再强制手改脚本，配置放到独立 `watchdog.env`。
- 支持 systemd 用户服务，也支持没有 user systemd 时临时后台兜底。
- 通道失败会二次确认，并用通用网络探测排除全局断网。
- 增加指数退避、每小时重启上限、单实例锁、日志轮转。
- 增加 `SKILL.md`、中英文 README、LICENSE，方便发布到 Git 和 ClawHub。

## 发布到 ClawHub

本目录已经带 `SKILL.md`，可作为 ClawHub skill 发布：

```bash
clawhub publish . \
  --slug openclaw-gateway-watchdog \
  --name "OpenClaw Gateway Watchdog" \
  --version 1.0.0 \
  --changelog "Initial zero-config watchdog release"
```

建议先 dry-run 或检查元数据，再正式发布。
