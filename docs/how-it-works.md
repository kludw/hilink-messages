---
title: How it works
nav_order: 5
---

# How it works

## The stick is a small web server

A Huawei stick in HiLink mode presents itself to the computer as a USB network adapter. The stick sits at the gateway address of that network (for example `192.168.8.1` or `192.168.3.1`, depending on firmware) and serves an HTTP API that its own web page uses. HiLink Messages talks to the same API. No driver or serial connection is involved.

Huawei does not publish this API. What follows is what the app relies on, as observed on an E3372h-320 with firmware 10.0.3.1.

## Finding the stick

The app looks at every network interface on the Mac with a `192.168.x.y` address, and asks the `.1` address of each for `/api/device/basic_information`. A stick answers with `<classify>hilink</classify>`.

While connected, the app checks twice a second that the interface is still there. An unplugged stick is noticed within about a second this way, without waiting for a request to time out.

## Session tokens

Every request needs a session cookie and a verification token from `/api/webserver/SesTokInfo`. The stick invalidates a token as soon as it issues another one, so a token and the request that uses it must not overlap with any other pair. The app therefore sends all requests through a single queue, one at a time, and retries once if the stick rejects a token.

On this firmware no login is needed.

## Endpoints used

| Purpose | Endpoint |
|---|---|
| Signal, network type, SIM and service state | `GET /api/monitoring/status` |
| Carrier name | `GET /api/net/current-plmn` |
| SIM identifiers and own number, if stored | `GET /api/device/information` |
| Message counts and capacity | `GET /api/sms/sms-count` |
| List received and sent messages | `POST /api/sms/sms-list` |
| Send a message | `POST /api/sms/send-sms`, then `GET /api/sms/send-status` |
| Mark as read | `POST /api/sms/set-read` |
| Delete | `POST /api/sms/delete-sms` |

Requests and responses are small XML documents.

## Keeping up to date

Every five seconds the app reads the status and the message counts. It reloads the message lists only when the counts change. Sending waits for the stick to report success or failure, then reloads the outbox.

## Where your data lives

- **Messages** are stored on the stick, and only there. The app reads them each time and keeps no database or cache on the Mac. Deleting in the app deletes from the stick.
- **Your own number**, if you enter it, is saved in the app's preferences on the Mac (`~/Library/Preferences/local.hilink-messages.plist`), keyed by the SIM's serial number.
- **Contacts** are read from the Mac's Contacts to show names and photos. They are not copied or sent anywhere.
- **Nothing leaves your Mac** except the SMS messages you send, which go through the stick to your mobile network. The app makes no other network connections.

## Verification codes

A message counts as containing a code when it mentions a word such as code, PIN, OTP, password or verification (in a few languages) and contains 4 to 8 digits, or two groups of three. The first such number is offered by the Copy Code button. Codes made of letters are not detected.
