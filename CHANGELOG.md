# Changelog

## 1.4.2

- Rework the dashboard sidebar into real view switching for Overview, Trends, Strategy, Logs, and Config instead of one long page.
- Tighten the dashboard grid, panel sizing, button alignment, and sidebar polish for a cleaner operations-console layout.
- Fix the trend chart axis label collision by removing the redundant x-axis title and reserving more space for tick labels.
- Keep charts stable across refreshes by drawing only the active view and ignoring hidden canvases.
- Move strategy explanations into centered button content and remove the sidebar localhost note.

## 1.4.1

- Redesign the dashboard with a sidebar layout, stronger visual grouping, and selectable Light, Dark, Ocean, and Forest themes.
- Add Chinese/English language switching for dashboard labels, buttons, hints, legends, and notifications.
- Fix canvas redraw sizing so repeated refreshes do not stretch dashboard panels.
- Replace "overnight timeline" with a general event trend chart that includes lanes, legends, and time-axis ticks.
- Auto-follow the newest watchdog log lines while keeping a toggle for manual scrolling.
- Add an unlock/lock action flow and strategy hover hints so guarded controls are discoverable.

## 1.4.0

- Add a standalone local dashboard at `http://127.0.0.1:18790` that remains available when OpenClaw Gateway is down.
- Add dashboard API summaries, log-signal charts, overnight timelines, status file freshness, safe config summaries, diagnostic export, and quick strategy presets.
- Add guarded dashboard actions for run diagnostics, restart Gateway, and apply presets using a generated local action token.
- Add an OpenClaw native plugin bridge that registers `/resilience-guard` and redirects to the external dashboard when Gateway is healthy.
- Install dashboard files on Linux/WSL, macOS, and Windows.

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
