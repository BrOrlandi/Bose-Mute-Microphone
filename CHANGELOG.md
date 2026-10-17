# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-17

First release.

### Added

- **Global microphone mute from the menu bar.** One action mutes every input device on the Mac. The next one restores the exact previous mute and volume values, so a mic that was already muted stays muted.
- **Bose QC Ultra 2 Shortcut as a trigger.** Touch and hold the volume strip on the right ear cup, with the Shortcut set to voice control in the Bose app. The app recognizes the press from the Bluetooth log.
- **Siri closes automatically.** Every Shortcut press makes macOS start Siri. The app closes it right away, so the headset is ready for the next press. On by default.
- **Other triggers:** the `⌃⌥⌘M` keyboard shortcut and a menu item. Neither needs any permission.
- **Verified state.** Each device counts as muted only when its driver reports it. Devices that ignore mute are flagged and never shown as muted. Devices that appear while muted are muted too.
- **Clear indicator and sounds.** A crossed-out mic with MUTE in the menu bar, an orange warning when muting is only partial, and distinct falling and rising tones.
- **Safe by design:**
  - the app never mutes at launch;
  - quitting restores the microphones;
  - a crash while muted can be recovered on the next launch;
  - for 20 s after unmute, values the Bluetooth driver flips back are restored again.
- **Starts with the Mac** (Login Item), with a menu switch to turn it off.
- **Menu options:** ignore specific devices, turn sounds on and off, and open the event log.
- **`bose-mute-diag` command-line tool** for device reports, a single-device self-test and live Bose event watching.

[1.0.0]: https://github.com/BrOrlandi/Bose-Mute-Microphone/releases/tag/v1.0.0
