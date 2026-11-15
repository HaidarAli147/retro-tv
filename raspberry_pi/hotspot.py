#!/usr/bin/env python3
"""Wi-Fi hotspot backup for the phone remote.

When the TV has no network (no Wi-Fi, no cable), tv.py can switch the Pi's
Wi-Fi into a small access point, "RetroTV-XXXX". A phone joins it by scanning
a QR code and then opens the usual phone-remote page. Needs NetworkManager
(nmcli), which Raspberry Pi OS and Debian desktops already use. No root: the
logged-in desktop user may create and start Wi-Fi connections.

The Pi has ONE Wi-Fi radio: while the hotspot is on, the TV is not connected to
a Wi-Fi network (a network cable keeps working). Use it for control and setup.

Everything here is plain Python with no GTK, so it can be tested offline: the
only thing that touches the system is _nmcli().
"""
import json
import os
import re
import secrets
import subprocess

CONNECTION = "RetroTV-Hotspot"        # name of the NetworkManager profile
CREDS_PATH = os.path.expanduser("~/.config/retro-tv/hotspot.json")
GRACE_SECONDS = 30.0                  # no network this long -> start (auto mode)
RETRY_SECONDS = 120.0                 # wait this long after a failed start
MODES = ("auto", "on", "off")
MODE_LABELS = {"auto": "AUTO (NO NETWORK)", "on": "ALWAYS ON", "off": "OFF"}
# No 0/O/1/I/L: the password may be read off the screen and typed by hand.
PASSWORD_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
PASSWORD_LENGTH = 10


def clean_mode(value):
    return value if value in MODES else "auto"


# ----------------------------------------------------------------- nmcli
def _nmcli(args, timeout=20):
    """Runs nmcli. Returns (returncode, stdout, stderr); 127 if nmcli is missing."""
    try:
        done = subprocess.run(["nmcli"] + list(args), capture_output=True, text=True,
                              timeout=timeout, env=dict(os.environ, LC_ALL="C"))
        return done.returncode, done.stdout, done.stderr
    except FileNotFoundError:
        return 127, "", "nmcli is not installed"
    except (OSError, subprocess.SubprocessError) as exc:
        return 1, "", str(exc)


def split_terse(line):
    """One line of `nmcli -t` output -> fields ('\\:' is a colon inside a value)."""
    fields, cur, i = [], [], 0
    while i < len(line):
        ch = line[i]
        if ch == "\\" and i + 1 < len(line):
            cur.append(line[i + 1])
            i += 2
            continue
        if ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    fields.append("".join(cur))
    return fields


