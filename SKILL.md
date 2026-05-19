---
name: openclaw-weixin-gateway-watchdog
description: Install and operate a guarded watchdog that keeps OpenClaw Gateway and long-lived channels such as WeChat online by probing health, channel reachability, and general network status before restarting.
tags:
  - openclaw
  - gateway
  - watchdog
  - wechat
  - wsl
  - systemd
requirements:
  tools:
    - bash
    - curl
    - systemctl optional
permissions:
  - Writes a user-level systemd service under ~/.config/systemd/user when available.
  - Writes config and logs under ~/.config/openclaw-gateway-watchdog and ~/.local/state/openclaw-gateway-watchdog.
  - Restarts OpenClaw Gateway through systemctl --user or openclaw gateway restart.
---

# OpenClaw Gateway Watchdog

Use this skill when a user wants to keep OpenClaw Gateway and message channels online after network drops, WSL sleep/resume, or long-lived connection failures.

## Install

From this skill folder, run:

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

## Operate

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

If user systemd is unavailable, the installer starts a direct background fallback and stores its pid under `~/.local/state/openclaw-gateway-watchdog/watchdog.pid`.

## Safety Model

The watchdog restarts only after layered checks:

1. Local gateway health URL or TCP port.
2. Main channel URL.
3. General network URLs to avoid restarting during whole-machine network failure.
4. Backoff and hourly restart limits to avoid restart storms.

Tell users to review `~/.config/openclaw-gateway-watchdog/watchdog.env` before publishing, sharing logs, or reporting issues.
