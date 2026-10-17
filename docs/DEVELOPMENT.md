# Development

Requires macOS 13+ and Xcode / Swift 5.10+. How the app works internally: [TECHNICAL.md](TECHNICAL.md).

## Build and test

```sh
swift test                        # unit tests (toggle, restore, drift, devices, parser, debounce)
swift build                       # debug build of app + CLI
./scripts/build-app.sh            # release .app in build/
./scripts/install.sh              # install to ~/Applications and relaunch (restores mics first)
./scripts/make-dmg.sh             # release build packed as build/Bose-Mute-Microphone-<version>.dmg
swift scripts/make-icon.swift     # regenerate the icon after changing the drawing
```

Diagnostics:

```sh
.build/debug/bose-mute-diag list                               # read-only device/control report
.build/debug/bose-mute-diag selftest "MacBook Pro Microphone"  # mute + verify + restore ONE device; refuses devices in use
.build/debug/bose-mute-diag watch-bose                         # print Bose presses and HFP events live
```

Logs:

- **App event log**: `~/Library/Logs/Bose-Mute-Microphone.log`. It holds only state changes (mute/unmute, per-device results, HFP lines, Siri closing), never audio.
- **Raw Bluetooth evidence**: `log show --last 10m --predicate 'process == "bluetoothd" AND category == "Server.Handsfree"'`.

Settings are stored in `defaults` domain `local.brunoorlandi.BoseMuteMicrophone`:

- `soundsEnabled`
- `boseShortcutEnabled`
- `cancelSiriAfterBose`
- `ignoredDeviceUIDs`
- `loginItemConfigured`

## Tutorial images

The GIF and slides in `docs/images/tutorial/` are drawn by `scripts/make-tutorial.swift`:

```sh
swift scripts/make-tutorial.swift slides   # docs/images/tutorial/slide-1..4.png (1080x1080)
swift scripts/make-tutorial.swift gif      # docs/images/tutorial/bose-shortcut.gif (540x540)
```

The hand was generated once with Gemini "Nano Banana 2" (`gemini-3.1-flash-image`) as line art and is stored in `docs/images/tutorial/assets/hand-source.png`. The script makes its background transparent; everything else is drawn in code.

## Releasing

The convention is recorded in `.claude/release.json` and in [CLAUDE.md](../CLAUDE.md). In short:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Add the entry to [CHANGELOG.md](../CHANGELOG.md).
3. Build `./scripts/make-dmg.sh`.
4. Tag `vX.Y.Z` and publish a GitHub release with the DMG attached.

## Project layout

```
Package.swift
Sources/
  BoseMuteCore/            logic, testable without hardware
    AudioBackend.swift       device/control types + backend protocol
    CoreAudioBackend.swift   real backend (HAL properties, listeners)
    FilteringBackend.swift   hides ignored devices / single-device self-test
    MuteController.swift     mute, verify, restore, enforce, restore watch
    BoseButtonMonitor.swift  bluetoothd log stream → Bose press events
    SnapshotStore.swift      crash-safe pre-mute snapshot
    ToneGenerator.swift      in-memory WAV cues
  BoseMuteMicrophone/      menu bar app (AppKit)
    AppDelegate.swift        status item, menu, triggers, login item, event log
    HotKey.swift             ⌃⌥⌘M via Carbon RegisterEventHotKey
    SiriCanceller.swift      closes the Siri session a Bose press opened
  bose-mute-diag/          diagnostics CLI
Tests/BoseMuteCoreTests/   unit tests with a fake backend
Resources/                 Info.plist, AppIcon.icns, AppIcon-1024.png
scripts/
  build-app.sh             release build → build/Bose-Mute-Microphone.app (ad-hoc signed)
  install.sh               build + install to ~/Applications + relaunch
  make-dmg.sh              release build → build/Bose-Mute-Microphone-<version>.dmg
  make-icon.swift          draws the icon with Core Graphics → AppIcon.icns
  make-tutorial.swift      draws the Shortcut tutorial (black-and-white line art) → docs/images/tutorial
docs/DIAGNOSTICO.md        hardware/driver investigation with log evidence
```

## Removing all app data

Besides deleting the app:

```sh
rm -rf ~/Library/Application\ Support/Bose-Mute-Microphone ~/Library/Logs/Bose-Mute-Microphone.log
defaults delete local.brunoorlandi.BoseMuteMicrophone
```
