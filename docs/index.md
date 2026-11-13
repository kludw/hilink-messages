---
title: Home
layout: home
nav_order: 1
---

# HiLink Messages

HiLink Messages is a native macOS app for sending and receiving text messages (SMS) through a Huawei HiLink LTE USB stick. It looks and behaves like Apple's Messages app, and it stays in the menu bar so texts keep arriving when its window is closed.

![The HiLink Messages window showing a conversation list and a message thread]({{ '/assets/screenshot.jpg' | relative_url }})

## What it does

- **Conversations.** Messages stored on the stick are grouped into threads by phone number, with a search field and an unread filter.
- **Sending.** Type and press Return. A counter shows how many SMS parts the text will use. Failed messages can be retried.
- **Receiving.** The app checks the stick every few seconds, plays a tone for new messages and shows a notification when it is in the background.
- **Contacts.** Names and photos come from the Mac's Contacts. New messages can be addressed by typing a contact's name.
- **Verification codes.** Notifications for messages that contain a code get a Copy Code button.
- **Menu bar.** Closing the window leaves the app running as a signal-strength icon in the menu bar.
- **Connection screen.** If the stick is unplugged, has no SIM or has no signal, the app says so instead of showing a stale inbox.
- **Storage.** The stick holds a limited number of messages; the app warns when it is more than 80% full.

## What you need

- A Mac running macOS 26 or later.
- A Huawei LTE stick in HiLink mode with a SIM card. The app is developed and tested with the **E3372h-320**; other HiLink sticks may work but are untested.
- Xcode 26 or later to build the app. There is no downloadable release yet.

Continue with [Getting started]({{ '/getting-started' | relative_url }}).
