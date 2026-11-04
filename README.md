# Utter

Push-to-talk dictation for macOS that runs entirely on your Mac.

Hold a key, say what you want to type, let go — the text appears wherever your cursor is: a browser form, Slack,
Mail, your editor. Speech recognition uses Apple's on-device speech models, so **your voice never leaves the device and
no recording is ever saved**.

## How it works

| Do this | And Utter… |
| --- | --- |
| Hold **Right ⌘** and speak | listens; a small capsule at the top of the screen shows the level and live text |
| Release the key | inserts the text at your cursor |
| Tap the key quickly | switches to hands-free; press the key again to insert |
| Press **Esc** | cancels, nothing is inserted |
| Press another key while holding Right ⌘ | treats it as a normal shortcut (e.g. ⌘C) and cancels |

The trigger key (Right ⌘, Right ⌥ or Fn), the language and clipboard behaviour are in the menu bar menu.

## Privacy

- Audio is captured into memory, streamed to Apple's on-device `SpeechAnalyzer`, and dropped as soon as it has been
  consumed. Nothing is written to disk.
- Utter contains no networking code. The only download is the language model, which macOS fetches once through
  `AssetInventory` the first time you pick a language.
- Transcripts are not stored or logged. Text is inserted by putting it on the clipboard (marked transient so clipboard
  managers ignore it), pasting, and restoring your previous clipboard.
- The app is signed with the hardened runtime and asks only for the microphone entitlement.

You can verify the no-network claim yourself with a firewall such as LuLu or Little Snitch.

## Requirements

- macOS 26 (Tahoe) or later, Apple Silicon recommended
- Xcode 26 / Swift 6.2+ to build

## Build and run

```bash
scripts/build-app.sh
open build/Utter.app
```

On first launch macOS asks for:

1. **Microphone** — to hear you.
2. **Accessibility** — to see the trigger key system-wide and paste into other apps
   (System Settings › Privacy & Security › Accessibility).

macOS ties the Accessibility permission to the app's code signature. The build script signs with the first code-signing
identity in your keychain (set `SIGN_IDENTITY` to choose one), so the permission survives rebuilds. With no identity it
falls back to ad-hoc signing, and you'll need to re-grant Accessibility after each build.

### Testing the speech pipeline without a microphone

```bash
say -o /tmp/hello.aiff "Hello, this is a dictation test."
build/Utter.app/Contents/MacOS/Utter --transcribe /tmp/hello.aiff --locale en-US
```

### Unit tests

```bash
swift test
```

## Languages

Utter uses Apple's newer `SpeechTranscriber` where the language supports it (English, German, French, Spanish, Italian,
Portuguese, Japanese, Korean, Chinese…) and `DictationTranscriber` for the rest (about 55 languages in total, including
Polish, Czech, Dutch, Ukrainian, Swedish and more).

## Known limitations

- Polish (and possibly other `DictationTranscriber` languages) came back without punctuation in tests with synthesized
  speech.
- Pasting uses the ⌘V key position of QWERTY-family layouts; Dvorak and similar layouts are not handled yet.
- Secure input fields (passwords) block global key monitoring, so dictation doesn't trigger there — by design.

## Ideas

- Optional on-device cleanup with Apple's Foundation Models (punctuation, filler words, "make this an email").
- Personal vocabulary for names and jargon.
- Per-app formatting, using the focused app's context.
- Optional WhisperKit / Parakeet engines for languages and accuracy beyond Apple's models.

## Layout

```text
Sources/UtterCore/   pure logic: trigger gesture, transcript assembly, locale choice (unit-tested)
Sources/Utter/       menu bar app: hotkey, audio + speech, indicator, text insertion, settings
Tests/               swift-testing unit tests for UtterCore
Resources/           Info.plist and entitlements for the app bundle
scripts/             build-app.sh
```

## License

MIT
