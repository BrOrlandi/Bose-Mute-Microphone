# Bose-Mute-Microphone

A native macOS menu bar app (Swift, AppKit, Core Audio) that mutes every microphone on the system at once. It shows a clear indicator and plays distinct mute/unmute sounds. It also tries to use the Shortcut gesture of the Bose QuietComfort Ultra Headphones (2nd Gen) as a trigger, but that trigger is **not reliable**. See [docs/DIAGNOSTICO.md](docs/DIAGNOSTICO.md).

## What it does

- **Toggle**: the first trigger mutes all input devices. The next one restores the exact previous values, so a mic that was already muted stays muted.
- **Triggers**:
  - the menu item;
  - the global shortcut `⌃⌥⌘M` (Carbon `RegisterEventHotKey`, which needs no Accessibility permission);
  - the Bose Shortcut, when the headset actually delivers it to the Mac (best effort, see the limitations below).
- **Verification**: after every write the app reads the value back from the driver.
  - A device counts as muted only when `kAudioDevicePropertyMute` reads 1.
  - If the mute property can't be used, the device counts as muted only when every settable input volume reads 0.
  - Devices that accept the write but don't apply it are reported as failed.
- **Device changes while muted**: new or reconnected devices are muted too, and mute is re-applied if another app turns it off. Core Audio listeners drive this, with a 2-second check as a safety net.
- **Indicator**:
  - `mic` icon: microphones active;
  - red `mic.slash` + **MUTE**: every present device verified muted;
  - orange ⚠︎ + **MUTE?**: only partly muted.
  - The menu lists each device with its result.
- **Sounds**: the tones are synthesized in memory (descending for mute, ascending for unmute) and play on the default output. Nothing is recorded or stored.
- **Safety**:
  - The app never mutes on its own at launch.
  - Quitting restores the previous state.
  - Pre-mute values are saved to `~/Library/Application Support/Bose-Mute-Microphone/mute-snapshot.json`, so after a crash the next launch resumes the muted state and can restore it.
- **Ignore devices**: a submenu excludes devices such as virtual loopbacks that ignore mute.
- **Siri**: the Shortcut asks macOS for Siri. With Siri turned off in System Settings, the press still reaches the app and Siri stays closed (tested). The menu shows a tip and opens the settings; the app never changes the setting itself.
- **Start with the Mac**: the app registers itself as a Login Item (`SMAppService.mainApp`) on first run. The menu checkbox toggles it.

## Build, install, run

Requires macOS 13+ and Xcode / Swift 5.10+.

```sh
swift test                 # unit tests (fake Core Audio backend)
./scripts/build-app.sh     # build/Bose-Mute-Microphone.app (release, ad-hoc signed)
./scripts/install.sh       # build + copy to ~/Applications + (re)launch
swift scripts/make-icon.swift   # regenerate Resources/AppIcon.icns (only after changing the drawing)
```

Diagnostics CLI:

```sh
swift build
.build/debug/bose-mute-diag list                      # read-only device/control report
.build/debug/bose-mute-diag selftest "MacBook Pro Microphone"   # mute+verify+restore ONE device; refuses devices in use
.build/debug/bose-mute-diag watch-bose                # print Bose Shortcut / HFP events as they arrive
```

Event log: `~/Library/Logs/Bose-Mute-Microphone.log` (state changes only, no audio).

## Limitations (honest)

- **Muting happens in the driver, not in the headset.** For the Bose and the built-in mic, the mute is the Core Audio driver's mute control, applied by macOS. The headset's own microphone is not turned off, and the QC Ultra 2 has no mute control. Bose support confirms this.
- **Some devices can't be muted.** `Microsoft Teams Audio`, a virtual loopback, reports mute as settable and returns `noErr`, but the value never changes. It shows as *FALHOU* and the indicator says **MUTE?** until you ignore it.
- **An app that bypasses the HAL controls can still capture audio.** This app uses public Core Audio controls only. It does not install a driver, does not disable SIP and does not request extra permissions.
- **The Bose Shortcut is not a reliable trigger.** The gesture arrives as an HFP voice-recognition request (`AT+BVRA`) that macOS's `bluetoothd` hands to Siri. There is no public API to intercept it. The app watches the `bluetoothd` log line instead: Siri is still asked to start, and the log text may change between macOS versions. With multipoint, the headset may send the request to the phone, or not send it at all. Details and evidence are in [docs/DIAGNOSTICO.md](docs/DIAGNOSTICO.md).
