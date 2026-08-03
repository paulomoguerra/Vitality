# Vitality

A native macOS menu bar app, dashboard, and Notification Centre widget that shows your Mac's vital signs at a glance — and lets you act on them.

**No dependencies.** Vitality measures everything itself through public macOS APIs. Nothing to install first, nothing to configure.

## What it does

**Menu bar** — health score, CPU, GPU, memory, disk, power, battery, and top process. Every row with more to say is clickable:

| Row | Opens |
|---|---|
| CPU | Per-core usage bars, chip, P/E core split, 1/5/15-minute load averages scaled to core count |
| GPU | Live utilisation with renderer/tiler breakdown and memory in use |
| Memory | In use / available / cached / total, plus swap — with a warning when your Mac is swapping heavily |
| Disk | Every volume with free space |
| Power / Battery | Adapter wattage, battery flow, plus battery health, max capacity and cycle count |
| Top process | The heaviest processes with PID and memory |

**Dashboard** (`Open Dashboard…`) — three tabs:

- **Overview** — health ring, machine summary, uptime, and the key metrics
- **Processes** — the full process table, filterable and sortable by CPU, memory or name. Quit or Force Quit anything you own.
- **Storage** — every volume, plus a size-sorted folder browser you can drill into. Reveal in Finder, or move items to the Trash.

**Widgets** — small, medium and large, in Notification Centre and on the desktop.

## Requirements

macOS 14 (Sonoma) or later. That's it.

## Install

```bash
./scripts/make-dmg.sh
```

Open `build/Vitality-<version>.dmg` and drag Vitality to Applications. That's the whole install.

**The widgets need the app to be running.** Vitality registers itself as a login item on first launch, so this normally takes care of itself. To add a widget: right-click the desktop or open Notification Centre → Edit Widgets → search for Vitality.

### Why there's no download link yet

There is deliberately **no GitHub Release**, because a downloaded build would not run on your Mac — and shipping a download that fails is worse than shipping none.

macOS only applies Gatekeeper to *quarantined* files. A DMG you build locally is never quarantined, so it installs and runs fine. Anything **downloaded** gets `com.apple.quarantine` stamped on it by the browser, Gatekeeper evaluates the signature, and a build signed with an *Apple Development* certificate is rejected. Apple's own tooling is blunt about it:

```
$ syspolicy_check distribution Vitality.app
App has failed one or more pre-distribution checks.
Notary Ticket Missing — Severity: Fatal
```

The right-click → Open trick rescues an *unidentified developer*; it does not bypass that.

Fixing it needs three things, all gated behind Apple's paid Developer Program (~$99/yr):

1. A **Developer ID Application** certificate
2. **Notarisation** — Apple scans and signs off on the build
3. **Stapling** the resulting ticket to the DMG

`scripts/make-dmg.sh` already handles all three. It detects a Developer ID certificate automatically and switches to it, and reports Gatekeeper's verdict on every build so the artefact's status is never a guess. Once you have the certificate, store notary credentials once:

```bash
xcrun notarytool store-credentials vitality-notary --apple-id you@example.com --team-id XXXXXXXXXX --password <app-specific-password>
```

and from then on build releases with:

```bash
NOTARIZE=1 ./scripts/make-dmg.sh
```

That produces a DMG anyone can download and drag into Applications with no warnings and no Terminal.

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
SystemMetrics (sysctl · Mach · IOKit)  ──▶  Vitality (menu bar app)
                                              │
                                              ▼  status.json
                                        App Group container
                                              │
                                              ▼
                                    VitalityWidget (WidgetKit)
```

Everything comes from public macOS APIs:

| Metric | Source |
|---|---|
| CPU, per-core | `host_processor_info` tick deltas |
| Load average | `getloadavg` |
| P/E core split | `hw.perflevel0/1.logicalcpu` |
| Memory, swap | `host_statistics64`, `vm.swapusage` |
| Disk | `URLResourceValues` volume capacities |
| GPU | IOKit `IOAccelerator` → `PerformanceStatistics` |
| Battery, cycles, health | IOKit `IOPowerSources` + `AppleSmartBattery` |
| Processes | `ps` + `kill(2)` |
| Model, chip, uptime | IOKit device tree, `sysctl` |

The app samples once a second and writes atomically to a shared App Group container. The widget extension reads that file on its WidgetKit timeline, and the app nudges WidgetKit at most once every 30 seconds — WidgetKit budgets reloads, so asking more often would refresh the widgets *less*.

Some design decisions worth being explicit about:

- **CPU usage is a delta, not a reading.** The kernel reports ticks accumulated since boot, so a single sample means nothing. `SystemMetrics` keeps the previous sample, which is why collection is serialised onto one queue — two concurrent collections would corrupt each other's deltas.
- **The health score is our own, and it explains itself.** Any single "health" number is a judgement call, so the weights are explicit in `HealthScore.swift` and the score always ships with a message naming the biggest deduction. A full boot volume weighs heaviest, then sustained swapping, then CPU saturation, then battery wear.
- **Memory "used" excludes inactive pages.** macOS keeps RAM deliberately full, so penalising a high memory figure would flag every healthy Mac. Swapping is the honest signal, and that's what the score reacts to.
- **Power is reported as two real figures, not one invented one.** Total SoC package draw — the single wattage `powermetrics` prints — needs IOReport or SMC access, neither of which is public API. Vitality reports adapter wattage and actual battery flow instead of guessing.
- **The app is not sandboxed.** It runs `ps` and reads IOKit registries. The widget extension *is* sandboxed — Apple requires that of all extensions — and only ever reads the status file.
- **The App Group ID is prefixed with the team ID.** macOS requires `TEAMID.group.example.app`; the bare `group.*` form is the iOS convention. Get this wrong and `containermanagerd` rejects the write with a generic "you don't have permission" error that looks nothing like a naming problem. The prefix is injected at build time from `DEVELOPMENT_TEAM`, so no team ID is hardcoded in source.
- **Deleting always moves to the Trash.** Vitality points you at your biggest files, which is exactly where a misread row costs something irreplaceable.

## The icon

The icon is the app's own health ring with a pulse through it — the same element the menu bar and dashboard use for the health score. It's authored as plain SVG at [`design/icon.svg`](design/icon.svg); edit that and regenerate the asset catalogue with:

```bash
python3 scripts/make-icon.py
```

That renders one 1024px master and downscales it to every size macOS needs. Downscaling a single master (rather than rendering each size straight from SVG) keeps the glow filters consistent — a 16px canvas would resolve them completely differently and the small icons wouldn't match the large one.

Three alternate designs live in [`design/alternates/`](design/alternates). To adopt one, copy it over `design/icon.svg` and regenerate:

```bash
cp design/alternates/light-clinical.svg design/icon.svg && python3 scripts/make-icon.py && xcodegen generate
```

| Alternate | Idea |
|---|---|
| `v-monogram.svg` | A heartbeat whose downstroke reads as a letter **V** — name and mark in one |
| `light-clinical.svg` | Pale, clinical tone; the only light option, so it stands out in a dark Dock |
| `heart-pulse.svg` | Solid heart with the pulse carved out as negative space |

## License

MIT — see [LICENSE](LICENSE).

## Credits

Vitality began as a front end for [Mole](https://github.com/tw93/Mole), tw93's excellent open-source Mac maintenance tool, and shipped that way for its first few versions. It now measures everything natively so it has no dependencies, but the project owes its shape — and its health-score idea — to Mole. Thank you [@tw93](https://github.com/tw93).
