# How Bose-Mute-Microphone works

Technical reference for contributors and the curious. The product overview is in the [README](../README.md); the hardware investigation, with log evidence, is in [DIAGNOSTICO.md](DIAGNOSTICO.md); build and release steps are in [DEVELOPMENT.md](DEVELOPMENT.md).

Tested on macOS 26.5.1 with QC Ultra 2 firmware 10.12.12.

### Muting (Core Audio)

- **Writes**: for each input device the app writes `kAudioDevicePropertyMute = 1` (input scope). When a device has no usable mute control, it sets every settable input volume element to 0 instead.
- **Read-back**: every write is read back from the driver for up to 300 ms. A device counts as muted only when the driver reports it.
  - Devices that accept the write but keep the old value are reported as **FALHOU**.
  - Devices without writable controls are reported as **NÃO suportado**.
  - Neither kind is ever shown as muted.
- **While muted**:
  - devices that appear or reconnect are muted too;
  - mute is re-applied if something else turns it off;
  - Core Audio property listeners drive this, plus a 2 s check as a safety net.
- **Unmute** restores the original mute and volume values per device and verifies them. For 20 s afterwards it keeps watching and restores again if the driver changes a value.
  - Why: a Bose Shortcut press opens and closes an HFP/SCO link for Siri. The Bluetooth driver was seen setting the headset mic back to mute = 1 after a verified restore.
- **Persistence**: pre-mute values are saved in `~/Library/Application Support/Bose-Mute-Microphone/mute-snapshot.json`. If the app crashes while muted, the next launch resumes muted mode and can restore. Quitting always restores.
- **No automatic muting.** The app never mutes at launch.

### The Bose Shortcut

The Shortcut is **not** a HID key or a media command. With *voice control* selected, the headset sends the HFP **voice-recognition request (`AT+BVRA`)**. macOS's `bluetoothd` owns the HFP link and passes the request to Siri. No public API lets a third-party app receive or intercept it.

The app **watches** the `bluetoothd` unified-log line that records it, through `/usr/bin/log stream` with a predicate on `category == "Server.Handsfree"`:

```
[com.apple.bluetooth:Server.Handsfree] Received voice recognition event from device AA:BB:CC:11:22:33
```

- **One press, one toggle.** bluetoothd logs a second line ("Received 'start voice command' event…") for the same press, and it is ignored.
- **Debounce**: 1.5 s, measured from the time the log data arrives.
- **Strict parsing.** A full Bluetooth address must follow the marker. The `log stream` header contains the marker text itself and once caused a false toggle.

### Why Siri must stay on

Every Shortcut press makes macOS start Siri, and that cannot be blocked from an app. The headset then waits for that voice session to end.

| Siri | Result |
|---|---|
| **off** | nobody answers the request. The headset sends **one** press and then ignores the Shortcut until it reconnects (seen 3 times) |
| on, app does nothing | works on every press, but Siri opens and listens each time |
| **on + "Fechar a Siri aberta pelo atalho do Bose"** (default) | works on every press. Siri flashes for about 1 s |

How the third row works:

1. After a Bose press, the app waits for the SCO link Siri opens ("Making sco connection for playing voice-command"), or 1.5 s at most.
2. It asks Siri to quit (`NSRunningApplication.terminate`). It force-quits only if Siri ignores that.
3. bluetoothd closes the voice link ("Voice command was active, sco will be closed"). This ends the session on the headset, which is then ready for the next press.
4. macOS relaunches Siri on demand.

Only Bose presses trigger this; Siri started any other way is left alone.

Tested: four presses in a row toggled mute → unmute → mute → unmute, and Siri quit cleanly each time.

### Start with the Mac

On first launch the app calls `SMAppService.mainApp.register()`. It then appears in System Settings › General › Login Items, and the menu checkbox toggles it. A user who turns it off stays off.

## Menu reference

| Item | What it does |
|---|---|
| status line | Microfones ativos / MUTADOS (n/n verificados) / PARCIAL |
| Silenciar todos os microfones / Reativar microfones (`⌃⌥⌘M`) | toggle |
| Dispositivos de entrada | each input device: default, in use, and the per-device result (mute verified, volume 0 verified, NÃO suportado, FALHOU) |
| Ignorar dispositivos › | leave a device out (e.g. a virtual loopback that ignores mute). If the app had muted it, it is restored immediately |
| Usar atalho do Bose | turn the Bose trigger on/off, plus monitor state and last event time/address |
| Iniciar com o Mac | Login Item on/off (`SMAppService`) |
| Abrir ajustes da Siri… | opens System Settings; the app never changes Siri settings itself |
| Fechar a Siri aberta pelo atalho do Bose | on by default; see [Why Siri must stay on](#why-siri-must-stay-on) |
| Sons de mute/unmute | cues on/off |
| Abrir log de diagnóstico | opens `~/Library/Logs/Bose-Mute-Microphone.log` |
| Sair (restaura microfones) | quits and restores the previous state |

## Limitations in detail

- **The mute happens in the macOS driver, not in the headset.** The headset microphone itself stays on; the QC Ultra 2 has no mic-mute control (Bose support confirms this). An app that reads the device below the HAL controls could still capture audio.
- **Some devices ignore mute.** `Microsoft Teams Audio`, a virtual loopback, accepts the write (`noErr`) but never changes the value. It shows **FALHOU** and the icon shows **MUTE?** until you put it in *Ignorar dispositivos*.
- **The Bose trigger depends on log text.** It is not a stable API and may change with macOS updates. If it breaks, `⌃⌥⌘M` and the menu keep working.
- **Side effects of a Bose press**: Siri flashes for about 1 s, and the headset audio switches to call quality (HFP) for about 1 s.
- **Multipoint.** When the headset is also connected to a phone, it can send the voice request to the phone instead. This was seen while the phone's HFP link reconnected.
- **During a call**, the headset does not offer voice control (Bose guide p.19), so use `⌃⌥⌘M` or the menu.
- **Other buttons are not used.** The Multi-function button's play/pause/next/previous (AVRCP) stay as media controls on purpose. Capture during Shortcut presses saw no media-key or HID event from the headset.
- **No drivers, no SIP changes, no extra permissions.** The app needs no Microphone or Accessibility access.
