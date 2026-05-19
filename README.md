# OpenClaw Gateway Resilience Guard

External recovery guard for OpenClaw Gateway and long-lived channel plugins such as `openclaw-weixin`.

This project is for people who run OpenClaw continuously on Linux, WSL, macOS, or Windows and need the gateway to recover from channel disconnects, network sleep/resume, and long-lived session failures without babysitting the terminal.

## Problem

OpenClaw Gateway can still be alive while an individual channel is no longer healthy. This is common after laptop sleep, Wi-Fi changes, WSL network hiccups, or long idle periods.

The WeChat plugin is especially sensitive because it depends on a long-poll `getUpdates` loop. In the upstream `Tencent/openclaw-weixin` code, the monitor has a limited retry loop and session guard:

- `monitor.ts` defines `MAX_CONSECUTIVE_FAILURES = 3` and `BACKOFF_DELAY_MS = 30_000`.
- `session-guard.ts` defines `SESSION_PAUSE_DURATION_MS = 60 * 60 * 1000` and `SESSION_EXPIRED_ERRCODE = -14`.
- Issue [Tencent/openclaw-weixin#141](https://github.com/Tencent/openclaw-weixin/issues/141) reports that after a config hot reload the monitor can end without starting again; the workaround is `openclaw gateway restart`.
- Issue [Tencent/openclaw-weixin#155](https://github.com/Tencent/openclaw-weixin/issues/155) reports that `errcode=-14` can enter a 60-minute session pause loop and block outbound messages.

This watchdog does not replace the official plugin. It is an external safety net: when the gateway or channel stops behaving like a live system, it restarts the gateway with guardrails.

## Design

The script uses a three-layer health model before it restarts anything:

| Layer | Probe | Purpose |
| --- | --- | --- |
| Gateway | `openclaw gateway status --json --require-rpc`, local health URL, local TCP port, service/process fallback | Detect whether OpenClaw Gateway is down or locally unreachable. |
| Channel | `openclaw health --json --verbose`, `openclaw status --deep`, optional `openclaw channels status --probe`, then URL fallback | Prefer OpenClaw's own per-channel health model, then fall back to a configured URL when native probes are unavailable. |
| Network | multiple independent URLs, default Baidu/QQ/Weixin | Avoid restarting the gateway during whole-machine or ISP network failure. |

Only gateway failures restart immediately. Channel failures go through confirmation, network split-brain protection, exponential backoff, and restart-rate limits.

## Recovery Policy

- Gateway down: restart immediately.
- Gateway running but channel probe fails: confirm with general network probes.
- General network also fails: do nothing except wait; restarting will not fix an offline machine.
- General network works but channel stays down: wait with exponential backoff, re-check, then restart.
- Five consecutive successful channel probes reset the failure state.
- Restart storm protection limits gateway restarts per hour.
- Night hours can use a slower probe interval to reduce noise.

## Files

| File | Purpose |
| --- | --- |
| `gateway-watchdog.sh` | Main daemon loop: probes, backoff, restart decisions, log rotation, single-instance lock. |
| `gateway-watchdog.ps1` | Windows-native daemon loop for Task Scheduler. |
| `install-watchdog.sh` | Linux/WSL/macOS installer: copies files, writes config, creates systemd user service or macOS LaunchAgent. |
| `install-watchdog.ps1` | Windows installer: creates config and a Task Scheduler job. |
| `uninstall-watchdog.sh` | Stops and removes the service and installed scripts. |
| `uninstall-watchdog.ps1` | Windows uninstaller. |
| `SKILL.md` | ClawHub/OpenClaw skill metadata and operator instructions. |
| `README.zh-CN.md` | Chinese documentation. |

## Install

Install from ClawHub:

```bash
clawhub install gateway-resilience-guard
```

Or use this repository directly.

Linux, WSL, or macOS:

```bash
bash install-watchdog.sh
```

For unattended install:

```bash
bash install-watchdog.sh --yes
```

For a custom channel probe:

```bash
bash install-watchdog.sh --channel-url "https://your-channel.example.com/health"
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-watchdog.ps1
```

The installer writes:

- scripts to `~/.local/share/openclaw-gateway-watchdog`;
- config to `~/.config/openclaw-gateway-watchdog/watchdog.env`;
- logs to `~/.local/state/openclaw-gateway-watchdog/watchdog.log`;
- a Linux/WSL user service to `~/.config/systemd/user/gateway-watchdog.service`;
- a macOS LaunchAgent to `~/Library/LaunchAgents/ai.clawhub.gateway-resilience-guard.plist`;
- a Windows scheduled task named `OpenClaw Gateway Resilience Guard`.

If user systemd is unavailable, the installer starts a direct background fallback process and stores its pid in the state directory.

## Manage

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
systemctl --user restart gateway-watchdog
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

macOS:

```bash
launchctl print gui/$(id -u)/ai.clawhub.gateway-resilience-guard
tail -f ~/.local/state/openclaw-gateway-watchdog/watchdog.log
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

Windows:

```powershell
Get-ScheduledTask -TaskName "OpenClaw Gateway Resilience Guard"
Get-Content "$env:LOCALAPPDATA\openclaw-gateway-watchdog\watchdog.log" -Wait
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\openclaw-gateway-watchdog\uninstall-watchdog.ps1"
```

Remove config and logs too:

```bash
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh --purge
```

## Configuration

Most users can keep the generated defaults. Advanced settings live in:

```text
~/.config/openclaw-gateway-watchdog/watchdog.env
```

Common keys:

```bash
GATEWAY_SERVICE="openclaw-gateway"
GATEWAY_HEALTH_URL="http://127.0.0.1:18789/healthz"
GATEWAY_HOST="127.0.0.1"
GATEWAY_PORT="18789"
CHANNEL_URL="https://ilinkai.weixin.qq.com"
NETWORK_URLS="https://www.baidu.com https://www.qq.com https://api.weixin.qq.com"
RESTART_COMMAND="systemctl --user restart openclaw-gateway"
OPENCLAW_NATIVE_PROBES="auto"
OPENCLAW_HEALTH_TIMEOUT_MS="12000"
OPENCLAW_GATEWAY_STRICT="0"
OPENCLAW_CHANNELS_PROBE="1"
BASE_INTERVAL="60"
NIGHT_INTERVAL="300"
MAX_INTERVAL="1800"
CHANNEL_FAILURES_BEFORE_RESTART="2"
SUCCESS_COUNT_TO_RESET="5"
MAX_RESTARTS_PER_HOUR="6"
```

Use `RESTART_COMMAND` if your OpenClaw install is not managed by a user-level systemd unit. Example:

```bash
RESTART_COMMAND="openclaw gateway restart"
```

On Windows, the generated config is JSON:

```text
%APPDATA%\openclaw-gateway-watchdog\watchdog.json
```

Set `OpenClawNativeProbes` to `false` if your OpenClaw CLI is too old for `openclaw health` or `openclaw status --deep`.

## Safety Notes

This project intentionally avoids destructive behavior. It does not edit OpenClaw configuration, tokens, sessions, or plugin files. It only probes URLs and restarts the gateway through the configured command.

Before sharing logs, review them for local paths, service names, and channel URLs.

## License

MIT-0. This matches ClawHub's skill publishing requirement and allows reuse without attribution requirements.

## Publish To ClawHub

Published package:

- ClawHub: <https://clawhub.ai/zc-kama/gateway-resilience-guard>
- Slug: `gateway-resilience-guard`

This repository includes `SKILL.md`, so it can also be republished as an OpenClaw skill bundle:

```bash
clawhub publish . \
  --slug gateway-resilience-guard \
  --name "OpenClaw Gateway Resilience Guard" \
  --version 1.2.0 \
  --changelog "Add native OpenClaw probes and cross-platform installers"
```

ClawHub requires CLI authentication. Run `clawhub login` first.
