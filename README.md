<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="Utter app icon">

# Utter

**Hold a key. Say it. It's typed.**

Private, push-to-talk dictation for the Mac menu bar. Speech is recognised entirely on your Mac.
Nothing is recorded, stored or sent anywhere.

[![CI](https://github.com/natgurlain/utter/actions/workflows/ci.yml/badge.svg)](https://github.com/natgurlain/utter/actions/workflows/ci.yml)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-111111?logo=apple&logoColor=white)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![100% on-device](https://img.shields.io/badge/speech-100%25%20on--device-2EA44F)
![No network](https://img.shields.io/badge/network-none-2EA44F)
![Languages](https://img.shields.io/badge/languages-55-7B61FF)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

---

## Why Utter

- **Works everywhere you type.** Browser forms, Slack, Mail, Notes, your code editor. The text lands at your cursor.
- **Private by design.** Apple's on-device speech models do the recognition. Audio lives in memory for as long as you
  speak, then it's gone. Utter has no networking code at all.
- **Out of your way.** A menu bar icon and a small capsule that appears while you talk. No windows, no Dock icon.
- **Speaks your language.** About 55 languages, including English, Polish, German, French, Spanish, Ukrainian and
  Japanese.

## How it works

| You | Utter |
| --- | --- |
| Hold **Right ⌘** and speak | Listens and shows live text in a capsule at the top of the screen |
| Let go | Types what you said where your cursor is |
| Tap **Right ⌘** quickly | Switches to hands-free; press the key again to insert |
| Press **Esc** | Cancels; nothing is typed |
| Press another key while holding Right ⌘ | Treats it as a normal shortcut (⌘C, ⌘V…) and stays out of the way |

The trigger key (Right ⌘, Right ⌥ or Fn/Globe), language, clipboard behaviour and launch at login are all in the menu
bar menu.

## Install

Requires **macOS 26 Tahoe** or later and **Xcode 26** (Swift 6.2) to build.

```bash
git clone https://github.com/natgurlain/utter.git
cd utter
scripts/install.sh
```

`install.sh` builds a release copy, installs it to `~/Applications/Utter.app` and launches it. Utter then turns on
**Launch at Login** for itself (you can switch it off in the menu).

On first launch macOS asks for two permissions:

| Permission | Why |
| --- | --- |
| **Microphone** | To hear you while the key is held |
| **Accessibility** | To notice the trigger key in any app and to type the text there |

Grant Accessibility in **System Settings › Privacy & Security › Accessibility**. Utter notices within a couple of
seconds; if it doesn't, choose **Already Granted? Relaunch Utter** from the menu.

The first time you use a language, macOS downloads its speech model once (about a minute).

## Privacy

| | |
| --- | --- |
| 🎙️ **Audio** | Captured into memory, streamed to Apple's on-device `SpeechAnalyzer`, released as soon as it's processed. Never written to disk. |
| 📝 **Transcripts** | Typed into the app you're using, then forgotten. No history, no logs. |
| 🌐 **Network** | None. Language models are installed by macOS itself through `AssetInventory`. |
| 📋 **Clipboard** | Text is pasted through the clipboard, marked *transient* so clipboard managers ignore it, and your previous clipboard is restored. |
| 🔒 **Entitlements** | Hardened runtime with microphone input only. |

Don't take our word for it: watch Utter with a firewall such as [LuLu](https://objective-see.org/products/lulu.html)
or Little Snitch. It makes no connections.

## Troubleshooting

<details>
<summary><b>Holding the key does nothing</b></summary>

1. Check the menu bar menu. If it says *Needs Accessibility permission*, grant it in System Settings › Privacy &
   Security › Accessibility.
2. Make sure you're running the installed copy (`~/Applications/Utter.app`). macOS ties permissions to the app's
   location and signature, so a copy in another folder, or one whose folder was moved or renamed, may silently lose
   them.
3. Still stuck? Reset Utter's permission record only, then reinstall:

   ```bash
   tccutil reset Accessibility com.natgurlain.utter
   scripts/install.sh
   ```

</details>

<details>
<summary><b>I have to re-grant Accessibility after every build</b></summary>

macOS remembers the permission by code signature. `scripts/build-app.sh` signs with the first code-signing identity in
your keychain (choose one with `SIGN_IDENTITY="…"`). If there is none it signs ad-hoc, and every build looks like a new
app. Create a self-signed code-signing certificate in Keychain Access (Certificate Assistant › Create a Certificate…,
type *Code Signing*) and rebuild.

</details>

<details>
<summary><b>The text appears in the wrong place or not at all</b></summary>

Utter pastes with ⌘V into the focused app. Some apps block synthetic paste in secure fields (passwords), which is
intended. Keyboard layouts that move the V key (e.g. Dvorak) aren't supported yet.

</details>

<details>
<summary><b>Polish text has no punctuation</b></summary>

Languages served by Apple's `DictationTranscriber` (Polish among them) may return little or no punctuation. On-device
cleanup with Apple's Foundation Models is on the roadmap.

</details>

## Development

```bash
swift test                    # unit tests (trigger gesture, transcript assembly, language choice)
scripts/build-app.sh debug    # build build/Utter.app without installing
scripts/install.sh            # build, install to ~/Applications and launch
scripts/make-icon.sh          # regenerate the app icon
```

Test the speech pipeline without a microphone:

```bash
say -o /tmp/hello.aiff "Hello, this is a dictation test."
build/Utter.app/Contents/MacOS/Utter --transcribe /tmp/hello.aiff --locale en-US
```

### Project layout

```text
Sources/UtterCore/   pure logic: trigger gesture, transcript assembly, language choice (unit-tested)
Sources/Utter/       the app: hotkey, audio + speech, indicator, text insertion, settings, login item
Tests/               swift-testing unit tests
Resources/           Info.plist, entitlements, app icon
scripts/             build, install and icon scripts
```

### How it fits together

```text
Right ⌘ held ──▶ HotkeyMonitor ──▶ TriggerGesture ──▶ DictationController
                                                         │
              AVAudioEngine (memory) ──▶ SpeechAnalyzer ─┤──▶ live text in the capsule
                                                         │
                                       on release ──▶ TextInserter ──▶ ⌘V into the focused app
```

## Roadmap

- [x] Push-to-talk and hands-free dictation
- [x] About 55 languages, fully on-device
- [x] Launch at login
- [ ] On-device cleanup with Apple Foundation Models: punctuation, filler words, "make this an email"
- [ ] Personal vocabulary for names and jargon
- [ ] Per-app formatting
- [ ] Optional WhisperKit / Parakeet engines
- [ ] Signed and notarized release download

## License

[MIT](LICENSE) © Nat Gurlain
