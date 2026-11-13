---
title: Using the app
nav_order: 3
---

# Using the app

## Reading and sending

- Click a conversation in the sidebar to open it. Opening a conversation marks its messages as read on the stick.
- Type in the field at the bottom and press **Return** to send.
- While you type, a counter shows the characters used and, for longer texts, how many SMS parts the message needs. Plain text fits 160 characters per message; text with emoji or accented letters outside the standard SMS alphabet fits 70.
- Web addresses in messages are clickable links.

### If a message fails

A failed message shows a red **!** next to its bubble and **Not Delivered** beneath it. Click the **!** or **Try Again** to send it again.

## Starting a new conversation

Press **⌘N** or click the compose button at the top of the thread.

- Type a **name** to search your contacts, or a **phone number**. Matching contacts appear with their photo and number; a contact with several numbers gets one row per number.
- Use the arrow keys and **Return**, or click, to pick one. The thread opens with the cursor in the message field.
- A thread you open but never send in disappears when you select another conversation.

## Selecting and deleting

- **⌘-click** adds or removes a conversation from the selection. **⇧-click** selects a range.
- Right-click a conversation and choose **Delete Conversation…**, or press **⌘⌫**. With several selected, they are deleted together after one confirmation.

{: .warning }
Deleting removes the messages from the stick permanently. The app keeps no copy.

## Notifications

When a message arrives the app plays a text tone. If the app is not the active one, it also shows a notification with the sender and the text; clicking it opens that conversation.

If the message contains a verification code (for example "Your code is 284 913"), the notification has a **Copy Code** button that copies just the digits. On macOS the button appears when you hover over the banner.

## The menu bar icon

The icon shows five signal bars filled to the current signal strength.

| Icon | Meaning |
|---|---|
| Some bars filled | Connected; the number of bars is the signal strength. |
| Faint bars with a slash | No stick, no SIM or no signal. |
| A dot in the corner | You have unread messages. |

Its menu shows the carrier and network type, the unread count, and **Open Messages**, **New Message** and **Quit**.

## The sidebar footer

- **Top row:** signal bars, carrier and network type, and the number of messages stored on the stick out of its capacity (for example `42/500`).
- **Bottom row:** your own number, with buttons to copy and edit it.

### Storage warning

The stick can only hold a fixed number of messages (500 on the E3372h-320). Once it is full, new messages cannot arrive.

- Above **80%** an orange warning triangle appears next to the count.
- At **100%** the triangle turns red.

Delete old conversations to free space.

## Settings

Open Settings with **⌘,** or from the menu bar icon.

| Tab | Setting | What it does |
|---|---|---|
| General | Open at login | Starts the app when you log in to the Mac. |
| General | Keep running in the menu bar when the window is closed | On by default. With it off, closing the window quits the app, and messages only arrive while it is open. |
| General | Check for new messages | How often the stick is asked for new messages: every 2, 5, 10 or 30 seconds. |
| Notifications | Play a sound when a message arrives | Turns the text tone on or off. |
| Notifications | Sound | Which tone to play. Picking one plays it. |
| Notifications | Show notifications | Turns the banners on or off. macOS must also allow them. |
| Mobile Data | Mobile data | Switches the SIM's internet connection on or off. Text messages work either way. |
| Mobile Data | Data roaming | Allows mobile data on other networks, for example abroad. |
| Mobile Data | This month (read-only) | Data downloaded, uploaded and the total for the current month, as counted by the stick. |
| Stick | (read-only) | Connection status, signal, messages stored, your number, model, firmware, hardware, IMEI, serial number and how long the stick has been running. |
| Stick | Update firmware automatically | Lets the stick install firmware updates by itself. Shown only if the stick offers the setting. |
| Stick | Restart Stick | Restarts the stick. It takes about a minute and the app reconnects by itself. |
| Stick | Reset Stick | Restores the stick's factory settings after a confirmation. Messages stored on it may be deleted. This cannot be undone. |

{: .note }
The Mobile Data tab, the firmware update switch and the Restart and Reset buttons are new and have not yet been verified against a real stick. If one of them reports an error, the stick's firmware probably answers differently from what the app expects.

## When the app is blocked

The app replaces its whole window with a status screen when it cannot work:

| Screen | Meaning | What to do |
|---|---|---|
| Connect Your LTE Stick | No stick was found. | Plug it in and wait a few seconds. |
| No SIM Card | The stick has no usable SIM. | Insert a SIM, or check that it is not locked with a PIN. |
| No Signal | The stick is not registered on a network. | Move the stick somewhere with better reception. |

The screen clears by itself when the problem is gone. See [Troubleshooting]({{ '/troubleshooting' | relative_url }}) if it does not.
