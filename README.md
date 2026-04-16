# LocalTalk

A minimal macOS menubar app for local, private speech-to-text dictation.

Hold the **fn key**, speak, release — your words appear wherever the cursor is. No cloud, no subscription, no data leaving your machine.

## How it works

- **Hold fn** → microphone starts recording
- **Release fn** → [WhisperKit](https://github.com/argmaxinc/WhisperKit) transcribes the audio on-device
- Transcribed text is typed at your cursor via the clipboard

The Whisper `small.en` model (~150 MB) downloads automatically from Hugging Face on first launch and is cached locally.

## Quick start (pre-built)

1. Download `LocalTalk.dmg` from this repo
2. Open the DMG, drag **LocalTalk** into **Applications**
3. Launch it from Applications
4. Grant **Accessibility** and **Microphone** permissions when prompted
5. The mic icon appears in your menubar — you're ready

> **Note:** The app is ad-hoc signed (not notarized). On first open, right-click → Open → Open to bypass Gatekeeper.

## Build from source

**Requirements:** macOS 14+, Xcode command line tools, Swift 5.9+

```bash
git clone https://github.com/rusackas/localtalk
cd localtalk
make run        # builds, bundles, and launches
```

Or build a distributable DMG:

```bash
make dmg        # produces LocalTalk.dmg
```

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Detect the fn key and type text at the cursor |
| **Microphone** | Record your voice while fn is held |

Both are requested on first launch. If you accidentally deny one, open **System Settings → Privacy & Security** to re-enable.

## Menubar icons

| Icon | State |
|---|---|
| Mic (gray slash) | Loading Whisper model |
| Mic | Ready |
| Mic (red, filled) | Recording |
| Waveform (orange) | Transcribing |
| Warning triangle | Error — check Accessibility/Mic permissions |

## Notes

- Suppresses the fn key so macOS Dictation / Globe menu doesn't appear while the app is running
- Clipboard is saved and restored after each injection
- Works in any app that supports paste (text editors, terminals, browsers, messaging apps, etc.)
