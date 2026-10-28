# Claude Monitor

A macOS desktop widget that shows how much of your Claude subscription limits you have left.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20WidgetKit-orange)

## What it shows

The medium-size widget displays:

| Item | Description |
|---|---|
| **5-hour limit** | Ring with the remaining percentage of the current 5-hour session limit and a live countdown to its reset |
| **Weekly limit** | Remaining percentage of the weekly limit and when it resets |
| **Per-model limits** | Separate weekly limits for specific models (e.g. Fable), when your plan has them |
| **Tokens** | Output and cache-read tokens used by Claude Code on this Mac in the last 5 hours |
| **Plan** | Your subscription, e.g. `Max 5x` |
| **Login** | Time until Claude Code asks you to `/login` again (turns orange 3 days before) |

Bars and the ring turn orange below 30% and red below 10%. If the data could not be refreshed, the widget
keeps showing the last values with a warning.

The interface is available in **English**, **Ukrainian** and **Russian** and follows the system language.

## Requirements

- macOS 14 Sonoma or later
- [Claude Code](https://claude.com/claude-code) installed and logged in with a Claude Pro or Max subscription
  (`claude` → `/login`)

## Installation

1. Download `ClaudeMonitor-<version>.dmg` from the [latest release](https://github.com/Mefistosss/claude-monitor/releases/latest).
2. Open the DMG and drag **Claude Monitor** into **Applications**.
3. Launch **Claude Monitor** once. Its window opens and the app enables launch at login.
4. Add the widget:
   - **Desktop:** right-click the desktop → **Edit Widgets…** → search for **Claude** → add the widget → **Done**.
   - **Notification Center:** click the date and time in the menu bar → scroll down → **Edit Widgets…**.

The app is signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings.

### Using the app

Claude Monitor runs in the background without a Dock icon. Click the widget (or open the app again) to show its
window, where you can:

- see the same data as the widget and when it was last updated
- refresh the data immediately
- turn **Launch at login** on or off
- quit the app

### Uninstall

Quit the app from its window, then move **Claude Monitor** from **Applications** to the Trash. The widget is removed
together with the app.

## How it works

```
Keychain ("Claude Code-credentials") ─┐
                                      ├─> Claude Monitor.app ──> App Group snapshot.json ──> widget
api.anthropic.com/api/oauth/usage ────┤        (every 5 min
~/.claude/projects/**/*.jsonl ────────┘         and on wake)
```

- **Limits** come from `https://api.anthropic.com/api/oauth/usage`, the same endpoint Claude Code's `/usage`
  command uses. It reports percentages, not absolute token counts. Anthropic does not publish how many tokens a
  limit equals.
- **Credentials** are Claude Code's OAuth token, read from the Keychain via `/usr/bin/security`, so no Keychain
  prompt appears. The token is sent only to `api.anthropic.com`.
- **Token counts** are summed from Claude Code's local session logs, so they include only Claude Code on this Mac,
  not claude.ai chats or other devices.
- **The app never refreshes the OAuth token itself.** Refreshing rotates the refresh token, which could log Claude
  Code out. Claude Code refreshes the access token while you use it; if you haven't used Claude Code for several hours,
  the widget shows *"Open Claude Code to refresh"* until you do.

> **Note:** The usage endpoint is internal and undocumented. It may change without notice, which could break the
> widget until the app is updated. This project is not affiliated with Anthropic.

## Troubleshooting

| Problem | Solution |
|---|---|
| Widget is not in the gallery | Make sure the app is in **Applications** and was launched at least once, then reopen the widget gallery |
| *"Open Claude Monitor to start"* | The app has not run yet. Launch **Claude Monitor** |
| *"Open Claude Code to refresh"* | The access token expired. Run any command in Claude Code, then click **Refresh** in the app |
| *"Not logged in to Claude Code"* | Run `claude` and `/login` |
| *"No connection, data may be stale"* | Network or API error. The app retries every 5 minutes |

## Building from source

Requires Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open ClaudeMonitor.xcodeproj
```

`ClaudeMonitor.xcodeproj` is generated from `project.yml`; edit `project.yml` and regenerate rather than changing
project settings in Xcode. To build with your own Apple developer account, replace the team ID `89X7GT8Y93` in
`project.yml`, `Shared/UsageSnapshot.swift` (App Group) and `scripts/release.sh`.

### Project layout

| Path | Contents |
|---|---|
| `App/` | Background host app: credentials, usage API, log scanner, refresh loop, window |
| `Widget/` | WidgetKit extension |
| `Shared/` | Snapshot model, App Group storage, widget layout, string catalog (`Localizable.xcstrings`) |
| `scripts/release.sh` | Signed and notarized release build |

## Releasing

`scripts/release.sh` archives the app, exports it with a Developer ID, packs it into a DMG, notarizes and staples
it, and writes `dist/ClaudeMonitor-<version>.dmg` with a SHA-256 checksum.

```sh
# 1. Bump MARKETING_VERSION in project.yml, commit and push
git push
# 2. Build, notarize and create the GitHub release v<version>
scripts/release.sh --publish
```

One-time setup:

1. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → Manage Certificates → **+**.
2. Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security.
3. Store notarization credentials in the Keychain:
   ```sh
   xcrun notarytool store-credentials claude-monitor \
     --apple-id <apple-id> --team-id 89X7GT8Y93 --password <app-specific-password>
   ```

Set `NOTARY_PROFILE` to use a profile with a different name.
