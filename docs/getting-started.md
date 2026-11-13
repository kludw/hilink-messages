---
title: Getting started
nav_order: 2
---

# Getting started

## 1. Build the app

There is no packaged download yet, so the app is built from source. You need Xcode 26 or later installed and selected as the active developer directory.

```bash
git clone https://github.com/kludw/hilink-messages.git
cd hilink-messages
scripts/bundle.sh --open
```

The script compiles a release build, wraps it in `build/HiLink Messages.app` and opens it. Run it again after pulling changes. To keep the app around, drag `build/HiLink Messages.app` into your Applications folder.

## 2. Plug in the stick

Insert the SIM card into the stick and plug the stick into the Mac. macOS shows it as a new network adapter; no driver is needed.

The app starts on a **Connect Your LTE Stick** screen and switches to your messages within a few seconds of finding the stick.

## 3. Allow the permissions

On first launch macOS asks three things. The app asks for all of them up front.

| Permission | Why the app asks | If you decline |
|---|---|---|
| Local Network | The stick is reached over its own local network address. | The app cannot find the stick and stays on the connection screen. |
| Notifications | To show a banner for messages that arrive while the app is in the background. | Messages still arrive and the tone still plays; there is no banner. |
| Contacts | To show names and photos instead of bare numbers, and to address new messages by name. | Threads show phone numbers only. |

{: .note }
The app is signed locally, not with an Apple developer certificate. After each rebuild macOS may treat it as a new app and ask for these permissions again.

## 4. Add your number (optional)

Many SIM cards do not store their own phone number, so the stick cannot report it. To see your number in the sidebar footer, click **Add your number**, pick the country and type the number. It is saved on this Mac for that SIM only. Use the pencil button to change or remove it.

## Quitting

Closing the window (⌘W) keeps the app running in the menu bar, and removes it from the Dock. To quit completely, press ⌘Q or choose **Quit** from the menu bar icon.
