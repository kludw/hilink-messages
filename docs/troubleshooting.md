---
title: Troubleshooting
nav_order: 4
---

# Troubleshooting

## The app stays on "Connect Your LTE Stick"

1. **Give it a moment.** After plugging in, the stick needs several seconds to start before it answers.
2. **Check Local Network access.** Open System Settings › Privacy & Security › Local Network and make sure HiLink Messages is switched on. Without it the app cannot reach the stick at all. If you rebuilt the app, macOS may have asked again and the prompt may be hidden behind another window.
3. **Check that the Mac sees the stick.** In System Settings › Network the stick appears as an extra network adapter (often named HUAWEI_MOBILE) with an address starting `192.168.`. If it is missing, try another USB port or cable.
4. **Check the stick is in HiLink mode.** Open the stick's own page in a browser: the address is the adapter's address with the last number replaced by `1`, commonly `http://192.168.8.1`. If no page loads, the stick is probably in modem ("stick") mode, which this app does not support.

## "No SIM Card" although a SIM is inserted

The app shows this when the stick reports that its SIM is not ready. Common causes are a SIM locked with a PIN or a badly seated card. The app cannot enter a PIN; unlock the SIM through the stick's own web page or disable the PIN in a phone.

## Messages sometimes fail or the app flickers to the connection screen

The stick only handles one conversation with a client at a time. If its own web page is open in a browser, or another program is talking to it, requests collide. Close the stick's web page and any other tools using it.

## macOS keeps asking for permissions

The app is signed locally. Each rebuild changes its signature, and macOS then treats it as a new app. Allow the prompts again; nothing is lost.

## No names or photos, only numbers

Contacts access was declined or has been reset by a rebuild. Enable HiLink Messages under System Settings › Privacy & Security › Contacts and restart the app.

Numbers are matched on their last nine digits, so `+44 7700 900123` and `07700 900123` are the same contact. Sender names such as "MyBank" never match a contact.

## No notification banners

Check System Settings › Notifications › HiLink Messages. Banners only appear when the app is not the active one; if its window is in front you hear the tone only.

## New messages stopped arriving

Look at the storage count in the sidebar footer. If it shows the stick as full (a red triangle), delete some conversations. The network usually keeps undelivered texts for a while and delivers them once there is room.

## My own number is not shown

Most SIMs do not store it. Click **Add your number** in the sidebar footer and enter it once. See [Getting started]({{ '/getting-started' | relative_url }}).

## The window is gone

Closing the window leaves the app in the menu bar. Click the signal-bar icon and choose **Open Messages**, or open the app again from Finder.
