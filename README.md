# Vitality

A native macOS menu bar app and Notification Centre widget that shows your Mac's vital signs at a glance.

Vitality is a small, native front end for [Mole](https://github.com/tw93/Mole) — a terminal tool that does the actual system inspection. Mole does the measuring; Vitality makes it glanceable.

**Shows:** health score · CPU · memory · disk · power draw · battery · top CPU process

## Requirements

- macOS 14 (Sonoma) or later
- [Mole](https://github.com/tw93/Mole), which provides the `mo` command:

```bash
brew install mole
```

Vitality does **not** bundle Mole. You install it yourself, and Vitality runs it.

## Build from source

There are no binary releases yet — build it locally.

**1.** Install the tooling:

```bash
brew install xcodegen
```

**2.** Set your Apple Developer Team ID. A free Apple ID works for local builds:

```bash
cp Local.xcconfig.example Local.xcconfig
```

Then edit `Local.xcconfig` and replace `XXXXXXXXXX` with your Team ID (find it at [developer.apple.com/account](https://developer.apple.com/account) → Membership details). This file is gitignored, so no signing identity ends up in the repo.

**3.** Generate the Xcode project and open it:

```bash
xcodegen generate
open Vitality.xcodeproj
```

Build and run the `Vitality` scheme. The app has no window — it lives in the menu bar, and registers itself as a login item on first launch.

To add the widget: right-click the desktop → Edit Widgets → search for Vitality. Small, medium, and large sizes are supported.

<details>
<summary>Building from the command line</summary>

```bash
xcodebuild -project Vitality.xcodeproj -scheme Vitality -configuration Debug \
  -allowProvisioningUpdates build
```

`-allowProvisioningUpdates` is needed on the first build so Xcode can register the app IDs and the App Group under your team. Building from the Xcode GUI handles this for you.

If that fails with *"tool 'xcodebuild' requires Xcode"*, your `xcode-select` path points at the Command Line Tools rather than a full Xcode. Override it for the one command instead of switching it system-wide:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Vitality.xcodeproj -scheme Vitality -configuration Debug build
```

</details>

## How it works

```
mo status --json  ──▶  Vitality (menu bar app)  ──▶  App Group container
                                                        │  status.json
                                                        ▼
                                              VitalityWidget (WidgetKit)
```

The menu bar app runs `mo status --json` every two seconds on a background task, decodes it, and writes the result to a shared App Group container. The widget extension reads that same file on its WidgetKit timeline.

The menu bar popover is live. The widget refreshes on WidgetKit's schedule (roughly every five minutes) — that budget is controlled by the system, not by Vitality.

Two design notes worth being explicit about:

- **The app is not sandboxed.** App Sandbox forbids a sandboxed process from executing an external binary that isn't embedded in its own bundle, which would make calling Homebrew's `mo` impossible. The widget extension *is* sandboxed — Apple requires that for all extensions, and it only ever reads the status file.
- **Status collection lives in the app, not a background daemon.** Vitality is a login item and expected to run continuously, so a separate always-on helper process would be extra machinery for no real gain.

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
