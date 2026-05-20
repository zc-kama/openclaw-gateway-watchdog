---
name: gateway-resilience-guard
description: OpenClaw Gateway Resilience Guard keeps Gateway, channels, and optional model-provider probes observable after Wi-Fi changes, WSL sleep/resume, session expiry, provider timeouts, or partial outages. It uses native OpenClaw health/status checks, local gateway/channel/network probes, opt-in model calls, split-brain safeguards, backoff, restart limits, quiet hours, locking, log rotation, generated config, systemd, LaunchAgent, or Task Scheduler.
tags:
  - openclaw
  - gateway
  - watchdog
  - resilience
  - wechat
  - wsl
  - systemd
  - macos
  - windows
requirements:
  tools:
    - bash
    - curl
    - systemctl optional
    - launchctl optional
    - powershell optional
    - openclaw recommended
permissions:
  - Writes a user-level systemd service, macOS LaunchAgent, or Windows scheduled task when requested.
  - Writes config and logs under user-level config/state directories.
  - Restarts OpenClaw Gateway through systemctl --user or openclaw gateway restart.
  - Optional model probe sends real OpenClaw model requests only when explicitly enabled.
---

# OpenClaw Gateway Resilience Guard

Use this skill when a user wants to keep OpenClaw Gateway and message channels online after network drops, WSL sleep/resume, macOS/Windows wake events, long-lived connection failures, or recurring model-provider timeouts.

## Install

Linux, WSL, or macOS:

```bash
bash install-watchdog.sh
```

The installer works with defaults. It prompts for the main channel probe URL when running interactively, but pressing Enter is enough for the default WeChat probe.

For unattended install:

```bash
bash install-watchdog.sh --yes
```

For a custom channel:

```bash
bash install-watchdog.sh --channel-url "https://your-channel.example.com/health"
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-watchdog.ps1
```

## Operate

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

On macOS, inspect `launchctl print gui/$(id -u)/ai.clawhub.gateway-resilience-guard`.
On Windows, inspect `Get-ScheduledTask -TaskName "OpenClaw Gateway Resilience Guard"`.

If user systemd is unavailable, the installer starts a direct background fallback and stores its pid under `~/.local/state/openclaw-gateway-watchdog/watchdog.pid`.

## Safety Model

The watchdog restarts only after layered checks:

1. OpenClaw native health probes: `openclaw gateway status --require-rpc`, `openclaw health --json --verbose`, and `openclaw status --deep` when available.
2. Runtime diagnostics: `openclaw models status` plus `openclaw logs --plain` signal scanning for provider timeout, proxy/network, rate limit, auth, channel session, gateway degraded, config reload, and task runtime warnings.
3. Local gateway health URL/TCP and main channel URL fallbacks.
4. General network URLs to avoid restarting during whole-machine network failure.
5. Optional model-provider probe via `openclaw agent --json`; default action is evidence logging only.
6. Backoff and hourly restart limits to avoid restart storms.

Model probing is disabled by default because it consumes real provider quota. To diagnose provider timeouts, set `MODEL_PROBE_ENABLED=1`, keep `MODEL_PROBE_ACTION=log`, and inspect `model-probe-history.jsonl` the next day.
Diagnostic log scanning is enabled by default, but `OPENCLAW_DIAG_ACTION=log` keeps it non-invasive unless the operator explicitly opts into a restart or custom command.

Tell users to review `~/.config/openclaw-gateway-watchdog/watchdog.env` before publishing, sharing logs, or reporting issues.
