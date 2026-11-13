# Phone Remote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any phone on the same Wi-Fi control Retro TV (keys, text, mouse, volume) by scanning a QR code shown in tv.py.

**Architecture:** `remote_server.py` (stdlib HTTP server, run in a thread by tv.py as the desktop user) serves `remote_page.html` and a token-protected JSON API; commands go to its own evdev UInput keyboard+mouse, volume to `wpctl`. tv.py adds a `PHONE REMOTE` tile/screen showing a QR (python3-qrcode matrix → GdkPixbuf), URL and 6-digit code.

**Tech Stack:** Python 3 stdlib (`http.server`, `secrets`, `ipaddress`, `threading`), python3-evdev (optional at runtime), python3-qrcode, GTK3; vanilla HTML/CSS/JS page.

**Spec:** `docs/superpowers/specs/2026-11-13-phone-remote-design.md`

## Global Constraints
- Branch `feature/phone-remote`, local commits only. **Never push.**
- Never touch `rpi_bridge.py` in the repo OR on the Pi: do not edit or run `setup.sh` (it overwrites /opt/rpi-bridge); nothing touches /opt/rpi-bridge, rpi-bridge.service or power-button.service; nothing new runs as root; no network listener in a root process.
- Port 8080, fallback 8081–8089. Pairing code: 6 random digits, new per server start.
- Wrong-code limit: 5 per client IP per 60 s. Text ≤ 200 chars, ASCII only. Mouse dx/dy clamped to ±200.
- Only private / loopback / link-local client IPs; every `/api/cmd` needs header `X-Remote-Token`.
- Page colour `#7851A9`. No power/shutdown command.
- tv.py must keep working if qrcode/evdev/uinput/port are unavailable.
- `install_tv.sh` embedded tv.py is already out of sync (log 2026-11-04); leave it untouched and say so in the log.
- Log every change in `PROJECT_LOG.md` (newest row on top) in the same commit.

## Review Focus
1. Phone on mobile data / other network → cannot reach the page at all; a non-private source IP that does reach it → 403.
2. tv.py restarted → old phone token rejected (401) and page asks to re-scan.
3. Two phones paired at once → both work.
4. `/dev/uinput` permission denied → server up, `/api/status` reports `"input": false`, volume still works, tv.py does not crash.
5. Malformed JSON / huge body / unknown command → 400, server keeps running.

---

### Task 1: Pairing, security and command validation (pure logic)

**Files:** Create `raspberry_pi/remote_server.py`; Test `tests/test_remote_server.py`

**Interfaces — Produces:**
- `class Pairing(code: str | None = None, clock=time.monotonic)`; attrs `code`; methods `pair(ip: str, code: str) -> str | None` (token, or None; raises `RateLimited` after 5 wrong in 60 s per ip), `valid(token: str) -> bool`, `count() -> int`.
- `is_local_client(ip: str) -> bool`
- `parse_command(data: dict) -> tuple` — returns one of `("key", NAME)`, `("text", str)`, `("move", dx, dy)`, `("click", "left"|"right")`, `("scroll", +1|-1)`, `("volume", "up"|"down"|"mute")`; raises `ValueError` otherwise. Key NAMEs: `UP DOWN LEFT RIGHT ENTER BACK`.
- `text_to_keys(text: str) -> list[tuple[str, bool]]` — (evdev key name e.g. `"KEY_A"`, shift) per char; raises `ValueError` for non-ASCII.

- [ ] Step 1: tests — `test_code_is_six_digits`, `test_pair_right_and_wrong_code`, `test_rate_limit_after_five_wrong_then_recovers` (fake clock +61 s), `test_tokens_unique_and_valid`, `test_local_ip_filter` (192.168.1.5, 10.0.0.2, 127.0.0.1, 169.254.1.1 True; 8.8.8.8, 2001:4860::1 False; "junk" False), `test_parse_command_valid_and_invalid` (incl. `{"cmd":"POWER"}` → ValueError, text 201 chars → ValueError, move clamps 999 → 200), `test_text_to_keys` (`"Ab1!"` → KEY_A/False, KEY_B/True, KEY_1/False, KEY_1/True; `"é"` → ValueError).
- [ ] Step 2: run `python3 -m unittest tests.test_remote_server -v` → fails (module missing).
- [ ] Step 3: implement with `secrets.randbelow`, `secrets.token_urlsafe(24)`, `ipaddress`.
- [ ] Step 4: tests pass.
- [ ] Step 5: commit with PROJECT_LOG row.

### Task 2: Input backend + HTTP server

**Files:** Modify `raspberry_pi/remote_server.py`; Test `tests/test_remote_server.py`

