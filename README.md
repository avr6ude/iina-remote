# IINA Remote

Control [IINA](https://iina.io) from your iPhone or any browser on the same network:
play, pause, seek, volume, speed, subtitle and audio tracks, delays.

<p>
  <img src="screenshots/app.png" width="200" alt="Remote">
  <img src="screenshots/app-dark.png" width="200" alt="Remote in dark mode">
  <img src="screenshots/picker.png" width="200" alt="Choosing between IINA windows">
  <img src="screenshots/web.png" width="200" alt="Browser remote">
</p>

## Install

**1. IINA plugin (required).** In IINA → Settings → Plugins, install from GitHub with
`https://github.com/avr6ude/iina-remote` (IINA then offers updates), or download the `.iinaplgz` from
[Releases](../../releases) and double-click it. Enable **Remote**.

**2. iPhone app.**

<a href="https://apps.apple.com/app/id6825027883"><img src="https://tools.applemarketingtools.com/api/badges/download-on-the-app-store/black/en-us" height="40" alt="Download on the App Store"></a>

Open a video in IINA and launch the app. It finds every IINA window on your network by itself.

**No app?** In IINA choose **Plugin → Show Remote QR Code** and scan the code with any phone.

<img src="screenshots/iina.png" width="600" alt="QR code in IINA's sidebar">

## Development

```sh
ln -s "$PWD" ~/Library/Application\ Support/com.colliderli.iina/plugins/com.avrdude.iina-remote.iinaplugin-dev
open ios/IINARemote.xcodeproj
```

Each IINA window serves a WebSocket on port 8766 and up, advertised over Bonjour as
`_iina-remote._tcp`; the browser remote is served on port 8765. There is no authentication:
anyone on your network can control playback.
