# OpenClaw Gateway Watchdog

A guarded watchdog for OpenClaw Gateway. It keeps long-lived channels such as WeChat online by checking the local gateway, the channel URL, and general network reachability before restarting anything.

## Why

When WSL or the host network sleeps, switches networks, or briefly drops packets, OpenClaw Gateway can stay running while the channel connection is dead. This watchdog sits outside OpenClaw and pulls the gateway back up only when the failure is likely local and recoverable.

## Install

Run inside WSL/Linux:

```bash
bash install-watchdog.sh
```

That is enough for the default WeChat probe. For unattended install:

```bash
bash install-watchdog.sh --yes
```

For a custom channel URL:

```bash
bash install-watchdog.sh --channel-url "https://your-channel.example.com/health"
```

The installer:

- copies scripts into `~/.local/share/openclaw-gateway-watchdog`;
- writes config to `~/.config/openclaw-gateway-watchdog/watchdog.env`;
- creates a user service at `~/.config/systemd/user/gateway-watchdog.service`;
- starts the service when user systemd is available;
- falls back to a direct background process when user systemd is unavailable.

## Manage

```bash
systemctl --user status gateway-watchdog
journalctl --user -u gateway-watchdog -f
systemctl --user restart gateway-watchdog
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh
```

Purge config and logs too:

```bash
bash ~/.local/share/openclaw-gateway-watchdog/uninstall-watchdog.sh --purge
```

## Configuration

Most users do not need to edit anything. Advanced settings live in:

```text
~/.config/openclaw-gateway-watchdog/watchdog.env
```

Useful keys:

```bash
CHANNEL_URL="https://ilinkai.weixin.qq.com"
GATEWAY_HEALTH_URL="http://127.0.0.1:18789/healthz"
GATEWAY_SERVICE="openclaw-gateway"
RESTART_COMMAND="systemctl --user restart openclaw-gateway"
NETWORK_URLS="https://www.baidu.com https://www.qq.com https://api.weixin.qq.com"
```

## Safety

The watchdog uses four protections:

- layered probes: gateway, channel, then general network;
- no restart when the whole network appears down;
- exponential backoff for repeated channel failures;
- an hourly restart limit to avoid restart storms.

## ClawHub

This folder includes `SKILL.md`, so it can be published as an OpenClaw skill bundle:

```bash
clawhub publish . \
  --slug openclaw-gateway-watchdog \
  --name "OpenClaw Gateway Watchdog" \
  --version 1.0.0 \
  --changelog "Initial zero-config watchdog release"
```

Always run a dry run or inspect the metadata before publishing from a shared machine.
