<p align="center">
  <img src="Resources/AppIcon-1024.png" alt="Bose-Mute-Microphone icon" width="160">
</p>

<h1 align="center">Bose-Mute-Microphone</h1>

<p align="center">
  <img src="docs/images/tutorial/bose-shortcut.gif" alt="Touch and hold the volume strip on the right ear cup for about 2 s to mute; repeat to unmute" width="540">
</p>

<p align="center"><b>Mute every microphone on your Mac from your Bose QuietComfort Ultra Headphones.</b></p>

Touch and hold the volume strip on the right ear cup, and all your Mac's microphones go silent: built-in, headset, USB, any app. Hold it again and they come back exactly as they were. A crossed-out mic in the menu bar and a short tone in your ears tell you which state you're in.

## Features

- **One gesture, every mic.** Mutes all input devices on the Mac at once, not just the one a call app happens to use.
- **Works from your headphones.** The Shortcut on the Bose QuietComfort Ultra Headphones (2nd Gen) toggles mute. No need to reach for the keyboard.
- **Also from the keyboard or the menu.** Press `⌃⌥⌘M` anywhere, or use the menu bar icon.
- **You always know the state.** The menu bar shows a crossed-out mic with **MUTE**, and you hear a falling tone when muting and a rising tone when unmuting.
- **Really muted, or it tells you.** The app checks that every device actually went silent. If one can't be muted, the icon warns you instead of pretending.
- **Puts things back as they were.** Unmuting restores each mic's previous state, so a mic you had muted yourself stays muted.
- **Keeps up with changes.** A mic you plug in or connect while muted is muted too.
- **Safe.** It never mutes on its own, quitting restores your microphones, and it starts with your Mac.
- **Lightweight and private.** Native menu bar app. It records nothing, sends nothing and needs no special permissions.

## Install

1. Download the latest **`Bose-Mute-Microphone-x.y.z.dmg`** from [Releases](https://github.com/BrOrlandi/Bose-Mute-Microphone/releases).
2. Open it and drag the app to **Applications**.
3. Launch it. The app isn't notarized by Apple, so the first time macOS blocks it:
   1. dismiss the warning;
   2. open System Settings › Privacy & Security;
   3. click **Open Anyway**.

   You only need to do this once.

Requires macOS 13 or later.

## Set up your headphones

1. In the **Bose app** on your phone, set the **Shortcut** to **voice control**.
2. On the Mac, keep **Siri turned on**. The headphones need Siri to answer each press. The app closes Siri right away, so you only see it flash for a moment.

That's it: **touch and hold the volume strip for about 2 seconds** to mute, and do it again to unmute.

## Using it

| To | Do this |
|---|---|
| Mute or unmute | Hold the Bose volume strip ~2 s, press `⌃⌥⌘M`, or click the menu bar icon › *Silenciar todos os microfones* |
| See what's muted | Open the menu: every microphone is listed with its state |
| Leave a device alone | Menu › *Ignorar dispositivos* |
| Turn sounds or start-at-login off | Menu › *Sons de mute/unmute* / *Iniciar com o Mac* |

| Menu bar icon | Meaning |
|---|---|
| microphone | microphones on |
| crossed-out microphone + **MUTE** | every microphone is muted |
| ⚠︎ **MUTE?** | muted, but at least one device couldn't be muted (shown in the menu) |

## Good to know

- **The mute is done by macOS, not by the headphones.** Every app on the Mac stops receiving audio, but the QC Ultra 2 itself has no mic-mute switch.
- **A Bose press briefly shows Siri.** The audio in the headphones also switches to call quality for about a second.
- **During a call, use `⌃⌥⌘M` or the menu.** The headphones don't offer the Shortcut while a call is active.
- **Paired with a phone too?** The headphones may send the Shortcut to the phone instead of the Mac.
- **Some virtual devices ignore mute.** One example is *Microsoft Teams Audio*. Add them to *Ignorar dispositivos* if you don't need them.

How it works, and why the Shortcut goes through Siri: [docs/TECHNICAL.md](docs/TECHNICAL.md). Building from source: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Uninstall

1. Turn off *Iniciar com o Mac* in the menu.
2. Quit the app (this restores your microphones).
3. Drag it from Applications to the Trash.

## License

[MIT](LICENSE). Changes are listed in the [changelog](CHANGELOG.md).

Not affiliated with, endorsed by, or sponsored by Bose Corporation. "Bose" and "QuietComfort" are trademarks of Bose Corporation, used here only to describe the hardware this app works with.