def devices():
    """[{"device", "type", "state", "connection"}, ...] from NetworkManager."""
    rc, out, _ = _nmcli(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"])
    if rc:
        return []
    rows = []
    for line in out.splitlines():
        f = split_terse(line)
        if len(f) >= 4:
            rows.append({"device": f[0], "type": f[1], "state": f[2], "connection": f[3]})
    return rows


def wifi_device(rows=None):
    """The first Wi-Fi adapter: {"device", "state"} or None."""
    for r in (devices() if rows is None else rows):
        if r["type"] == "wifi":
            return {"device": r["device"], "state": r["state"]}
    return None


def has_network(rows=None):
    """True if a Wi-Fi network or a cable is connected (our own hotspot does not count)."""
    for r in (devices() if rows is None else rows):
        if r["type"] in ("wifi", "ethernet") and r["state"].startswith("connected") \
                and r["connection"] != CONNECTION:
            return True
    return False


def is_active(rows=None):
    """True while our hotspot is up."""
    return any(r["connection"] == CONNECTION and r["state"].startswith("connected")
               for r in (devices() if rows is None else rows))


def supports_ap(device):
    """True / False if the adapter says it can host a hotspot, None if unknown."""
    rc, out, _ = _nmcli(["-t", "-g", "WIFI-PROPERTIES.AP", "device", "show", device])
    if rc:
        return None
    answer = out.strip().lower()
    return True if answer == "yes" else False if answer == "no" else None


def address(device):
    """The TV's own address while the hotspot is up (normally 10.42.0.1)."""
    rc, out, _ = _nmcli(["-g", "IP4.ADDRESS", "device", "show", device])
    if rc:
        return None
    m = re.search(r"(\d{1,3}(?:\.\d{1,3}){3})/\d+", out)
    return m.group(1) if m else None


# ----------------------------------------------------------- credentials
def new_credentials(rng=secrets):
    ssid = "RetroTV-" + "".join(rng.choice(PASSWORD_ALPHABET) for _ in range(4))
    password = "".join(rng.choice(PASSWORD_ALPHABET) for _ in range(PASSWORD_LENGTH))
    return {"ssid": ssid, "password": password}


def load_credentials(path=CREDS_PATH, rng=secrets):
    """Name and password of the hotspot. Created once and kept, so a phone that
    joined before can reconnect without scanning again."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if (isinstance(data, dict) and re.fullmatch(r"RetroTV-[A-Z0-9]{4}", str(data.get("ssid", "")))
                and re.fullmatch(r"[A-Z0-9]{8,32}", str(data.get("password", "")))):
            return {"ssid": data["ssid"], "password": data["password"]}
    except (OSError, ValueError):
        pass
    creds = new_credentials(rng)
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(creds, fh)
    except OSError:
        pass                         # still works, just not remembered
    return creds


def _wifi_escape(text):
    return re.sub(r'([\\;,:"])', r"\\\1", text)


def wifi_qr_text(ssid, password):
    """What a phone camera reads to join the network in one tap."""
    return "WIFI:T:WPA;S:%s;P:%s;;" % (_wifi_escape(ssid), _wifi_escape(password))


# ------------------------------------------------------------ start / stop
def start(creds):
    """Switches the Wi-Fi adapter into hotspot mode. Returns (ok, message)."""
    rows = devices()
    adapter = wifi_device(rows)
    if adapter is None:
        return False, "NO WI-FI ADAPTER FOUND"
    device = adapter["device"]
    if adapter["state"] in ("unavailable", "unmanaged"):
        return False, ("WI-FI IS %s: SET THE WI-FI COUNTRY (sudo raspi-config) OR SWITCH WI-FI ON"
                       % adapter["state"].upper())
    if supports_ap(device) is False:
        return False, "THIS WI-FI ADAPTER CANNOT MAKE A HOTSPOT"
    _nmcli(["connection", "delete", CONNECTION])          # a stale profile, if any
    rc, _, err = _nmcli([
        "connection", "add", "type", "wifi", "ifname", device, "con-name", CONNECTION,
        "autoconnect", "no", "ssid", creds["ssid"],
        "802-11-wireless.mode", "ap", "802-11-wireless.band", "bg",
        "ipv4.method", "shared", "ipv6.method", "ignore",
        "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.proto", "rsn",
        "wifi-sec.pairwise", "ccmp", "wifi-sec.group", "ccmp",
        "wifi-sec.psk", creds["password"]])
    if rc:
        return False, "HOTSPOT SETUP FAILED: " + (err.strip().splitlines() or ["?"])[0][:90]
    rc, _, err = _nmcli(["connection", "up", CONNECTION], timeout=45)
    if rc:
        _nmcli(["connection", "delete", CONNECTION])
        return False, "HOTSPOT DID NOT START: " + (err.strip().splitlines() or ["?"])[0][:90]
    return True, creds["ssid"]


def stop():
    """Switches the hotspot off and forgets its profile. True if nothing is left."""
    if not is_active() and not _profile_exists():
        return True
    _nmcli(["connection", "down", CONNECTION], timeout=30)
    _nmcli(["connection", "delete", CONNECTION])
    return not is_active()


def _profile_exists():
    rc, out, _ = _nmcli(["-t", "-f", "NAME", "connection", "show"])
    return rc == 0 and CONNECTION in [split_terse(l)[0] for l in out.splitlines()]


# ----------------------------------------------------------------- policy
class Policy:
    """Decides when to start or stop the hotspot. Pure logic: tv.py feeds it
    what it observed and does what it answers.

    mode "off":  never; switches off a hotspot we made.
    mode "on":   always on.
    mode "auto": on only after GRACE_SECONDS with no network; off again when a
                 cable appears. Never while the user is in Settings (they may
                 be typing a Wi-Fi password), and not again for RETRY_SECONDS
                 after a failed start (so a missing permission does not loop).
    "on" also waits while the user is in Settings, so joining a Wi-Fi works.
    """

    def __init__(self, grace=GRACE_SECONDS, retry=RETRY_SECONDS):
        self.grace = grace
        self.retry = retry
        self._since = None           # when the network was first seen missing
        self._failed_at = None

    def failed(self, now):
        self._failed_at = now

    def reset(self):
        self._since = None

    def decide(self, now, mode, network, active, suppress=False, force=False):
        """-> "start", "stop" or None. force = the user has just chosen this
        mode, so act now: it ignores the Settings pause and the retry wait."""
        mode = clean_mode(mode)
        if mode == "off":
            return "stop" if active else None
        if suppress and not force:
            self._since = None
            return None
        if mode == "on":
            if active:
                return None
            return "start" if (force or self._can_retry(now)) else None
        # auto
        if network:
            self._since = None
            return "stop" if active else None
        if active:
            return None
        if self._since is None:
            self._since = now
            return None
        if now - self._since >= self.grace and self._can_retry(now):
            return "start"
        return None

    def _can_retry(self, now):
        return self._failed_at is None or now - self._failed_at >= self.retry
