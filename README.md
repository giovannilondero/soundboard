# Soundboard

Keyboard soundboard for macOS. A dedicated layer on the Dygma Defy sends **Hyper (⌃⌥⇧⌘) + key**;
a small Swift menu bar daemon catches those hotkeys and plays the mapped sound **only through the
MacBook speakers**, even while headphones are the system output. Spotify, YouTube and calls stay in the headphones.

## How it works

- The daemon opens the `MacBook Pro Speakers` CoreAudio device directly (by name → UID) and binds an
  `AVAudioEngine` to it. The system default output is never touched, so nothing else is rerouted.
- Before each play it unmutes the speakers and sets *their* volume to `volume` from the config
  (independent from the headphone volume). When playback ends (or on Stop) the previous speaker
  volume and mute state are restored (`restoreVolume: true`, set to `false` to leave them as is).
- A new sound interrupts the previous one. Hyper+Esc stops everything.
- If the speakers device is not found the sound is **not** played (never falls back to headphones); the
  menu bar icon turns into a warning triangle with the reason in the menu.
- Global hotkeys use Carbon `RegisterEventHotKey`, no Accessibility permission needed.

## Install

```sh
make install        # build, copy to bin/, install LaunchAgent, symlink into /opt/homebrew/bin
soundboard doctor   # verify devices, config, sounds
```

`make restart` rebuilds and restarts the daemon after code changes. `make uninstall` removes the LaunchAgent.

## Adding sounds

```sh
soundboard import ~/Downloads/laugh.mp3 --key a --name "Laugh"
soundboard import clip.wav --key s --max 5 --fade 0.3   # cut at 5 s, 0.3 s fade-out
soundboard import other.mp3 --key a --force              # replace what is on "a"
```

`import` runs ffmpeg two-pass `loudnorm` (−16 LUFS, −1 dBTP), trims leading/trailing silence, writes a
48 kHz stereo WAV into `sounds/` and updates `config.json`. The running daemon reloads automatically.

Key names: letters, digits, `- = [ ] ; ' , . / \` ` `` `, `space`, `tab`, `return`, `escape`, `delete`, arrows, `f1`–`f20`.

## Config (`config.json`)

```json
{
  "outputDevice": "MacBook Pro Speakers",
  "volume": 1.0,
  "restoreVolume": true,
  "stopKey": "escape",
  "soundsDir": "~/Soundboard/sounds",
  "logFile": "~/Soundboard/soundboard.log",
  "sounds": {
    "a": { "file": "laugh.wav", "name": "Laugh" },
    "s": { "file": "applause.wav", "name": "Applause", "gain": 0.8 }
  }
}
```

`gain` (optional, 0–1) scales one sound below the others. Edits are picked up live; `soundboard reload` forces it.

## Dygma / Bazecor

1. Create a new layer, set its toggle key (Layer Lock) and a distinct LED color.
2. For every sound key, assign the same letter/number **with ⌃ ⌥ ⇧ ⌘ all enabled**.
3. Assign Hyper+Esc to any key you like: that is Stop.
4. `soundboard map` prints the table and writes `MAP.md`; the menu bar has a shortcut for it.

## CLI

```
soundboard run | play <key> | stop | reload | quit
soundboard import <file> --key <k> [--name N] [--max s] [--fade s] [--force]
soundboard map | init | install | uninstall | doctor | devices
```

`play` talks to the running daemon, or plays directly if it is not running (handy for testing).

## Menu bar

Speaker volume slider · list of sounds (click to play) · Stop · Disable hotkeys · Open config /
sounds folder · Reload · Bazecor map · Quit.
Icons: `speaker.wave.2` idle, `speaker.wave.3` playing, `speaker.slash` disabled, `exclamationmark.triangle` error.

## Notes

- Headphones must be Bluetooth or USB. With the 3.5 mm jack, macOS may hide the internal speakers device.
- Key codes assume the US/ABC layout (letters and digits are layout-independent).
