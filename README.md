# Vitality

A native macOS menu bar app, dashboard, and Notification Centre widget that shows your Mac's vital signs at a glance — and lets you act on them.

Vitality is a small, native front end for [Mole](https://github.com/tw93/Mole) — a terminal tool that does the system inspection. Mole does the measuring; Vitality makes it glanceable and clickable.

## What it does

**Menu bar** — health score, CPU, memory, disk, power draw, battery, and top process. Every row with more to say is clickable:

| Row | Opens |
|---|---|
| CPU | Per-core usage bars, chip, P/E core split, 1/5/15-minute load averages scaled to core count |
| Memory | In use / available / cached / total, plus swap — with a warning when your Mac is swapping heavily |
| Disk | Every volume with free space and SMART state |
| Power / Battery | System draw, adapter, fan, plus battery health, max capacity and cycle count |
| Top process | The five heaviest processes with PID and memory |

**Dashboard** (`Open Dashboard…`) — three tabs:

- **Overview** — health ring, machine summary, uptime, and the four key metrics
- **Processes** — the full process table, filterable and sortable by CPU, memory or name. Quit or Force Quit anything you own.
- **Storage** — every volume, plus a size-sorted file browser you can drill into. Reveal in Finder, or move items to the Trash.

**Widgets** — small, medium and large, in Notification Centre and on the desktop.

## Requirements

- macOS 14 (Sonoma) or later
- [Mole](https://github.com/tw93/Mole), which provides the `mo` command:

```bash
brew install mole
```

Vitality does **not** bundle Mole. You install it yourself, and Vitality runs it.

## Install

Build the disk image:

```bash
./scripts/make-dmg.sh
```

Then open `build/Vitality-<version>.dmg` and drag Vitality to Applications.

> **Signing:** the DMG is signed with whatever identity your team provides. An *Apple Development* identity is enough to run Vitality on **your own** Mac, but macOS will refuse it on anyone else's. Distributing to other people needs the paid Apple Developer Program, a *Developer ID Application* certificate, and notarisation via `xcrun notarytool`. There is no notarised release yet.

**The widgets need the app to be running.** Vitality registers itself as a login item on first launch, so this normally takes care of itself. To add a widget: right-click the desktop or open Notification Centre → Edit Widgets → search for Vitality.

## Build from source

**1.** Install the tooling:

```bash
brew install xcodegen
```

**2.** Set your Apple Developer Team ID. A free Apple ID works for local builds:

```bash
cp Local.xcconfig.example Local.xcconfig
```

Edit `Local.xcconfig` and replace `XXXXXXXXXX` with your Team ID (find it at [developer.apple.com/account](https://developer.apple.com/account) → Membership details). This file is gitignored, so no signing identity ends up in the repo.

**3.** Generate the Xcode project and open it:

```bash
xcodegen generate
open Vitality.xcodeproj
```

<details>
<summary>Building from the command line</summary>

```bash
xcodebuild -project Vitality.xcodeproj -scheme Vitality -configuration Debug \
  -allowProvisioningUpdates build
```

`-allowProvisioningUpdates` is needed whenever bundle IDs or the App Group change, so Xcode can register them under your team.

If it fails with *"tool 'xcodebuild' requires Xcode"*, your `xcode-select` path points at the Command Line Tools rather than a full Xcode. Override it per-command instead of switching system-wide:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Vitality.xcodeproj -scheme Vitality -configuration Debug -allowProvisioningUpdates build
```

</details>

## How it works

```
mo status --json  ──▶  Vitality (menu bar app)  ──▶  App Group container
                                                        │  status.json
                                                        ▼
                                              VitalityWidget (WidgetKit)
```

The app runs `mo status --json` every three seconds on a background task, decodes it, and writes it atomically to a shared App Group container. The widget extension reads that file on its WidgetKit timeline, and the app nudges WidgetKit at most once every 30 seconds — WidgetKit budgets reloads, so asking more often would get Vitality throttled and refresh the widgets *less*.

Four design decisions worth being explicit about:

- **The app is not sandboxed.** App Sandbox forbids executing an external binary that isn't embedded in the app's own bundle, which would make calling Homebrew's `mo` impossible. The widget extension *is* sandboxed — Apple requires that of all extensions — and only ever reads.
- **The App Group ID is prefixed with the team ID.** macOS requires `TEAMID.group.example.app`; the bare `group.*` form is the iOS convention. Get this wrong and `containermanagerd` rejects the write with a generic "you don't have permission" error that looks nothing like a naming problem. The prefix is injected at build time from `DEVELOPMENT_TEAM`, so no team ID is hardcoded in source.
- **Process listing and quitting use `ps` and `kill` directly, not Mole.** Mole has no process-management commands, and its `status --json` returns only the top five — too thin to manage anything. Only processes you own can be signalled; that's macOS, not Vitality.
- **Mole's destructive commands are not automated.** `mo clean`, `purge` and `uninstall` are interactive terminal UIs with no JSON or non-interactive mode. Driving them headlessly would mean screen-scraping a UI that deletes files, so Vitality hands off to Terminal instead. Vitality's own delete path moves items to the **Trash**, never `rm`.

## Relationship to Mole, and licensing

Vitality is an independent project. It is **not** affiliated with, sponsored by, or endorsed by Mole or its author.

Vitality contains no Mole source code. Mole is written in Go; Vitality is written in Swift. The only point of contact is running the `mo` command-line tool and parsing its public JSON output — two separate programs communicating at arm's length. That is why Vitality can be MIT licensed while Mole is GPL-3.0: Vitality is not a derivative work of Mole, and it does not redistribute any part of it.

Vitality never ships the `mo` binary. You install Mole yourself via Homebrew, under Mole's own license.

| | License |
|---|---|
| **Vitality** (this project) | MIT — see [LICENSE](LICENSE) |
| **Mole** (separate dependency) | GPL-3.0-or-later, © [tw93](https://github.com/tw93) |

## Credits

Vitality is only useful because [Mole](https://github.com/tw93/Mole) exists. All the hard work of actually measuring the system is Mole's — thank you [@tw93](https://github.com/tw93).
