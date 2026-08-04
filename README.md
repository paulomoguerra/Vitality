# Vitality

A native macOS menu bar app, dashboard, and Notification Centre widget that shows your Mac's vital signs at a glance — and lets you act on them.

**No dependencies.** Vitality measures everything itself. Nothing to install first, nothing to configure.

Almost all of it goes through documented macOS APIs. The exception is temperature and wattage, which have no public interface at all — see [Temperatures and power](#temperatures-and-power).

## What it does

**Live figures in the menu bar** — pick which readings sit next to the Vitality icon and watch them update every second: CPU, CPU temperature, GPU, GPU temperature, memory, disk, power draw, power in, battery, health. `Menu bar…` in the popover chooses them, with a live preview of the result.

| Option | What it does |
|---|---|
| Show | Which of the ten metrics appear, in a fixed order so the strip never reshuffles |
| Colour | `When it matters` (default — plain until a reading goes orange or red), `Always`, or `Never` |
| Labels | The `CPU` / `GPU°` / `RAM` tags before each number |
| Graph | A 40-second sparkline on everything that moves — usage, temperatures and wattage |
| Vitality icon | The gauge itself — and it stays put if you turn everything else off, so the app can't hide from you |

Each reading reserves room for its widest possible value, so a Mac going from 9% to 100% never shoves the rest of your menu bar sideways.

**Menu bar popover** — health score, CPU, GPU, temperature, memory, disk, power, battery, and top process. Every row with more to say is clickable:

| Row | Opens |
|---|---|
| CPU | Per-core usage bars, chip, P/E core split, 1/5/15-minute load averages scaled to core count |
| GPU | Live utilisation with renderer/tiler breakdown and memory in use |
| Temperature | CPU (split by performance and efficiency cores), GPU, battery, storage, enclosure, and the hottest sensor on the machine |
| Memory | In use / available / cached / total, plus swap — with a warning when your Mac is swapping heavily |
| Disk | Every volume with free space |
| Power / Battery | What the Mac is drawing, what is coming in over the cable, what the difference is going to, plus battery health, max capacity and cycle count |
| Top process | The heaviest processes with PID and memory |

**Dashboard** (`Open Dashboard…`) — four tabs:

- **Overview** — health ring, machine summary, uptime, and the key metrics
- **Processes** — the full process table, filterable and sortable by CPU, memory or name. Quit or Force Quit anything you own.
- **Storage** — every volume, plus a size-sorted folder browser you can drill into. Reveal in Finder, or move items to the Trash.
- **Sensors** — every temperature sensor the Mac reports, grouped by what it measures, with the raw SMC key beside each reading

**Widgets** — small, medium and large, in Notification Centre and on the desktop.

## Temperatures and power

macOS publishes no API for die temperature or system wattage. `powermetrics` needs root, IOReport is a private framework, and IOKit's HID sensors are named things like `PMU tdie7` — real readings that cannot be attributed to the CPU or the GPU. So Vitality reads the SMC, which is the only source that names what it is measuring.

That is a deliberate exception, kept as narrow as possible:

- It uses **public IOKit calls** to talk to the `AppleSMC` driver. No private framework is linked and no symbol is resolved at runtime, so it cannot break by a missing symbol — only by Apple changing the driver's protocol, which shows up as no reading rather than a crash.
- Every value is optional the whole way to the screen. A Mac that answers nothing shows no temperatures; it never shows an invented one.
- No root, no entitlement, no helper tool. It does require the app to stay outside the sandbox — a sandboxed process cannot open `AppleSMC` at all.

Two consequences worth knowing:

**Cluster figures are means, not peaks.** Each core reports several sensors across the die and the hottest runs ~10°C above the rest even at idle, so a maximum would read alarmingly high all the time. The peak is still shown separately as the hottest sensor.

**"Drawing now" and "Coming in" are different numbers on purpose.** `PSTR` is what the machine consumes; `PDTR` is what crosses the cable. The gap is conversion loss and whatever is going into the battery. The adapter's *rating* is a third number again — a 70W charger reports 70W whether the Mac is pulling 8W or 60W.

Sensors Vitality can read but cannot name are still listed, under "Unidentified", rather than quietly dropped.

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
