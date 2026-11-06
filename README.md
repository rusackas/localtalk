# LocalTalk

A minimal macOS menubar app for local, private speech-to-text dictation.

Hold a key, speak, release — your words appear wherever the cursor is. No cloud, no subscription, no data leaving your machine.

## How it works

- **Hold trigger key** → microphone starts recording (in memory, no files written to disk)
- **Release** → [WhisperKit](https://github.com/argmaxinc/WhisperKit) transcribes on-device
- The transcript is inserted at your cursor, by pasting (default), simulated typing, or live as you speak (see [Output modes](#output-modes))

The Whisper model (Small by default; English-only variant when the language is English) downloads automatically on first launch and is cached locally. The mic icon appears once it's loaded; the trigger key does nothing until then.

## Quick start (pre-built)

1. Download `LocalTalk.dmg` from the [releases page](../../releases)
2. Open the DMG, drag **LocalTalk** into **Applications**
3. Launch it from Applications
4. Grant **Accessibility** and **Microphone** permissions when prompted
5. The mic icon appears in your menubar — you're ready

The app is signed with a Developer ID and notarized by Apple, so it should open without Gatekeeper warnings. Updates install automatically through Sparkle (verified with an EdDSA signature) — when a new version is available, you'll see a prompt with a "Install and Relaunch" button.

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

## Settings

Click the menubar icon → **Settings…** (or press ⌘,) to:

- **Change trigger key** — default is fn/Globe; also supports Right Option (⌥) or Right Control (⌃)
- **Launch at login**, and an optional **sound** on start/stop
- **Model** (Tiny, Base, Small, Medium) and **language** (or auto-detect). Switching downloads the new model on first use.
- **Output mode** (see below), plus optional **capitalize first letter** and **add trailing period**
- **View usage stats** — total time recorded and characters typed
- **Reset stats** — clears the counters

### Output modes

| Mode | What it does |
|---|---|
| **Paste** (default) | Inserts the whole transcript at once via the clipboard after you release the key. Your previous clipboard contents (including images and files) are restored afterwards. Fast and works almost everywhere. |
| **Simulated typing** | Same timing as Paste, but inserts the transcript as keystrokes. Slower; useful in the few fields that block paste. |
| **Live (types as you speak)** | Types each phrase while you're still holding the key, as soon as Whisper is confident in it; the rest lands when you release. Text trails your voice by about a phrase and is never revised once typed. Uses more CPU, so it works best with the Tiny or Base model. |

## Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Detect the trigger key and type text at the cursor |
| **Microphone** | Record your voice while the trigger key is held |

Both are requested on first launch. If microphone access is denied or no microphone is connected, LocalTalk shows an alert with a shortcut to the right System Settings pane, and the warning icon clears on its own once it's fixed.

## Menubar icons

| Icon | State |
|---|---|
| Spinner | Loading / downloading Whisper model |
| Mic | Ready |
| Mic (red, filled) | Recording |
| Waveform (orange) | Transcribing |
| Warning triangle | Needs attention: Accessibility permission, microphone access, no microphone, or the model failed to load (click the icon for details) |

## Notes

- Suppresses the trigger key so macOS Dictation / Globe menu doesn't interfere
- Audio is captured in memory — no temporary files are written to disk
- In Paste mode the clipboard is saved and restored after each insertion
- Works in any app that accepts paste or typing (text editors, terminals, browsers, messaging apps, etc.)
