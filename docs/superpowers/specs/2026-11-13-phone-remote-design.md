# Phone Remote for Retro TV — Design

Status: approved by Haidar on 2026-11-13 (option C, with mouse controls added).
Branch: `feature/phone-remote` (local only, not pushed).

## Intent
Anyone in the room can control Retro TV from their phone: scan a QR code shown
on the TV, get a remote in the phone's browser. It must only work on the same
Wi-Fi as the Pi.

## Approaches considered
- **A. appendhub.com page + PeerJS/WebRTC (LAN-only candidates)** — page really
  on appendhub, but needs `aiortc` on the Pi and depends on the public PeerJS
  server. Most code.
- **B. appendhub.com page + LiveKit relay, same-public-IP check** — works through
  any router, but commands go via the cloud and "same network" is approximate.
- **C. Page served by the Pi itself (chosen)** — simplest and most reliable; the
  phone must reach the Pi's LAN address, so "same network" is enforced
  naturally. Trade-off: the page lives on the Pi, not on appendhub.com.
  (An https appendhub.com page cannot call the Pi's plain-http LAN address —
  browsers block mixed content — which is why A/B needed extra machinery.)

## Goals
- `PHONE REMOTE` tile on the Home screen → screen with QR code, URL and a
  6-digit pairing code.
- Phone page (Append Hub purple `#7851A9`): D-pad, OK, Back, volume −/+, mute,
  text box that types on the TV, touchpad (drag = move, tap = left click),
  left/right click and scroll buttons.
- Works for tv.py screens, web apps and the video player (system-level input).

## Non-goals (v1)
- Power/shutdown from the phone (a misclick must not turn the TV off).
- Arabic labels or non-ASCII typing (uinput typing is US-layout ASCII).
- Hosting anything on appendhub.com; no change to the Append-Hub repo.

## Anti-goals
- No root process listening on the network.
- No change to `rpi_bridge.py` (the Pi's copy has unsynced local edits).
- Must not break tv.py if the remote can't start (missing package, port busy,
  no /dev/uinput access) — show a clear message instead.

## Design
- `raspberry_pi/remote_server.py` — stdlib `ThreadingHTTPServer`, started by
  tv.py in a daemon thread on port 8080 (tries 8080–8089). Runs as the
  desktop user.
  - `GET /` serves `remote_page.html` (same folder).
  - `POST /api/pair {code}` → session token; `POST /api/cmd` with header
    `X-Remote-Token`. Unknown commands rejected.
  - Security: pairing code is random per tv.py start; ≤5 wrong codes per IP per
    minute; only private/loopback/link-local client IPs accepted; token required
    for every command (custom header ⇒ cross-site pages can't forge requests);
    text ≤200 chars; mouse deltas clamped.
  - Input: its own `evdev.UInput` keyboard+mouse device (same keys as the
    bridge's KEY_MAP). Volume/mute via `wpctl` on the user's own session.
  - If evdev/uinput is unavailable: server still runs, volume still works,
    page shows "keys unavailable on TV".
- QR code: `python3-qrcode` matrix drawn into a `GdkPixbuf` (no PIL needed).
  QR encodes `http://<pi-lan-ip>:<port>/#code=<code>`; the fragment never leaves
  the phone in request logs; the page pairs automatically from it.
- tv.py: new tile kind `remote`, new `REMOTE` screen (QR, URL, code, paired
  device count, "SAME WI-FI ONLY · BACK TO RETURN"); server stopped on exit.
- setup.sh: install `python3-qrcode`, copy the two new files to `$HOME`, add a
  udev rule giving the `input` group access to `/dev/uinput`, add the user to
  `input` (takes effect after re-login).

## Testing
- Offline unit tests (`tests/test_remote_server.py`): pairing, wrong-code rate
  limit, private-IP filter, token check, command validation, text→key mapping,
  using a fake input device — no GTK, no hardware.
- Manual on the Pi: scan QR, pair, navigate Home/Live/Web, type into Wi-Fi
  password, move mouse in a web app, volume, second phone, phone on mobile data
  (must fail).

## Left to the builder
Exact layout/styling of the REMOTE screen and phone page within the retro and
Append Hub styles; mouse acceleration curve; port-retry details.
