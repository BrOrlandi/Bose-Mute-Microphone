# Bose QC Ultra 2 Shortcut and microphone mute: diagnosis

Hardware: Bose QC Ultra Headphones (2nd Gen) "Bose QC Ultra 2", firmware 10.12.12, VID 0x009E / PID 0x4082. Mac: macOS 26.5.1. Phone: an Android phone with Bose app 13.3.4. Dates are 2026-10-14 (local time, -03).

## 1. What the Shortcut gesture sends

Per the Bose owner's guide (897194, p.20), the Shortcut is "touch and hold the volume strip". It can be set to "Use your device voice control". The guide also says voice control is not available during a call (p.19).

Captures on the Mac while the gesture was used:

| Source | Result |
|---|---|
| IOHIDManager (all HID devices) | nothing from the headset. The only HID values seen were the MacBook lid-angle sensor (page 0x20) |
| `NSEvent` system-defined (media keys) and `MPRemoteCommandCenter` | nothing |
| `bluetoothd` unified log | `23:19:33.726 [Server.Handsfree] Received voice recognition event from device AA:BB:CC:11:22:33`, then `Received 'start voice command' event …` and `[Server.MacCoex] Received Start Voice Command - Activating Siri` |

Conclusion (proven): the gesture is an **HFP voice-recognition request (AT+BVRA)**, not a HID key and not an AVRCP command. macOS `bluetoothd` owns the HFP link and routes the request to Siri. `IOBluetoothHandsFreeAudioGateway` would open a second gateway that competes with bluetoothd, so no public API delivers this event to a third-party app.

The app detects it by streaming that one log line (`/usr/bin/log stream --predicate 'process == "bluetoothd" AND category == "Server.Handsfree" …'`). This only observes the event, it does not intercept it.

## 2. Why the button stopped arriving

- Over about 3 hours, the Mac received **exactly one** voice-recognition event (23:19:33), although the gesture was used many times.
- Read-only ADB on the phone (`dumpsys bluetooth_manager`) shows:
  - the headset is bonded and connected to the phone too (multipoint, `ACL BR/EDR:Y`);
  - it is the phone's active HFP/A2DP device;
  - `mVoiceRecognitionStarted: false`.
- The phone's HFP link was **down from 23:13:09 to 23:31:54**. The one event that reached the Mac falls inside that window.
- After the phone reconnected (23:31:54), the phone's `HeadsetStateMachine` records no voice-recognition event, and the Mac's log has none either, during the user's failed test (about 23:32–23:33).

What is proven: the Mac received the request only while the phone's HFP link was down. During the failed test, neither the Mac nor the phone logged one.

Hypotheses, not proven:

- (a) With multipoint, the headset sends BVRA only to its primary/last-active source, or not at all when the phone holds that role.
- (b) After the 23:19:33 request, macOS logged "Activating Siri", but Siri did not appear and no SCO link was opened. The headset may then have waited for a +BVRA reply that never came, and ignored later presses until it reconnected.
- (c) The gesture was not recognized (hold too short, or a swipe changed the volume instead; volume changes were logged at 23:20).

**Siri regression check.** Siri already failed to open at 23:19:33. That was before this project wrote any value to the Bose microphone; the first write happened at 23:28:08. No Siri, Bluetooth or system setting was changed. The temporary capture tools were passive and have been stopped:

- `log stream`;
- an `NSEvent`/`MPRemoteCommandCenter`/non-exclusive `IOHIDManager` monitor.

Smallest test that settles it: with no call active, use the gesture once while watching `bose-mute-diag watch-bose` on the Mac. Then try again with the phone's Bluetooth temporarily off. That last step is the user's choice; it was not done here.

Bottom line: **the Bose button is not a reliable global trigger with current public APIs.** The menu item and `⌃⌥⌘M` are the dependable triggers.

## 3. Mute verification on real devices

`bose-mute-diag selftest` runs on one device at a time and refuses devices in use. The full app was then tested with `⌃⌥⌘M` while no input was in use:

| Device | Method | Result |
|---|---|---|
| Bose QC Ultra 2 (Bluetooth) | `kAudioDevicePropertyMute` (input) | mute read back 1; restored to 0; volume 1.000 unchanged |
| MacBook Pro Microphone | `kAudioDevicePropertyMute` | read back 1; restored 0; volume 0.541 unchanged |
| Microsoft Teams Audio (virtual) | mute and volume both "settable" | write returns noErr but the value never changes (checked again 2 s later): reported as **FAILED**, never as muted |

Quitting while muted restored all values and removed the snapshot file. The Bose mute is a Core Audio driver control, applied in software by macOS. It does not turn off the headset's microphone, and HFP has no standard mic-mute command.

## 4. Incident during development

On the first launch (23:28:08) the app muted every input without being asked. `log stream` prints a header line ("Filtering the log data using … Received voice recognition event from device …") that contains the marker text, and the parser took it for a button press. No input was in use at the time. The app was quit 9 s later, and the values were restored and checked.

Fix: the parser now requires a full Bluetooth address after the marker and ignores the header. A regression test covers it (`testIgnoresLogStreamHeaderThatContainsTheMarker`).
