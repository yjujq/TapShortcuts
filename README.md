# TapShortcuts

Turn your trackpad into shortcuts: tap with three fingers to open something, tap beside a resting finger to close a window.

**[Download TapShortcuts.zip](https://github.com/yjujq/TapShortcuts/releases/latest/download/TapShortcuts.zip)**

## What it does

- 39 gestures: taps and double taps with 2–5 fingers, holds, a tap beside a resting finger, swipes, pinches, rotation and corner taps.
- Bind any of them to a system action (Mission Control, spaces, screenshots, volume, dark mode…), the previous app, a key combination you record, an app or a Shortcut.
- Stays quiet while you type, ignores your palm, and can be switched off in chosen apps such as games and drawing tools.
- Gestures macOS already uses are marked, so you know which ones may not always fire.
- Lives in the menu bar, with no Dock icon.

## Install

1. Download **TapShortcuts.zip**, unzip it and move **TapShortcuts.app** to Applications.
2. Open it. The app is not notarized, so macOS stops it the first time: open **System Settings → Privacy & Security** and click **Open Anyway**.

## Requirements

macOS 26 and a trackpad. Tested on a MacBook Pro M3 Pro.

## Permissions

- **None** for Shortcuts, apps and switching to the previous app.
- **Accessibility** for key combinations and the system actions that send keys.

## Good to know

Touches are read through Apple's private MultitouchSupport framework. A future macOS may change it — gestures would stop working, but the app will not crash.

## Build from source

```sh
./build.sh --install
```

Swift, AppKit and SwiftUI, no dependencies. Shell commands and scripts can be bound by hand:

```sh
defaults write local.tapshortcuts bindings.v2 -dict-add tap4 "shell:open -a Terminal"
```
