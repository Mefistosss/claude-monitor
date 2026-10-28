# Claude Monitor

macOS widget that shows remaining Claude subscription limits:

- 5-hour session limit with live countdown to reset
- weekly limit and per-model weekly limits (e.g. Fable)
- tokens used by Claude Code on this Mac in the last 5 hours (from `~/.claude/projects` logs)
- plan name and time left until Claude Code asks you to log in again

UI is localized in English, Ukrainian and Russian (follows the system language).

## How it works

`Claude Monitor.app` runs in the background (no Dock icon). Every 5 minutes and after wake it reads
Claude Code's OAuth credentials from the Keychain (`Claude Code-credentials`), queries
`https://api.anthropic.com/api/oauth/usage`, and writes a snapshot to the shared App Group container,
which the WidgetKit extension renders. The app never refreshes the OAuth token itself, so it cannot
interfere with Claude Code's login; if Claude Code hasn't run for a while, the widget shows stale data
with a warning.

## Install

1. Move `Claude Monitor.app` to `/Applications` and open it once (it enables launch at login).
2. Right-click the desktop → Edit Widgets → search for "Claude" → add the medium widget.

## Build

```sh
brew install xcodegen
xcodegen generate
open ClaudeMonitor.xcodeproj
```

## Release

`scripts/release.sh` builds a Developer ID-signed, notarized and stapled `dist/ClaudeMonitor-<version>.dmg`;
`scripts/release.sh --publish` also creates the GitHub release `v<version>` with the DMG attached.
The version comes from `MARKETING_VERSION` in `project.yml`. One-time setup is described at the top of the script.
