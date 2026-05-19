# OpenClaw Gateway 看门狗

OpenClaw Gateway 外部恢复守护脚本，面向 `openclaw-weixin` 这类需要长期在线的通道。

这个项目解决的是一个很具体的运维问题：OpenClaw Gateway 进程还活着，但微信通道、长轮询、WSL 网络或 session 状态已经坏掉，导致消息收不到、发不出，最后只能手动 `openclaw gateway restart`。

## 问题背景

OpenClaw Gateway 和通道插件是长连接系统。电脑睡眠、切换 Wi-Fi、WSL 网络重建、iLink 长时间空闲、配置热加载，都可能让“进程存活”和“通道可用”变成两件事。

以官方 `Tencent/openclaw-weixin` 为例，源码和 issue 里能看到几个已知边界：

- `monitor.ts` 里 `MAX_CONSECUTIVE_FAILURES = 3`，失败后 `BACKOFF_DELAY_MS = 30_000`，也就是插件内部主要是 3 次失败后的 30 秒退避。
- `session-guard.ts` 里 `SESSION_PAUSE_DURATION_MS = 60 * 60 * 1000`，`SESSION_EXPIRED_ERRCODE = -14`，session 过期会进入 60 分钟暂停窗口。
- [Tencent/openclaw-weixin#141](https://github.com/Tencent/openclaw-weixin/issues/141) 记录了配置热加载后 Monitor 结束但不再启动，临时处理方式是手动重启 gateway。
- [Tencent/openclaw-weixin#155](https://github.com/Tencent/openclaw-weixin/issues/155) 记录了 `errcode=-14` 后进入 60 分钟循环暂停、出站消息被阻塞的问题。

所以这个项目不是替换官方插件，而是在外面加一层独立 watchdog：当通道或 gateway 进入“看起来还活着，实际上已经不能工作”的状态时，用更保守的探测和熔断策略自动恢复。

## 工作原理

看门狗使用三层健康检查，从浅到深判断是否真的需要重启：

| 层级 | 检查对象 | 作用 |
| --- | --- | --- |
| Gateway 本机状态 | systemd 用户服务、本机 health URL、本机 TCP 端口、进程兜底 | 判断 OpenClaw Gateway 是否已经挂掉或本机不可达。 |
| 通道状态 | 主通道 URL，默认 `https://ilinkai.weixin.qq.com` | 判断微信 iLink 等通道服务是否从当前机器可达。 |
| 外部网络状态 | 百度、QQ、微信 API 等多个独立 URL | 排除全局断网，避免电脑没网时误重启 gateway。 |

核心策略是：gateway 真挂了就立即重启；通道不通时先确认不是全局断网；网络正常但通道持续失败，才进入退避等待和重启流程。

## 恢复策略

- Gateway 本机健康检查失败：立即重启。
- 通道 URL 失败：累计失败次数，进入故障流程。
- 外部网络全部失败：认为是全局断网，只等待，不重启。
- 外部网络正常但通道仍失败：指数退避后再次确认，再重启 gateway。
- 连续 5 次通道探测成功后，清空失败状态。
- 每小时最多重启固定次数，防止网络抖动时形成重启风暴。
- 深夜可以降低检查频率，减少无意义日志。

## 文件说明

| 文件 | 作用 |
| --- | --- |
| `gateway-watchdog.sh` | 主守护脚本，负责探测、退避、熔断、日志、单实例锁和重启决策。 |
| `install-watchdog.sh` | 一键安装脚本，自动复制文件、生成配置、创建用户级 systemd 服务并启动。 |
| `uninstall-watchdog.sh` | 卸载脚本，停止服务并删除安装目录。 |
| `SKILL.md` | ClawHub/OpenClaw 技能元数据和使用说明。 |
| `README.md` | 英文文档。 |

## 安装

在 WSL/Linux 里进入本目录运行：

```bash
bash install-watchdog.sh
```

无人值守安装：

```bash
bash install-watchdog.sh --yes
```

指定自己的通道探测地址：

```bash
bash install-watchdog.sh --channel-url "https://你的通道地址/health"
```

安装后会生成：

- 脚本目录：`~/.local/share/openclaw-gateway-watchdog`
- 配置文件：`~/.config/openclaw-gateway-watchdog/watchdog.env`
- 日志文件：`~/.local/state/openclaw-gateway-watchdog/watchdog.log`
- systemd 用户服务：`~/.config/systemd/user/gateway-watchdog.service`

如果当前环境没有 user systemd，安装脚本会退回到后台进程模式，并把 pid 写到状态目录。

## 管理命令

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
systemctl --user restart gateway-watchdog
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

连配置和日志一起删除：

```bash
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh --purge
```

## 配置

普通用户一般不用改。高级配置在：

```text
~/.config/openclaw-gateway-watchdog/watchdog.env
```

常用项：

```bash
GATEWAY_SERVICE="openclaw-gateway"
GATEWAY_HEALTH_URL="http://127.0.0.1:18789/healthz"
GATEWAY_HOST="127.0.0.1"
GATEWAY_PORT="18789"
CHANNEL_URL="https://ilinkai.weixin.qq.com"
NETWORK_URLS="https://www.baidu.com https://www.qq.com https://api.weixin.qq.com"
RESTART_COMMAND="systemctl --user restart openclaw-gateway"
BASE_INTERVAL="60"
NIGHT_INTERVAL="300"
MAX_INTERVAL="1800"
CHANNEL_FAILURES_BEFORE_RESTART="2"
SUCCESS_COUNT_TO_RESET="5"
MAX_RESTARTS_PER_HOUR="6"
```

如果你的 OpenClaw 不是 systemd 用户服务管理，可以显式指定重启命令：

```bash
RESTART_COMMAND="openclaw gateway restart"
```

## 安全边界

这个项目不修改 OpenClaw 配置、不读取 token、不改微信插件源码、不处理消息内容。它只做三件事：

1. 探测本机 gateway 和外部 URL。
2. 写自己的日志和状态文件。
3. 在满足保护条件后执行配置好的 gateway 重启命令。

分享日志前，请检查里面是否包含本机路径、服务名或私有通道地址。

## 开源许可

MIT-0。这个许可证符合 ClawHub skill 发布要求，也方便别人直接复用、改造和分发。

## 发布到 ClawHub

本仓库带 `SKILL.md`，可以作为 OpenClaw skill 发布：

```bash
clawhub publish . \
  --slug openclaw-weixin-gateway-watchdog \
  --name "OpenClaw Gateway Watchdog" \
  --version 1.0.0 \
  --changelog "Initial public watchdog release"
```

发布前需要先执行 `clawhub login` 完成 CLI 登录。
