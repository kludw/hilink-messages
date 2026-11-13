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
| `Sources/HiLinkMessages/openapi.yaml` | OpenAPI 3.1 description of the stick's API. Also linked from the repository root. |
| `Sources/HiLinkMessages/ModemClient.swift` | The calls to the stick, using the types generated from `openapi.yaml`. |
| `Sources/HiLinkMessages/XMLCoding.swift` | Reads and writes the stick's XML with those generated types. |
| `Sources/HiLinkMessages/SettingsView.swift`, `Preferences.swift` | The Settings window and the stored settings. |
| `Tests/HiLinkMessagesTests/` | Tests for the XML coding and the app's text and number logic. |
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

## The API description and generated types

`Sources/HiLinkMessages/openapi.yaml` describes the part of the stick's API the app uses. [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) runs as a build plugin and turns its schemas into Swift types (`Components.Schemas.…`) on every build; the generated code is not checked in.

Only the types are generated. The stick speaks XML and needs a fresh session token before every call, so the requests themselves are made by `ModemClient`, and `XMLCoding` converts between XML and the generated types.

To support another call, add it and its schemas to `openapi.yaml`, build, and use the new type in `ModemClient`.

The first build downloads the generator and its dependencies and takes a minute or two.

## Tests

```bash
swift test
```

The tests decode real responses from an E3372h-320 (with identifiers replaced), check that requests are encoded exactly as the stick expects, and cover the SMS counter, verification-code detection and phone-number handling. They do not need a stick.

## Checks still owed

Some stick code was written without a stick connected and has not run against a real device:

- The calls marked `x-verified: false` in `openapi.yaml`: the mobile data switch, connection (roaming) settings, traffic and month statistics, the data plan, clearing statistics, and restarting the device.
- The switch of `ModemClient` to generated types, which is covered by tests using recorded responses but has not been exercised on a stick since.

To verify: read each unverified call from a real stick and compare the answer with its schema, then try each action that changes something (mobile data, roaming, reset statistics, restart). When a call is confirmed, remove its `x-verified: false` mark and replace the assumed XML in the tests with a real response.

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

The automated tests never talk to a stick. When testing by hand, remember that sending is real: every test message is an SMS billed to the SIM. Prefer `--sample-data` for interface work.

## Documentation site

The site is built by GitHub Pages from the `docs/` folder using Jekyll and the Just the Docs theme. Editing a Markdown file there and pushing to `master` updates the site.
