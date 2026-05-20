# Changelog

## 1.3.1

- Publish a ClawHub package that includes the Windows PowerShell installer, watchdog, and uninstaller files.

## 1.3.0

- Add an opt-in model-provider probe that uses `openclaw agent --json` against the configured OpenClaw model path.
- Add a no-credential provider edge probe that checks the configured provider `baseUrl` before the end-to-end model call.
- Add OpenClaw runtime diagnostics that snapshot gateway status, health, model status, deep status, and recent OpenClaw logs.
- Classify log signals for provider timeout, proxy/network, rate limit, auth, channel session, gateway degraded, config reload, task runtime, and related warning families.
- Record model probe evidence in the main log and `model-probe-history.jsonl` without logging API keys.
- Add configurable model failure actions: log-only, gateway restart, or a custom command after consecutive failures.
- Document safe overnight diagnostics for separating Gateway/channel failures from model-provider timeouts.

## 1.2.0

- Add OpenClaw-native health probing via `openclaw gateway status --json --require-rpc`, `openclaw health --json --verbose`, and `openclaw status --deep`.
- Add Windows Task Scheduler support with native PowerShell install, watchdog, and uninstall scripts.
- Add macOS LaunchAgent support to the Bash installer and uninstaller.
- Document cross-platform installation and native probe configuration.

## 1.1.0

- Rename the ClawHub package to `gateway-resilience-guard`.
- Expand the public summary to describe the layered probes, restart guardrails, and advantages over simple restart loops or one-URL monitors.

## 1.0.1

- Add the published ClawHub URL and install command to the README files.

## 1.0.0

- First public zero-config release.
- Install from the current folder instead of a hard-coded workspace path.
- Generate user config and systemd service automatically.
- Add layered gateway/channel/network probes.
- Add exponential backoff, hourly restart limits, lock protection, and log rotation.
- Reset failure state after five consecutive successful channel probes.
- Add ClawHub-ready `SKILL.md`.
- Initial ClawHub publication used a temporary slug before the 1.1.0 rename.
