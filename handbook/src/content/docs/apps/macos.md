---
title: Mac app (experimental)
description: Mac Catalyst build of the iOS shell. Camera Wi-Fi or a shared local network; physical validation pending.
---

**Experimental. Not yet validated with a camera on a Mac.**

The Mac app is the iOS shell built with Mac Catalyst from the same
`ios/OpenPocketCine/` sources and the same XcodeGen project. The Swift core,
CoreBluetooth pairing, the UDP datalink and the hardware decoder are unchanged.
It needs a Mac running macOS 14 or later with Bluetooth and Wi-Fi.

```sh
just mac-build
open .local/dd-mac/Build/Products/Debug-maccatalyst/OpenPocketCine.app
```

For a signed build, open `ios/OpenPocketCine.xcodeproj`, choose the
**OpenPocketCine** scheme and **My Mac (Mac Catalyst)**, then run.

## Joining Wi-Fi

macOS has no `NEHotspotConfiguration`. The Mac app embeds a small AppKit bundle,
`OpenPocketCineMacBridge`, that uses CoreWLAN to read the current network, scan
for a network by name and join it. The camera Wi-Fi password is read over
Bluetooth, so no password entry is needed. Allow **Location Services** when
asked: macOS names Wi-Fi networks to an app only with that permission. Without
it, the bridge joins the camera's access point by name through `networksetup`,
but the app cannot confirm the current network name or leave the camera network
for you. That fallback passes the camera password on the `networksetup` command
line while it runs. It is never used for your own network: without Location,
join that network from the Wi-Fi menu first.
A Mac `bridge` interface (Internet Sharing, virtual machines) is not treated
as an iPhone Personal Hotspot.

Both connection paths are available:

- **Camera Wi-Fi.** The Mac joins the camera's own access point with the
  credentials read over Bluetooth, exactly as on iPhone. While it is joined,
  the Mac has no internet over Wi-Fi unless Ethernet is also connected. You
  can also join the camera network yourself from the Wi-Fi menu; the app then
  continues without joining again.
- **Shared Wi-Fi (station mode).** In **Add setup → Wi-Fi** or Multiview, the
  camera joins your router and the Mac stays on its own network. A Mac on
  Ethernet in the same LAN needs no Wi-Fi join. See the
  [Multiview guide](../../guides/multiview-prototype/) for the station path and
  its limits, including WPA2 and client isolation.

The Mac Wi-Fi interface is not always `en0`. Station-mode addressing prefers the
Wi-Fi interface reported by CoreWLAN, then a connected wired `en` interface. A
self-assigned `169.254` address is not used.

## Not available on Mac

- Apple Watch remote: there is no paired watch on a Mac.
- Personal Hotspot setup: the Hotspot choice is hidden; use Wi-Fi.
- Networks this app configured: the network list shows the current network and
  camera scan results only. macOS keeps known networks in System Settings.
- AirPods head tracking, orientation lock and haptics follow what Mac Catalyst
  provides and are not validated.

The app is not sandboxed, so it is not yet suitable for the Mac App Store.