**Interfaces — Consumes:** Task 1. **Produces:**
- `class InputBackend` — `available: bool`; `key(name)`, `type_text(text)`, `move(dx, dy)`, `click(button)`, `scroll(step)`; creates `evdev.UInput` lazily; any ImportError/OSError → `available=False`.
- `set_volume(action) -> bool` — runs `wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+|5%-` or `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`, timeout 2 s.
- `class RemoteServer(input_backend=None, ports=range(8080, 8090), page_path=<dir>/remote_page.html)` — `start() -> bool`, `stop()`, attrs `port`, `pairing`; `url() -> str` (`http://<lan-ip>:<port>/`), `qr_link() -> str` (`url() + "#code=" + code`).
- `lan_ip() -> str` (UDP-connect trick, fallback `127.0.0.1`).
- Routes: `GET /` page; `GET /api/status` → `{"paired": bool, "input": bool}` (token optional); `POST /api/pair` `{code}` → `{"token"}` / 403 / 429; `POST /api/cmd` → 204 / 400 / 401. Non-local client → 403 on everything. Body > 4 KB → 413.

- [ ] Step 1: tests with a `FakeInput` recording calls, server on port 0/ephemeral via `ports=[0]`: `test_full_flow_pair_then_key`, `test_cmd_without_token_401`, `test_restart_invalidates_token`, `test_bad_json_400_server_survives`, `test_input_unavailable_status_false` (backend `available=False`), `test_volume_runs_wpctl` (patch subprocess.run).
- [ ] Step 2: run → fail.
- [ ] Step 3: implement (`ThreadingHTTPServer`, daemon thread, quiet `log_message`).
- [ ] Step 4: tests pass.
- [ ] Step 5: commit with log row.

### Task 3: Phone page

**Files:** Create `raspberry_pi/remote_page.html`

Single file, no external requests. Reads `#code=` → `POST /api/pair`, stores token in `sessionStorage`, clears the hash. D-pad, OK, BACK, VOL−/VOL+/MUTE, text box + SEND, touchpad (pointer drag → `move` batched every 40 ms, tap → left click), LEFT/RIGHT click, SCROLL ▲/▼. 401 → "Re-scan the QR code on the TV". Shows "Keys unavailable on TV" when status `input:false`. Header "RETRO TV · REMOTE", `#7851A9`, large touch targets, `touch-action:none` on the pad.

- [ ] Step 1: test `test_page_served_and_self_contained` — `GET /` 200, contains `api/pair`, no `http://`/`https://` src/href to outside.
- [ ] Step 2–4: fail → write page → pass.
- [ ] Step 5: browser smoke check (Playwright, mobile viewport) against a local server with FakeInput: pair via hash, tap ▲, type "hi", drag pad → FakeInput recorded them. Commit with log row.

### Task 4: tv.py integration + setup

**Files:** Modify `raspberry_pi/tv.py`, `raspberry_pi/README.md`; Create `raspberry_pi/install_remote.sh`, `raspberry_pi/uninstall_remote.sh`

- Test `test_install_scripts_never_touch_bridge`: install/uninstall scripts contain no `rpi-bridge`, `rpi_bridge`, `power-button`, `setup.sh`, `channels.m3u`, `chime.wav`; and `git diff main -- raspberry_pi/rpi_bridge.py raspberry_pi/setup.sh` is empty.

**Consumes:** `RemoteServer`, `.start()`, `.stop()`, `.qr_link()`, `.url()`, `.pairing.code`, `.pairing.count()`, `InputBackend.available`.

- `qr_pixbuf(text: str, size: int = 360) -> GdkPixbuf.Pixbuf | None` (module function; None if `qrcode` missing). Black on white, 4-module quiet zone, nearest-neighbour scale.
- Tile `{"kind": "remote", "name": "PHONE REMOTE"}` before APP STORE; `TILE_ICON["remote"] = "RC"`.
- Screen `"REMOTE"`: brand " PHONE REMOTE ", QR, URL, "CODE 123456", "PAIRED PHONES: n" (1 s GLib timer only while visible), notices for no qrcode / no server / input unavailable, hint " SAME WI-FI ONLY   BACK TO RETURN ". Back → home via existing `_back_step`.
- Server started in `__init__` (failure → `self.remote = None`), stopped in `on_destroy`.
- install_remote.sh (run as desktop user, not sudo; setup.sh untouched): back up `~/tv.py` to `~/tv.py.before-phone-remote` (only if no backup exists); `sudo apt install -y python3-qrcode`; copy `tv.py remote_server.py remote_page.html` to `$HOME`; udev rule `/etc/udev/rules.d/99-retro-tv-uinput.rules`: `KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"`; `sudo usermod -aG input "$USER"`; reload udev. uninstall_remote.sh: restore the backup, remove the two new files and the udev rule (leaves group membership, says so). Neither script references /opt/rpi-bridge.
- README: test/rollback section.

- [ ] Step 1: test `test_tv_registers_remote_tile` is not possible headless here → instead `python3 -m py_compile raspberry_pi/tv.py` and a unit test for `qr_pixbuf`-independent helper `qr_matrix(text) -> list[list[bool]]` (in remote_server.py) checked for square size ≥ 21.
- [ ] Step 2–4: implement, compile, tests pass.
- [ ] Step 5: commit with log row (note install_tv.sh not synced).

### Task 5: Verification and hand-off
- [ ] Full test run `python3 -m unittest discover -s tests -v` (GTK test file may be skipped if gi unavailable — report honestly).
- [ ] Build a test bundle (`git bundle`) + zip of the 4 changed Pi files for the user; Pi test checklist and rollback in the hand-off. No push.
