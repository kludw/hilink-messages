---
title: Development
nav_order: 6
---

# Development

## Layout

The app is a Swift package with a single executable target, written in SwiftUI with the Swift 6 language mode.

| Path | What it holds |
|---|---|
| `Package.swift` | Package definition. Targets macOS 26. |
| `Sources/HiLinkMessages/App.swift` | App entry point, window, menu bar item, colours. |
| `Sources/HiLinkMessages/MessageStore.swift` | App state: polling, conversations, sending, selection. |
| `Sources/HiLinkMessages/ModemClient.swift` | The stick's HTTP API and a small XML reader. |
| `Sources/HiLinkMessages/SidebarView.swift` | Conversation list, search, footer, number editor. |
| `Sources/HiLinkMessages/ChatView.swift` | Thread, bubbles, message field, New Message. |
| `Sources/HiLinkMessages/ConnectionView.swift` | The blocking not-connected screens. |
| `Sources/HiLinkMessages/ContactsDirectory.swift` | Names and photos from Contacts. |
| `Sources/HiLinkMessages/Notifier.swift` | Tone and notifications. |
| `Sources/HiLinkMessages/MessageText.swift` | Link and verification-code detection. |
| `Sources/HiLinkMessages/Countries.swift` | Dialling codes and number validation. |
| `Sources/HiLinkMessages/MenuBarIcon.swift` | Drawing of the menu bar signal bars. |
| `scripts/bundle.sh` | Builds and wraps the binary into a `.app`. |
| `Resources/AppIcon.icns`, `design/AppIcon.svg` | App icon and its source. |
| `docs/` | This documentation site. |

## Building

```bash
scripts/bundle.sh --open
```

The script runs `swift build -c release`, creates `build/HiLink Messages.app` with its `Info.plist` and icon, and signs it ad hoc. There is no Xcode project; open the folder in Xcode to edit the package if you prefer.

A plain `swift run` also works for quick checks, but macOS features that need a real app bundle (notifications, permission prompts, plain HTTP to the stick) are only reliable in the bundled app.

## Launch flags

These are for development and testing. Pass them after `--args`, and quit the running app first, because flags are only read at launch.

```bash
open "build/HiLink Messages.app" --args --sample-data
```

| Flag | Effect |
|---|---|
| `--sample-data` | Does not touch the stick. Shows made-up conversations; sending is simulated. |
| `--no-modem` | Behaves as if no stick is connected. |
| `--no-sim` | Behaves as if the stick has no SIM. |
| `--no-signal` | Behaves as if the stick has no signal. |
| `--fail-sends` | Every send fails, to see the failed state and retry. |
| `--storage-nearly-full` | Shows storage as 90% full, to see the warning. |

## Testing against a real stick

There is no automated test suite. When testing by hand, remember that sending is real: every test message is an SMS billed to the SIM. Prefer `--sample-data` for interface work.

## Documentation site

The site is built by GitHub Pages from the `docs/` folder using Jekyll and the Just the Docs theme. Editing a Markdown file there and pushing to `master` updates the site.
