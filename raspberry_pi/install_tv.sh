#!/bin/bash
# One-file installer for the retro-TV app: tv.py + channels.m3u + chime.wav.
# Does NOT touch the Arduino bridge or power-button services - those are
# unchanged infrastructure, already installed.
#
# Usage on the Pi:
#   bash install_tv.sh

set -e

echo "Installing tv.py ..."
cat > "$HOME/tv.py" <<'TV_PY_EOF_9f3'
#!/usr/bin/env python3
"""Retro-TV front end: a home screen of apps, 90s styling.

HOME  - a row of app tiles: LIVE TV, TOD, any apps you have added, and
        APP STORE for adding more by URL.
LIVE  - channels from an M3U, played by mpv rendered inside this window.
WEB   - TOD, or any app added through the store, in an embedded page.
STORE - type a name and a URL to add a new app to the home screen.

Controls (all reachable from the joystick alone):
    left / right    move along the home row / do nothing elsewhere
    up / down       move through the channel list (LIVE only)
    short press     launch the tile / play the channel / add app field
    long press      back: video -> channel list -> home; app -> home
    F11             leave / re-enter full screen (keyboard)
    Ctrl+Q          quit (keyboard, on purpose)

Typing a name and URL in the App Store needs a keyboard, the same as
signing in to TOD does.

Usage:  python3 tv.py [playlist.m3u]
"""
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
import urllib.parse
import urllib.request

IS_WINDOWS = sys.platform == "win32"

# On Linux mpv is embedded via an X11 window id, so run under X11 (Xwayland is
# fine). On Windows it is embedded via the window's HWND, so nothing is forced.
if not IS_WINDOWS:
    os.environ.setdefault("GDK_BACKEND", "x11")

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GdkPixbuf, GLib, Pango

# WebKit is optional: without it web apps explain what to install.
WEBKIT = None
for _ver in ("4.1", "4.0"):
    try:
        gi.require_version("WebKit2", _ver)
        from gi.repository import WebKit2 as WEBKIT
        break
    except (ValueError, ImportError):
        continue

DEFAULT_PLAYLIST = os.path.expanduser("~/channels.m3u")
if not os.path.exists(DEFAULT_PLAYLIST):
    # No copy in the home folder: use the one sitting next to this script.
    DEFAULT_PLAYLIST = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "channels.m3u")
# Cap which quality is taken from an adaptive stream, in bits per second.
# 2.5 Mbps lands on the 720p feed of most channels.
HLS_MAX_BITRATE = 2500000
TOD_URL = "https://tod.tv"
# Web apps serve their normal site, so present as an ordinary desktop browser.
WEB_USER_AGENT = (
    "Mozilla/5.0 (%s) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    % ("Windows NT 10.0; Win64; x64" if IS_WINDOWS else "X11; Linux aarch64")
)
# Where cookies, local storage and cache are kept between runs, so signing
# in to a web app only has to be done once. A WebView with no context is
# ephemeral - closing the app throws the session away.
WEB_DATA_DIR    = os.path.expanduser("~/.local/share/brack-tv/web")
WEB_CACHE_DIR   = os.path.expanduser("~/.cache/brack-tv/web")
WEB_COOKIE_FILE = os.path.join(WEB_DATA_DIR, "cookies.sqlite")

# Remembers which live channel was on when the app was last closed.
STATE_FILE = os.path.expanduser("~/.config/brack-tv/state.json")
# Apps added through the App Store: [{"name": ..., "url": ...}, ...].
APPS_FILE = os.path.expanduser("~/.config/brack-tv/apps.json")

# --- 1990s set-top styling -------------------------------------------------
# Silver panels, hard bevels, navy selection, teal surround, monospace type.
CSS = b"""
window, .root { background-color: #008080; }

.sidebar {
    background-color: #c0c0c0;
    border-right: 3px solid #404040;
}
.brand {
    background-color: #000080;
    color: #ffffff;
    font-family: monospace;
    font-size: 17px;
    font-weight: 700;
    padding: 8px 12px;
}

list { background-color: #ffffff; }
row { padding: 0px; }
.item {
    color: #000000;
    font-family: monospace;
    font-size: 23px;
    font-weight: 700;
    padding: 12px 14px;
}
.item-sub {
    color: #404040;
    font-family: monospace;
    font-size: 15px;
    padding: 10px 14px;
}
row:selected { background-color: #000080; }
row:selected .item, row:selected .item-sub { color: #ffff00; }

.videoarea {
    background-color: #000000;
    border-top: 3px solid #404040;
    border-left: 3px solid #404040;
    border-bottom: 3px solid #ffffff;
    border-right: 3px solid #ffffff;
}
.status {
    background-color: #c0c0c0;
    color: #000000;
    font-family: monospace;
    font-size: 14px;
    padding: 6px 12px;
    border-top: 2px solid #404040;
}
.nowplaying {
    background-color: #000080;
    color: #ffff00;
    font-family: monospace;
    font-size: 20px;
    font-weight: 700;
    padding: 8px 12px;
}
.hint {
    background-color: #c0c0c0;
    color: #000000;
    font-family: monospace;
    font-size: 14px;
    padding: 6px 12px;
    border-bottom: 2px solid #404040;
}
.logo {
    margin: 6px 6px 6px 12px;
    background-color: #ffffff;
}
.notice {
    background-color: #c0c0c0;
    color: #000000;
    font-family: monospace;
    font-size: 19px;
    padding: 40px;
}

.osd {
    background-color: #c0c0c0;
    border-top: 4px solid #ffffff;
    border-left: 4px solid #ffffff;
    border-bottom: 4px solid #404040;
    border-right: 4px solid #404040;
}
.osd-label {
    color: #000000;
    font-family: monospace;
    font-size: 20px;
    font-weight: 700;
    padding: 10px 14px 4px 14px;
}
.seg {
    min-width: 16px;
    min-height: 34px;
    margin: 2px;
    border-top: 2px solid #ffffff;
    border-left: 2px solid #ffffff;
    border-bottom: 2px solid #404040;
    border-right: 2px solid #404040;
}
.seg-on  { background-color: #000080; }
.seg-off { background-color: #909090; }

/* ---- home screen: a row of app tiles ---- */
.tile {
    background-color: #c0c0c0;
    border-top: 3px solid #ffffff;
    border-left: 3px solid #ffffff;
    border-bottom: 3px solid #404040;
    border-right: 3px solid #404040;
    margin: 16px;
}
.tile-icon {
    color: #000080;
    font-family: monospace;
    font-size: 40px;
    font-weight: 700;
}
.tile-name {
    color: #000000;
    font-family: monospace;
    font-size: 14px;
    font-weight: 700;
    padding-bottom: 10px;
}
.tile-selected {
    background-color: #000080;
    border-top: 3px solid #404040;
    border-left: 3px solid #404040;
    border-bottom: 3px solid #ffffff;
    border-right: 3px solid #ffffff;
}
.tile-selected .tile-icon,
.tile-selected .tile-name { color: #ffff00; }

/* ---- on-screen keyboard ---- */
.key {
    background-color: #c0c0c0;
    border-top: 2px solid #ffffff;
    border-left: 2px solid #ffffff;
    border-bottom: 2px solid #404040;
    border-right: 2px solid #404040;
}
.key-label {
    color: #000000;
    font-family: monospace;
    font-size: 15px;
    font-weight: 700;
}
.key-selected {
    background-color: #000080;
    border-top: 2px solid #404040;
    border-left: 2px solid #404040;
    border-bottom: 2px solid #ffffff;
    border-right: 2px solid #ffffff;
}
.key-selected .key-label { color: #ffff00; }

/* ---- app store ---- */
entry {
    font-family: monospace;
    font-size: 18px;
    background-color: #ffffff;
    color: #000000;
    border-top: 2px solid #404040;
    border-left: 2px solid #404040;
    border-bottom: 2px solid #ffffff;
    border-right: 2px solid #ffffff;
    padding: 8px;
    margin: 6px 20px;
}
"""


CHIME = os.path.join(os.path.dirname(os.path.abspath(__file__)), "chime.wav")
LOGO_CACHE = os.path.expanduser("~/.cache/brack-tv-logos")
LOGO_W, LOGO_H = 76, 50

APP_ICON_CACHE = os.path.expanduser("~/.cache/brack-tv/app-icons")
ICON_MAX_BYTES = 1024 * 1024
ICON_CACHE_SECONDS = 7 * 24 * 3600


def set_desktop_keyboard(visible):
    """Ask Raspberry Pi OS's Squeekboard to appear, without blocking GTK."""
    if IS_WINDOWS or not os.environ.get("XDG_RUNTIME_DIR"):
        return
    try:
        subprocess.Popen(
            ["busctl", "--user", "call", "sm.puri.OSK0", "/sm/puri/OSK0",
             "sm.puri.OSK0", "SetVisible", "b", str(bool(visible)).lower()],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def parse_speaker_volume(output):
    """Parse wpctl's sink level, not mpv's independent stream volume."""
    match = re.fullmatch(r"\s*Volume:\s*([0-9]+(?:\.[0-9]+)?)\s*(\[MUTED\])?\s*", output)
    if not match:
        raise ValueError("Unrecognized wpctl volume")
    return float(match[1]), bool(match[2])


def read_speaker_volume():
    """Read the current desktop user's default PipeWire output off-thread."""
    if IS_WINDOWS:
        return None
    try:
        result = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True, check=True, timeout=1,
            env=dict(os.environ, LC_ALL="C"),
        )
        return parse_speaker_volume(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def http_icon_url(base, href):
    """Only request web resources; never open local files from page metadata."""
    url = urllib.parse.urljoin(base, href)
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Not an HTTP icon URL")
    if parsed.username or parsed.password:
        raise ValueError("Credentials are not allowed in icon URLs")
    return url


class IconLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.base = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "base" and self.base is None:
            self.base = attrs.get("href")
        if tag != "link" or not attrs.get("href"):
            return
        rel = attrs.get("rel", "").lower().split()
        if "apple-touch-icon" in rel or "apple-touch-icon-precomposed" in rel:
            self.links.insert(0, attrs["href"])
        elif "icon" in rel:
            self.links.append(attrs["href"])


class IconRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return super().redirect_request(
            req, fp, code, msg, headers, http_icon_url(req.full_url, newurl))


def read_icon_resource(url):
    url = http_icon_url(url, "")
    request = urllib.request.Request(url, headers={"User-Agent": WEB_USER_AGENT})
    # No browser cookies or credentials are sent. Never use a favicon proxy.
    with urllib.request.build_opener(IconRedirectHandler()).open(request, timeout=3) as response:
        final_url = http_icon_url(response.geturl(), "")
        data = response.read(ICON_MAX_BYTES + 1)
        if len(data) > ICON_MAX_BYTES:
            raise ValueError("Icon resource too large")
        return data, final_url


def decode_app_icon(data):
    loader = GdkPixbuf.PixbufLoader.new()
    loader.set_size(64, 64)
    loader.write(data)
    loader.close()
    pixbuf = loader.get_pixbuf()
    if pixbuf is None:
        raise ValueError("Empty image")
    return pixbuf


def fetch_app_icon(url):
    """Discover and cache a real website icon; return None for text fallback."""
    cache = os.path.join(APP_ICON_CACHE, hashlib.sha256(url.encode()).hexdigest() + ".png")
    cached = None
    try:
        cached = GdkPixbuf.Pixbuf.new_from_file_at_scale(cache, 64, 64, True)
        if time.time() - os.path.getmtime(cache) < ICON_CACHE_SECONDS:
            return cached
    except (OSError, GLib.Error):
        pass
    try:
        url = http_icon_url(url, "")
    except ValueError:
        return cached
    candidates = []
    try:
        html, final_url = read_icon_resource(url)
        parser = IconLinks()
        parser.feed(html.decode("utf-8", errors="replace"))
        base = final_url
        if parser.base:
            try:
                base = http_icon_url(final_url, parser.base)
            except ValueError:
                pass
        for href in parser.links[:6]:
            try:
                candidates.append(http_icon_url(base, href))
            except ValueError:
                pass
        candidates.append(http_icon_url(final_url, "/favicon.ico"))
    except (OSError, ValueError):
        pass
    candidates.append(http_icon_url(url, "/favicon.ico"))
    for candidate in dict.fromkeys(candidates):
        try:
            data, _ = read_icon_resource(candidate)
            pixbuf = decode_app_icon(data)
        except (OSError, ValueError, GLib.Error):
            continue
        try:
            os.makedirs(APP_ICON_CACHE, exist_ok=True)
            # Atomic replacement avoids partial cache entries after a shutdown.
            temporary = cache + ".%s.tmp" % threading.get_ident()
            pixbuf.savev(temporary, "png", [], [])
            os.replace(temporary, cache)
        except (OSError, GLib.Error):
            pass
        return pixbuf
    return cached


def load_playlist(path):
    """Return [(name, url, logo_url, group), ...] from an M3U file."""
    items, name, logo, group = [], None, None, None
    if not os.path.exists(path):
        return items
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("#EXTINF"):
                m = re.search(r'tvg-logo="([^"]+)"', line)
                logo = m.group(1) if m else None
                m = re.search(r'group-title="([^"]+)"', line)
                group = m.group(1) if m else None
                name = line.split(",", 1)[1].strip() if "," in line else None
            elif line.startswith("#"):
                continue
            else:
                items.append((name or line, line, logo, group))
                name, logo, group = None, None, None
    return items


# @word typed in the search bar maps to a group-title, case-insensitive.
SEARCH_CATEGORY_ALIASES = {
    "kids": "Kids", "kid": "Kids",
    "news": "News",
    "sports": "Sports", "sport": "Sports",
    "islamic": "Islamic", "islam": "Islamic",
    "music": "Music",
    "movies": "Movies", "movie": "Movies",
    "series": "Series",
    "documentary": "Documentary", "doc": "Documentary", "docs": "Documentary",
    "culture": "Culture",
    "business": "Business", "biz": "Business",
    "entertainment": "Entertainment",
    "family": "Family",
    "education": "Education", "edu": "Education",
    "comedy": "Comedy",
    "classic": "Classic",
    # no "animation" entry: every animated channel in the list is also
    # tagged kids, and Kids wins priority - an @animation search would
    # always come back empty, which reads as broken rather than correct
    "cooking": "Cooking", "food": "Cooking",
    "general": "General",
}

# The on-screen keyboard's layout. Rows can be different lengths; the
# joystick's row/col navigation clamps the column when it changes row.
KEY_ROWS = [
    list("1234567890"),
    list("QWERTYUIOP"),
    list("ASDFGHJKL"),
    list("ZXCVBNM@"),
    ["SPACE", "DEL", "CLEAR", "DONE"],
]


def cached_logo(url):
    """Path to the cached logo, downloading it the first time. None on failure."""
    path = os.path.join(LOGO_CACHE, hashlib.sha1(url.encode()).hexdigest())
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return path
    try:
        os.makedirs(LOGO_CACHE, exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()
        if not data:
            return None
        with open(path, "wb") as fh:
            fh.write(data)
        return path
    except Exception:
        return None


def play_chime():
    """Short startup sound. Silently skipped if the file is missing."""
    if not os.path.exists(CHIME):
        return
    try:
        subprocess.Popen(
            ["mpv", "--no-video", "--really-quiet"] + _ao_args() + [CHIME],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def load_state():
    """{"channel_title": ...} from the last run, or {} on first run."""
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(state):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(STATE_FILE, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
    except OSError:
        pass


def load_apps():
    """Apps added through the store: [{"name": ..., "url": ...}, ...]."""
    try:
        with open(APPS_FILE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []


def save_apps(apps):
    try:
        os.makedirs(os.path.dirname(APPS_FILE), exist_ok=True)
        with open(APPS_FILE, "w", encoding="utf-8") as fh:
            json.dump(apps, fh)
    except OSError:
        pass


def make_persistent_webview():
    """A WebView whose cookies, local storage and cache survive a restart."""
    os.makedirs(WEB_DATA_DIR, exist_ok=True)
    os.makedirs(WEB_CACHE_DIR, exist_ok=True)
    manager = WEBKIT.WebsiteDataManager(
        base_data_directory=WEB_DATA_DIR,
        base_cache_directory=WEB_CACHE_DIR,
    )
    context = WEBKIT.WebContext.new_with_website_data_manager(manager)
    cookies = context.get_cookie_manager()
    cookies.set_persistent_storage(
        WEB_COOKIE_FILE, WEBKIT.CookiePersistentStorage.SQLITE)
    cookies.set_accept_policy(WEBKIT.CookieAcceptPolicy.ALWAYS)
    return WEBKIT.WebView.new_with_context(context)


# Audio output goes through PipeWire's own routing (--ao=pipewire) rather
# than a hardcoded ALSA device, so it follows whatever "wpctl set-default"
# is set to on the Pi - headphone jack, HDMI, a Bluetooth speaker, etc.
# "wpctl status" lists the sinks; "wpctl set-default <id>" changes it.
# On Windows mpv picks the right output (WASAPI) by itself.
AUDIO_OUTPUT_DRIVER = None if IS_WINDOWS else "pipewire"


def _ao_args():
    return ["--ao=%s" % AUDIO_OUTPUT_DRIVER] if AUDIO_OUTPUT_DRIVER else []


def native_window_id(win):
    """The id mpv's --wid wants for a realised Gdk window.

    X11: the XID. Windows: the HWND, which needs a real native child window
    (GTK3 draws child widgets client-side by default).
    """
    if not IS_WINDOWS:
        return win.get_xid()
    import ctypes
    win.ensure_native()
    getptr = ctypes.pythonapi.PyCapsule_GetPointer
    getptr.restype = ctypes.c_void_p
    getptr.argtypes = [ctypes.py_object, ctypes.c_char_p]
    ptr = getptr(win.__gpointer__, None)
    gdk = ctypes.CDLL("libgdk-3-0.dll")
    gdk.gdk_win32_window_get_handle.restype = ctypes.c_void_p
    gdk.gdk_win32_window_get_handle.argtypes = [ctypes.c_void_p]
    return gdk.gdk_win32_window_get_handle(ptr)

SEGMENTS = 16          # blocks in the volume bar
# PipeWire owns the Pi's volume; do not secretly attenuate it again in mpv.
START_VOLUME = 70 if IS_WINDOWS else 100
OSD_TIMEOUT_MS = 1800  # how long the bar stays on screen


class VolumeOSD(Gtk.Window):
    """Chunky on-screen volume bar, in the style of an old TV menu.

    A separate always-on-top window rather than an overlay, because mpv
    draws into its own X11 child window and GTK cannot paint above that.
    """

    def __init__(self):
        super().__init__(type=Gtk.WindowType.POPUP)
        self.set_keep_above(True)
        self.set_accept_focus(False)
        self.set_focus_on_map(False)
        self.get_style_context().add_class("osd")
        self._timer = None

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)

        self.caption = Gtk.Label(label="VOLUME", xalign=0)
        self.caption.get_style_context().add_class("osd-label")
        box.pack_start(self.caption, False, False, 0)

        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        bar.set_margin_start(12)
        bar.set_margin_end(12)
        bar.set_margin_bottom(12)
        box.pack_start(bar, False, False, 0)

        self.segments = []
        for _ in range(SEGMENTS):
            seg = Gtk.Box()
            seg.get_style_context().add_class("seg")
            seg.get_style_context().add_class("seg-off")
            bar.pack_start(seg, False, False, 0)
            self.segments.append(seg)

    def show_level(self, level, muted=False, source="SPEAKER"):
        """Display the reported percentage, including amplified sinks >100%."""
        lit = 0 if muted else int(round(min(1.0, max(0.0, level)) * SEGMENTS))
        for i, seg in enumerate(self.segments):
            ctx = seg.get_style_context()
            ctx.remove_class("seg-on" if i >= lit else "seg-off")
            ctx.add_class("seg-on" if i < lit else "seg-off")
        self.caption.set_text("%s  %d%%%s" % (
            source, int(round(level * 100)), "  MUTED" if muted else ""))

        self.show_all()
        screen_w = self.get_screen().get_width()
        screen_h = self.get_screen().get_height()
        w, h = self.get_size()
        self.move((screen_w - w) // 2, screen_h - h - 60)

        if self._timer:
            GLib.source_remove(self._timer)
        self._timer = GLib.timeout_add(OSD_TIMEOUT_MS, self._hide)

    def _hide(self):
        self.hide()
        self._timer = None
        return False

    def dismiss(self):
        if self._timer is not None:
            GLib.source_remove(self._timer)
            self._timer = None
        self.hide()


class Player:
    """One mpv process drawing into our video area.

    Pi playback stays at unity (100%); the knob controls the PipeWire sink.
    Windows retains its existing player volume and named-pipe IPC.
    """

    SOCKET = r"\\.\pipe\tv-mpv" if IS_WINDOWS else "/tmp/tv-mpv.sock"

    def __init__(self):
        self.proc = None

    def _ipc(self, payload):
        """Fire a command at the running mpv. Returns True if it landed."""
        data = (json.dumps(payload) + "\n").encode()
        try:
            if IS_WINDOWS:
                # mpv's IPC on Windows is a named pipe, opened like a file.
                with open(self.SOCKET, "r+b", buffering=0) as pipe:
                    pipe.write(data)
                return True
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.4)
            s.connect(self.SOCKET)
            s.sendall(data)
            s.close()
            return True
        except OSError:
            return False

    def set_volume(self, level):
        """level is 0 - 100."""
        return self._ipc({"command": ["set_property", "volume", level]})

    def set_mute(self, muted):
        return self._ipc({"command": ["set_property", "mute", bool(muted)]})

    def play(self, url, xid, volume=START_VOLUME, muted=False):
        self.stop()
        if not IS_WINDOWS:
            try:
                os.unlink(self.SOCKET)
            except OSError:
                pass
        if IS_WINDOWS:
            # Generic GPU decode and output; the Pi's V4L2/EGL flags do not exist.
            video_args = ["--hwdec=auto-safe", "--vo=gpu"]
        else:
            # Zero-copy V4L2 decoding straight into EGL.
            video_args = ["--hwdec=v4l2m2m", "--vo=gpu", "--gpu-context=x11egl"]
        self.proc = subprocess.Popen([
            "mpv",
            # mpv's low-overhead profile. Without it, audio drifts seconds
            # ahead of video on live sport.
            "--profile=fast",
            "--wid=%d" % xid,
            "--no-osc", "--no-input-default-bindings", "--no-terminal",
            # mpv must not take the keyboard, or its window swallows our keys.
            "--input-vo-keyboard=no", "--input-cursor=no",
            "--keep-open=no", "--idle=no",
            "--cache=yes", "--demuxer-max-bytes=64MiB",
            "--demuxer-readahead-secs=30",
            "--cache-pause=yes", "--cache-pause-wait=3",
            "--hls-bitrate=%d" % HLS_MAX_BITRATE,
            # Our own volume, and a socket so we can change it while playing
            "--volume=%d" % volume,
            "--mute=%s" % ("yes" if muted else "no"),
            "--input-ipc-server=%s" % self.SOCKET,
        ] + video_args + _ao_args() + [url])

    def stop(self):
        proc, self.proc = self.proc, None
        if proc and proc.poll() is None:
            try:
                proc.terminate()
            except OSError:
                return
            # Reap the old player without blocking GTK for up to 3 seconds.
            def reap():
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    try:
                        proc.kill()
                    except OSError:
                        pass
                    proc.wait()
            threading.Thread(target=reap, daemon=True).start()

    @property
    def running(self):
        return self.proc is not None and self.proc.poll() is None


class TVWindow(Gtk.Window):
    # kind of tile -> its icon text; anything else uses the first 3 letters
    # of the app's own name (so a custom app just works with no config).
    TILE_ICON = {"live": "TV", "store": "+"}

    def __init__(self, playlist_path):
        super().__init__(title="TV")
        self.playlist_path = playlist_path
        self.channels = load_playlist(playlist_path)

        self.screen = "HOME"           # HOME / LIVE / WEB / STORE
        self.player = Player()
        self.video_full = False
        self.window_full = True
        self.webview = None
        self.current_web_key = None    # which web app's URL is loaded
        self.osd = VolumeOSD()
        self.volume = START_VOLUME
        self.muted = False
        self.logo_slots = []
        self._logo_generation = 0
        self._logo_pending = set()
        self._logo_lock = threading.Lock()
        self.search_row = None
        self.keyboard_open = False
        self.osk_row, self.osk_col = 1, 0
        self.osk_widgets = []
        self.home_apps = []
        self.home_tiles = []
        self.home_index = 0
        self._closed = False
        self._speaker_level = None
        self._volume_busy = False
        self._audio_workers = ThreadPoolExecutor(max_workers=1)
        self._icon_workers = ThreadPoolExecutor(max_workers=2)
        self._icon_generation = 0
        self._icon_jobs = []

        self.state = load_state()
        # Only resume automatically if a previous run actually left a
        # channel behind - an empty state file must not force autoplay.
        self.resume_pending = bool(self.state.get("channel_title"))

        self.set_default_size(1280, 720)
        self.fullscreen()
        self.get_style_context().add_class("root")

        self.outer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(self.outer)

        self._build_home()
        self._build_live()
        self._build_web()
        self._build_store()

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", self.on_destroy)

        self.populate()
        self.refresh_store_list()
        self.rebuild_home_apps()
        self._volume_timer = None
        if not IS_WINDOWS:
            self._volume_timer = GLib.timeout_add(500, self._poll_speaker)
            self._poll_speaker()

    # ================================================================
    #  HOME - a row of app tiles
    # ================================================================
    def _build_home(self):
        self.home_screen = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.outer.pack_start(self.home_screen, True, True, 0)

        brand = Gtk.Label(label=" BRACK STUDY TV ", xalign=0)
        brand.get_style_context().add_class("brand")
        self.home_screen.pack_start(brand, False, False, 0)

        # Centring goes on the tile row itself, not the scroller: the
        # scroller is packed with expand+fill so it already fills the
        # space, which would make a valign set on it do nothing.
        row_scroller = Gtk.ScrolledWindow()
        row_scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER)
        self.home_tile_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.home_tile_box.set_halign(Gtk.Align.CENTER)
        self.home_tile_box.set_valign(Gtk.Align.CENTER)
        row_scroller.add(self.home_tile_box)
        self.home_screen.pack_start(row_scroller, True, True, 0)

        home_hint = Gtk.Label(
            label=" LEFT/RIGHT CHOOSE   PRESS TO LAUNCH ", xalign=0)
        home_hint.get_style_context().add_class("hint")
        self.home_screen.pack_start(home_hint, False, False, 0)

        self.speaker_bar = Gtk.ProgressBar()
        self.speaker_bar.set_show_text(True)
        self.speaker_bar.set_text("SPEAKER UNAVAILABLE" if not IS_WINDOWS
                                  else "SPEAKER LEVEL UNAVAILABLE ON WINDOWS")
        self.speaker_bar.set_margin_start(24)
        self.speaker_bar.set_margin_end(24)
        self.speaker_bar.set_margin_top(8)
        self.speaker_bar.set_margin_bottom(12)
        self.home_screen.pack_start(self.speaker_bar, False, False, 0)

    def _poll_speaker(self):
        if self._closed:
            return False
        if not self._volume_busy:
            self._volume_busy = True
            future = self._audio_workers.submit(read_speaker_volume)
            future.add_done_callback(self._speaker_read_done)
        return True

    def _speaker_read_done(self, future):
        try:
            result = future.result()
        except Exception:
            result = None
        if not self._closed:
            GLib.idle_add(self._apply_speaker_level, result)

    def _apply_speaker_level(self, result):
        self._volume_busy = False
        if self._closed:
            return False
        previous = self._speaker_level
        self._speaker_level = result
        if result is None:
            self.speaker_bar.set_fraction(0)
            self.speaker_bar.set_text("SPEAKER UNAVAILABLE")
            self.osd.dismiss()
            return False
        level, muted = result
        self.speaker_bar.set_fraction(0 if muted else min(1.0, level))
        self.speaker_bar.set_text("SPEAKER  %d%%%s" % (
            round(level * 100), "  MUTED" if muted else ""))
        if previous is not None and (round(previous[0] * 100), previous[1]) != (
                round(level * 100), muted):
            self.osd.show_level(level, muted)
        return False

    def rebuild_home_apps(self):
        """Re-reads apps.json and rebuilds the tiles - call after add/remove."""
        custom = load_apps()
        self.home_apps = (
            [{"kind": "live", "name": "LIVE TV", "url": None}] +
            [{"kind": "web", "name": "TOD", "url": TOD_URL}] +
            [{"kind": "web", "name": a.get("name") or "APP", "url": a["url"]}
             for a in custom if a.get("url")] +
            [{"kind": "store", "name": "APP STORE", "url": None}]
        )
        if self.home_index >= len(self.home_apps):
            self.home_index = len(self.home_apps) - 1
        self._build_home_tiles()

    def _build_home_tiles(self):
        self._icon_generation += 1
        generation = self._icon_generation
        for job in self._icon_jobs:
            job.cancel()
        self._icon_jobs = []
        for child in self.home_tile_box.get_children():
            self.home_tile_box.remove(child)
        self.home_tiles = []

        for app in self.home_apps:
            tile = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tile.set_can_focus(True)          # needed for scroll-into-view
            tile.get_style_context().add_class("tile")
            tile.set_size_request(190, 150)

            icon_text = self.TILE_ICON.get(app["kind"], app["name"][:3].upper())
            icon = Gtk.Label(label=icon_text)
            icon.get_style_context().add_class("tile-icon")
            icon.set_valign(Gtk.Align.CENTER)
            tile.pack_start(icon, True, True, 0)
            if app["kind"] == "web":
                future = self._icon_workers.submit(fetch_app_icon, app["url"])
                self._icon_jobs.append(future)
                future.add_done_callback(
                    lambda task, target=icon, parent=tile, version=generation:
                    self._app_icon_done(task, target, parent, version))

            name_lab = Gtk.Label(label=app["name"].upper())
            name_lab.get_style_context().add_class("tile-name")
            name_lab.set_ellipsize(Pango.EllipsizeMode.END)
            name_lab.set_max_width_chars(15)
            tile.pack_start(name_lab, False, False, 0)

            self.home_tile_box.pack_start(tile, False, False, 0)
            self.home_tiles.append(tile)

        self.home_tile_box.show_all()
        self.select_home_tile(self.home_index)

    def _app_icon_done(self, future, fallback, tile, generation):
        if future.cancelled() or self._closed:
            return
        try:
            pixbuf = future.result()
        except Exception:
            return  # The text tile remains usable if discovery fails.
        if pixbuf is not None:
            GLib.idle_add(self._apply_app_icon, pixbuf, fallback, tile, generation)

    def _apply_app_icon(self, pixbuf, fallback, tile, generation):
        if self._closed or generation != self._icon_generation:
            return False
        tile.remove(fallback)
        icon = Gtk.Image.new_from_pixbuf(pixbuf)
        tile.pack_start(icon, True, True, 0)
        tile.reorder_child(icon, 0)
        icon.show()
        return False

    def select_home_tile(self, idx):
        if not self.home_apps:
            return
        self.home_index = idx % len(self.home_apps)
        for i, tile in enumerate(self.home_tiles):
            ctx = tile.get_style_context()
            if i == self.home_index:
                ctx.add_class("tile-selected")
            else:
                ctx.remove_class("tile-selected")
        if self.screen == "HOME":
            self.home_tiles[self.home_index].grab_focus()

    def launch_app(self, app):
        kind = app["kind"]
        if kind == "live":
            self.screen = "LIVE"
            self.apply_screen()
        elif kind == "web":
            if self.webview is None and IS_WINDOWS:
                # No embedded browser on Windows: use the normal one.
                import webbrowser
                webbrowser.open(app["url"])
                return
            if self.webview is not None and app["url"] != self.current_web_key:
                self.webview.load_uri(app["url"])
                self.current_web_key = app["url"]
            self.screen = "WEB"
            self.apply_screen()
        elif kind == "store":
            self.refresh_store_list()
            self.screen = "STORE"
            self.apply_screen()

    def go_home(self):
        self.screen = "HOME"
        self.apply_screen()

    # ================================================================
    #  LIVE - channel list + video
    # ================================================================
    def _build_live(self):
        self.sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.sidebar.set_size_request(460, -1)
        self.sidebar.get_style_context().add_class("sidebar")
        self.outer.pack_start(self.sidebar, False, False, 0)

        header = Gtk.Label(label=" LIVE TV ", xalign=0)
        header.get_style_context().add_class("brand")
        self.sidebar.pack_start(header, False, False, 0)

        # Shows the current search text. A real keyboard can still Tab into
        # it and type directly - that keeps working - but the joystick path
        # is the pinned [ SEARCH ] row below, which opens the on-screen
        # keyboard and types into this same box for you.
        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text(
            "SEARCH, OR @kids @news @sports @islamic @music ...")
        self.search_entry.connect(
            "changed", lambda *_: self.filter_channels(self.search_entry.get_text()))
        self.search_entry.connect("activate", lambda *_: self._focus_first_result())
        self.sidebar.pack_start(self.search_entry, False, False, 0)

        # list_scroller and keyboard_box are siblings in the same slot -
        # exactly one is visible at a time, the same pattern used for the
        # HOME / LIVE / WEB / STORE screens themselves.
        self.list_scroller = Gtk.ScrolledWindow()
        self.list_scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.BROWSE)
        self.listbox.connect("row-activated", lambda _, row: self.activate_row(row))
        self.list_scroller.add(self.listbox)
        self.sidebar.pack_start(self.list_scroller, True, True, 0)

        self._build_keyboard()
        self.sidebar.pack_start(self.keyboard_box, True, True, 0)
        self.keyboard_box.set_visible(False)

        self.status = Gtk.Label(label="", xalign=0)
        self.status.get_style_context().add_class("status")
        self.sidebar.pack_start(self.status, False, False, 0)

        self.right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.outer.pack_start(self.right, True, True, 0)

        self.nowplaying = Gtk.Label(label=" NOTHING PLAYING ", xalign=0)
        self.nowplaying.get_style_context().add_class("nowplaying")
        self.nowplaying.set_ellipsize(Pango.EllipsizeMode.END)
        self.right.pack_start(self.nowplaying, False, False, 0)

        self.hint = Gtk.Label(
            label=" UP/DOWN CHOOSE   PRESS PLAY   HOLD BACK ", xalign=0)
        self.hint.get_style_context().add_class("hint")
        self.right.pack_start(self.hint, False, False, 0)

        self.video = Gtk.DrawingArea()
        self.video.get_style_context().add_class("videoarea")
        self.video.set_can_focus(False)
        self.right.pack_start(self.video, True, True, 0)

    def _build_keyboard(self):
        """The on-screen keyboard: a grid the joystick drives directly, so
        search never needs a physical keyboard plugged in."""
        self.keyboard_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        grid = Gtk.Grid()
        grid.set_column_spacing(4)
        grid.set_row_spacing(4)
        grid.set_halign(Gtk.Align.CENTER)
        grid.set_margin_top(16)
        self.keyboard_box.pack_start(grid, True, True, 0)

        self.osk_widgets = []
        for r, row_keys in enumerate(KEY_ROWS):
            widget_row = []
            for c, label in enumerate(row_keys):
                key = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
                key.get_style_context().add_class("key")
                wide = len(label) > 1
                key.set_size_request(76 if wide else 38, 38)
                lab = Gtk.Label(label=label)
                lab.get_style_context().add_class("key-label")
                key.pack_start(lab, True, True, 0)
                grid.attach(key, c, r, 1, 1)
                widget_row.append(key)
            self.osk_widgets.append(widget_row)

        kb_hint = Gtk.Label(
            label=" MOVE: JOYSTICK   PRESS: SELECT KEY   HOLD: DONE ", xalign=0)
        kb_hint.get_style_context().add_class("hint")
        self.keyboard_box.pack_start(kb_hint, False, False, 12)

    def populate(self, items=None):
        """Rebuilds the visible list. `items` defaults to every channel;
        filter_channels() passes a narrowed-down list while searching.

        Row 0 is always the pinned [ SEARCH ] row - reachable by joystick
        the same way as any channel, even when there are zero matches."""
        first_call = items is None and not hasattr(self, "displayed")
        if items is None:
            items = self.channels
        if not first_call and items == getattr(self, "displayed", None):
            return
        self.displayed = items
        self._logo_generation += 1

        for child in self.listbox.get_children():
            self.listbox.remove(child)

        self.search_row = Gtk.ListBoxRow()
        search_lab = Gtk.Label(label="[ SEARCH / @CATEGORY ]", xalign=0)
        search_lab.get_style_context().add_class("item")
        self.search_row.add(search_lab)
        self.listbox.add(self.search_row)

        if not items:
            row = Gtk.ListBoxRow()
            msg = ("NO CHANNELS IN %s" % self.playlist_path if not self.channels
                   else "NO MATCHES")
            lab = Gtk.Label(label=msg, xalign=0)
            lab.get_style_context().add_class("item-sub")
            row.add(lab)
            row.set_selectable(False)
            self.listbox.add(row)
        else:
            self.logo_slots = []
            remembered_title = self.state.get("channel_title") if first_call else None
            remembered_row = None
            for title, _url, logo, _group in items:
                row = Gtk.ListBoxRow()
                line = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)

                img = Gtk.Image()
                img.set_size_request(LOGO_W, LOGO_H)
                img.get_style_context().add_class("logo")
                line.pack_start(img, False, False, 0)
                self.logo_slots.append((img, logo))

                lab = Gtk.Label(label=title, xalign=0)
                lab.get_style_context().add_class("item")
                lab.set_ellipsize(Pango.EllipsizeMode.END)
                line.pack_start(lab, True, True, 0)

                row.add(line)
                self.listbox.add(row)
                if title == remembered_title:
                    remembered_row = row
            self.load_logos()

        self.listbox.show_all()
        # default focus is the first CHANNEL (index 1), not the search row,
        # so browsing feels the same as before; up from here still reaches
        # the search row, same as any other row.
        target = remembered_row if items and remembered_row else \
            self.listbox.get_row_at_index(1)
        if target is None or not target.get_selectable():
            target = self.search_row
        self.listbox.select_row(target)
        target.grab_focus()              # scrolls it into view too
        n = len(items)
        self.status.set_text(" %d CHANNEL%s " % (n, "" if n == 1 else "S"))

    def filter_channels(self, query):
        query = query.strip()
        if not query:
            filtered = self.channels
        elif query.startswith("@"):
            target = SEARCH_CATEGORY_ALIASES.get(query[1:].strip().lower())
            filtered = [c for c in self.channels if c[3] == target] if target else []
        else:
            q = query.lower()
            filtered = [c for c in self.channels if q in c[0].lower()]
        self.populate(filtered)

    def _focus_first_result(self):
        row = self.listbox.get_row_at_index(1)   # first channel, not [ SEARCH ]
        if row is None or not row.get_selectable():
            row = self.search_row
        self.listbox.select_row(row)
        row.grab_focus()

    def load_logos(self):
        """Load logos serially, cancelling stale list generations."""
        slots = list(self.logo_slots)
        generation = self._logo_generation

        def worker():
            for img, url in slots:
                if generation != self._logo_generation:
                    return
                if not url:
                    continue
                path = cached_logo(url)
                if path and generation == self._logo_generation:
                    GLib.idle_add(self._set_logo_if_current, img, path, generation)

        # Only one logo worker at a time: avoid spawning hundreds on search.
        with self._logo_lock:
            if self._logo_pending:
                self._logo_pending.clear()
            self._logo_pending.add(generation)
        def run():
            try:
                worker()
            finally:
                with self._logo_lock:
                    self._logo_pending.discard(generation)
        threading.Thread(target=run, daemon=True).start()

    def _set_logo_if_current(self, img, path, generation):
        if generation == self._logo_generation:
            return self._set_logo(img, path)
        return False

    def _set_logo(self, img, path):
        try:
            pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                path, LOGO_W, LOGO_H, True)
            img.set_from_pixbuf(pb)
        except GLib.Error:
            pass          # unreadable image, leave the slot blank
        return False

    def resume_playback(self):
        """Runs once, after the window is on screen: turning the TV back on
        picks up whatever channel was playing when it was last closed."""
        if not self.resume_pending:
            return False
        self.resume_pending = False
        self.screen = "LIVE"
        self.apply_screen()
        row = self.listbox.get_selected_row()
        if row is not None and row.get_selectable() and row is not self.search_row:
            self.play_selected()
        return False   # GLib.idle_add: do not call again

    def activate_row(self, row):
        """What a press on a listbox row does: open the keyboard for the
        pinned search row, otherwise play that channel."""
        if row is self.search_row:
            self.open_keyboard()
        else:
            self.play_selected()

    def play_selected(self):
        row = self.listbox.get_selected_row()
        if row is None or row is self.search_row or not self.displayed:
            return
        idx = row.get_index() - 1          # row 0 is the pinned search row
        if idx < 0 or idx >= len(self.displayed):
            return
        title, url, _logo, _group = self.displayed[idx]

        win = self.video.get_window()
        if win is None:
            self.status.set_text(" VIDEO AREA NOT READY ")
            return
        try:
            xid = native_window_id(win)
        except (AttributeError, OSError, TypeError, ValueError):
            self.status.set_text(
                " NEEDS A NATIVE WINDOW ID " if IS_WINDOWS
                else " NEEDS X11: GDK_BACKEND=x11 python3 tv.py ")
            return

        self.nowplaying.set_text(" " + title.upper() + " ")
        self.status.set_text(" PLAYING ")
        self.player.play(url, xid, volume=self.volume, muted=self.muted)
        self.state["channel_title"] = title
        save_state(self.state)
        # Fill the screen straight away: the joystick cannot press "f".
        if not self.video_full:
            self.toggle_video_full()
        # Show the level whenever a channel starts. Without this a volume of
        # zero looks like a broken channel rather than a turned-down system.
        if IS_WINDOWS:
            self.osd.show_level(self.volume / 100.0, muted=self.muted, source="PLAYER")
        elif self._speaker_level is not None:
            self.osd.show_level(*self._speaker_level)

    def toggle_video_full(self):
        self.video_full = not self.video_full
        self.sidebar.set_visible(not self.video_full)
        self.nowplaying.set_visible(not self.video_full)
        self.hint.set_visible(not self.video_full)

    # ---------------- on-screen keyboard ----------------
    def open_keyboard(self):
        self.keyboard_open = True
        self.osk_row, self.osk_col = 1, 0    # start on letters, not digits
        self._refresh_osk_highlight()
        self.list_scroller.set_visible(False)
        self.keyboard_box.set_visible(True)

    def close_keyboard(self):
        self.keyboard_open = False
        self.keyboard_box.set_visible(False)
        self.list_scroller.set_visible(True)
        self._focus_first_result()

    def _refresh_osk_highlight(self):
        for r, row in enumerate(self.osk_widgets):
            for c, key in enumerate(row):
                ctx = key.get_style_context()
                if r == self.osk_row and c == self.osk_col:
                    ctx.add_class("key-selected")
                else:
                    ctx.remove_class("key-selected")

    def osk_move(self, drow, dcol):
        if drow:
            self.osk_row = (self.osk_row + drow) % len(KEY_ROWS)
            self.osk_col = min(self.osk_col, len(KEY_ROWS[self.osk_row]) - 1)
        if dcol:
            row = KEY_ROWS[self.osk_row]
            self.osk_col = (self.osk_col + dcol) % len(row)
        self._refresh_osk_highlight()

    def osk_activate(self):
        label = KEY_ROWS[self.osk_row][self.osk_col]
        text = self.search_entry.get_text()
        if label == "SPACE":
            self.search_entry.set_text(text + " ")
        elif label == "DEL":
            self.search_entry.set_text(text[:-1])
        elif label == "CLEAR":
            self.search_entry.set_text("")
        elif label == "DONE":
            self.close_keyboard()
            return
        else:
            self.search_entry.set_text(text + label)
        self.search_entry.set_position(-1)

    # ================================================================
    #  WEB - TOD, or any app added through the store
    # ================================================================
    def _build_web(self):
        self.web_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.outer.pack_start(self.web_box, True, True, 0)
        if WEBKIT is not None:
            try:
                self.webview = make_persistent_webview()
            except (GLib.Error, AttributeError, TypeError):
                # Older WebKitGTK without WebsiteDataManager support - web
                # apps still work, they just will not remember sign-ins.
                self.webview = WEBKIT.WebView()
            settings = self.webview.get_settings()
            settings.set_user_agent(WEB_USER_AGENT)
            settings.set_property("enable-webgl", True)
            try:
                settings.set_property("media-playback-requires-user-gesture", False)
            except TypeError:
                pass
            self._setup_web_keyboard_detection()
            self.web_box.pack_start(self.webview, True, True, 0)
        else:
            notice = Gtk.Label(
                label="WEB APPS NEED WEBKIT.\n\n"
                      "sudo apt install -y gir1.2-webkit2-4.1\n\n"
                      "THEN RESTART THIS APP.",
                xalign=0)
            notice.get_style_context().add_class("notice")
            self.web_box.pack_start(notice, True, True, 0)

    def _setup_web_keyboard_detection(self):
        """Show the system keyboard on web text-input focus."""
        try:
            manager = self.webview.get_user_content_manager()
            if not manager.register_script_message_handler("retroKeyboard"):
                return
            manager.connect("script-message-received::retroKeyboard",
                            self._on_web_keyboard_focus)
            js = r"""
(function() {
  if (window.__retroKeyboard) return;
  window.__retroKeyboard = true;
  function update() {
    var el = document.activeElement, editable = false;
    if (el) {
      var tag = el.tagName, type = (el.type || 'text').toLowerCase();
      editable = !el.disabled && !el.readOnly &&
        (tag === 'TEXTAREA' || el.isContentEditable ||
         (tag === 'INPUT' && !/^(button|submit|reset|checkbox|radio|file|hidden|image|range|color)$/.test(type)));
    }
    try { window.webkit.messageHandlers.retroKeyboard.postMessage(editable ? 'show' : 'hide'); }
    catch (e) {}
  }
  document.addEventListener('focusin', update, true);
  document.addEventListener('focusout', function(){ setTimeout(update, 100); }, true);
})();
"""
            manager.add_script(WEBKIT.UserScript.new(
                js, WEBKIT.UserContentInjectedFrames.ALL_FRAMES,
                WEBKIT.UserScriptInjectionTime.START, None, None))
        except (AttributeError, GLib.Error, TypeError):
            pass

    def _on_web_keyboard_focus(self, _manager, message):
        if self.screen != "WEB" or self._closed:
            return
        try:
            action = message.get_js_value().to_string()
        except (AttributeError, TypeError):
            return
        if action in ("show", "hide"):
            set_desktop_keyboard(action == "show")

    # ================================================================
    #  STORE - add an app by URL
    # ================================================================
    def _build_store(self):
        self.store_screen = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.outer.pack_start(self.store_screen, True, True, 0)

        brand = Gtk.Label(label=" APP STORE ", xalign=0)
        brand.get_style_context().add_class("brand")
        self.store_screen.pack_start(brand, False, False, 0)

        self.store_name_entry = Gtk.Entry()
        self.store_name_entry.set_placeholder_text("APP NAME (optional)")
        self.store_name_entry.connect("focus-in-event",
                                      self._store_field_focused)
        self.store_screen.pack_start(self.store_name_entry, False, False, 4)

        self.store_url_entry = Gtk.Entry()
        self.store_url_entry.set_placeholder_text("https://...")
        self.store_url_entry.connect(
            "activate", lambda *_: self.add_app_from_form())
        self.store_url_entry.connect("focus-in-event",
                                     self._store_field_focused)
        self.store_screen.pack_start(self.store_url_entry, False, False, 4)

        self.store_status = Gtk.Label(label=" TYPE A URL AND PRESS ENTER TO ADD ",
                                       xalign=0)
        self.store_status.get_style_context().add_class("status")
        self.store_screen.pack_start(self.store_status, False, False, 4)
        self._create_store_keyboard()

        caption = Gtk.Label(label=" INSTALLED APPS ", xalign=0)
        caption.get_style_context().add_class("hint")
        self.store_screen.pack_start(caption, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.store_listbox = Gtk.ListBox()
        self.store_listbox.set_selection_mode(Gtk.SelectionMode.BROWSE)
        self.store_listbox.connect(
            "row-activated", lambda *_: self.delete_selected_app())
        scroller.add(self.store_listbox)
        self.store_screen.pack_start(scroller, True, True, 0)

        store_hint = Gtk.Label(
            label=" TAB TO THE LIST, UP/DOWN TO CHOOSE, PRESS TO REMOVE   "
                  "HOLD BACK TO LEAVE ",
            xalign=0)
        store_hint.get_style_context().add_class("hint")
        self.store_screen.pack_start(store_hint, False, False, 0)

    def _create_store_keyboard(self):
        """Always available within Store, even when Wayland OSK cannot overlay Xwayland."""
        self._store_keyboard_target = self.store_name_entry
        self.store_keyboard = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        for letters in ("1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"):
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=3)
            row.set_halign(Gtk.Align.CENTER)
            for char in letters:
                button = Gtk.Button(label=char)
                button.set_focus_on_click(False)
                button.set_size_request(45, 40)
                button.connect("clicked", self._store_keyboard_press, char)
                row.pack_start(button, False, False, 0)
            self.store_keyboard.pack_start(row, False, False, 0)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        row.set_halign(Gtk.Align.CENTER)
        for label, value in (("SPACE", " "), ((".", ".")), (("/", "/")),
                             ((":", ":")), (("-", "-")), (("_", "_")),
                             (("@", "@")), (("BACK", "BACK")),
                             (("CLEAR", "CLEAR")), (("ADD APP", "ADD"))):
            button = Gtk.Button(label=label)
            button.set_focus_on_click(False)
            button.connect("clicked", self._store_keyboard_press, value)
            row.pack_start(button, False, False, 0)
        self.store_keyboard.pack_start(row, False, False, 0)
        self.store_screen.pack_start(self.store_keyboard, False, False, 6)

    def _store_field_focused(self, widget, _event):
        self._store_keyboard_target = widget
        set_desktop_keyboard(True)
        return False

    def _store_keyboard_press(self, _button, value):
        if value == "ADD":
            self.add_app_from_form()
            return
        target = self._store_keyboard_target
        if value == "CLEAR":
            target.set_text("")
        elif value == "BACK":
            pos = target.get_position()
            if pos > 0:
                target.delete_text(pos - 1, pos)
                target.set_position(pos - 1)
        else:
            pos = target.get_position()
            target.insert_text(value, pos)
            target.set_position(pos + len(value))
        target.grab_focus()

    def refresh_store_list(self):
        for child in self.store_listbox.get_children():
            self.store_listbox.remove(child)

        apps = load_apps()
        if not apps:
            row = Gtk.ListBoxRow()
            lab = Gtk.Label(label="NO APPS ADDED YET", xalign=0)
            lab.get_style_context().add_class("item-sub")
            row.add(lab)
            row.set_selectable(False)
            self.store_listbox.add(row)
        else:
            for a in apps:
                row = Gtk.ListBoxRow()
                lab = Gtk.Label(
                    label="%s  -  %s" % (a.get("name", "APP"), a.get("url", "")),
                    xalign=0)
                lab.get_style_context().add_class("item")
                lab.set_ellipsize(Pango.EllipsizeMode.END)
                row.add(lab)
                self.store_listbox.add(row)

        self.store_listbox.show_all()
        first = self.store_listbox.get_row_at_index(0)
        if first and first.get_selectable():
            self.store_listbox.select_row(first)

    def add_app_from_form(self):
        name = self.store_name_entry.get_text().strip()
        url = self.store_url_entry.get_text().strip()
        if not url:
            self.store_status.set_text(" ENTER A URL FIRST ")
            return
        if not re.match(r"^https?://", url, re.I):
            url = "https://" + url
        parsed = urllib.parse.urlparse(url)
        if not parsed.netloc:
            self.store_status.set_text(" THAT DOES NOT LOOK LIKE A URL ")
            return
        if not name:
            name = parsed.netloc.upper()

        apps = load_apps()
        apps.append({"name": name, "url": url})
        save_apps(apps)

        self.store_name_entry.set_text("")
        self.store_url_entry.set_text("")
        self.rebuild_home_apps()
        self.refresh_store_list()
        self.store_status.set_text(" ADDED " + name.upper() + " ")
        self.store_name_entry.grab_focus()

    def delete_selected_app(self):
        row = self.store_listbox.get_selected_row()
        if row is None or not row.get_selectable():
            return
        idx = row.get_index()
        apps = load_apps()
        if idx >= len(apps):
            return
        removed = apps.pop(idx)
        save_apps(apps)
        self.rebuild_home_apps()
        self.refresh_store_list()
        self.store_status.set_text(
            " REMOVED " + (removed.get("name") or "APP").upper() + " ")

    # ================================================================
    #  screen switching
    # ================================================================
    def apply_screen(self):
        s = self.screen
        if s not in ("STORE", "WEB"):
            set_desktop_keyboard(False)
        self.home_screen.set_visible(s == "HOME")
        self.sidebar.set_visible(s == "LIVE" and not self.video_full)
        self.right.set_visible(s == "LIVE")
        self.web_box.set_visible(s == "WEB")
        self.store_screen.set_visible(s == "STORE")

        if s == "HOME" and self.home_tiles:
            self.home_tiles[self.home_index].grab_focus()
        elif s == "WEB" and self.webview is not None:
            self.webview.grab_focus()
        elif s == "STORE":
            self.store_name_entry.grab_focus()
        elif s == "LIVE" and not self.video_full:
            row = self.listbox.get_selected_row()
            if row:
                row.grab_focus()

    @staticmethod
    def _move_listbox(listbox, delta):
        row = listbox.get_selected_row()
        idx = row.get_index() if row else 0
        count = len(listbox.get_children())
        if not count:
            return
        new = (idx + delta) % count
        target = listbox.get_row_at_index(new)
        if target:
            listbox.select_row(target)
            target.grab_focus()

    # ---------------- keys ----------------
    def on_key(self, _widget, event):
        key = event.keyval
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK

        # Ctrl+Q is the only way to quit, and needs a keyboard on purpose
        if ctrl and key in (Gdk.KEY_q, Gdk.KEY_Q):
            self.destroy()
            return True

        if key == Gdk.KEY_F11:
            if self.window_full:
                self.unfullscreen()
            else:
                self.fullscreen()
            self.window_full = not self.window_full
            return True

        # The volume knob no longer sends key events at all - the bridge
        # changes the system (PipeWire) volume directly, so it controls
        # whatever speaker is actually connected, not just this app's mpv
        # instance. See rpi_bridge.py.

        # Esc is what the joystick's long press arrives as.
        if key == Gdk.KEY_Escape:
            if self.screen == "HOME":
                pass                      # already home, nothing to do
            elif self.screen == "LIVE":
                if self.keyboard_open:
                    self.close_keyboard()
                elif self.video_full:
                    self.toggle_video_full()
                elif self.player.running:
                    self.player.stop()
                    self.nowplaying.set_text(" NOTHING PLAYING ")
                    self.status.set_text(" STOPPED ")
                else:
                    self.go_home()
            else:                          # WEB or STORE
                self.go_home()
            return True

        # A page handles its own navigation while a web app is showing.
        if self.screen == "WEB":
            return False

        if self.screen == "STORE":
            focused = self.get_focus()
            if focused in (self.store_name_entry, self.store_url_entry):
                return False              # let normal typing happen
            if key in (Gdk.KEY_Up, Gdk.KEY_Down):
                self._move_listbox(
                    self.store_listbox, 1 if key == Gdk.KEY_Down else -1)
                return True
            if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.delete_selected_app()
                return True
            return False

        # "f" toggles full screen, but not while the on-screen keyboard is
        # open (it would hide the very keyboard being used) or while a real
        # keyboard is typing into the search box.
        typing_in_search = self.screen == "LIVE" and self.get_focus() is self.search_entry
        if key in (Gdk.KEY_f, Gdk.KEY_F):
            if self.screen == "LIVE" and self.keyboard_open or typing_in_search:
                pass  # fall through so the letter/OSK-key logic below handles it
            else:
                if self.screen == "LIVE" and self.player.running:
                    self.toggle_video_full()
                return True

        if self.screen == "HOME":
            if key in (Gdk.KEY_Left, Gdk.KEY_Right):
                self.select_home_tile(
                    self.home_index + (1 if key == Gdk.KEY_Right else -1))
                return True
            if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.launch_app(self.home_apps[self.home_index])
                return True
            return False

        if self.screen == "LIVE":
            if self.keyboard_open:
                # The on-screen keyboard owns every key while it is up, so
                # the joystick never needs a physical keyboard to search.
                if key == Gdk.KEY_Up:
                    self.osk_move(-1, 0)
                elif key == Gdk.KEY_Down:
                    self.osk_move(1, 0)
                elif key == Gdk.KEY_Left:
                    self.osk_move(0, -1)
                elif key == Gdk.KEY_Right:
                    self.osk_move(0, 1)
                elif key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                    self.osk_activate()
                return True
            if self.get_focus() is self.search_entry:
                return False              # let normal typing happen
            if key in (Gdk.KEY_Up, Gdk.KEY_Down):
                self._move_listbox(
                    self.listbox, 1 if key == Gdk.KEY_Down else -1)
                return True
            if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                row = self.listbox.get_selected_row()
                if row is not None:
                    self.activate_row(row)
                return True
            return False

        return False

    def on_destroy(self, *_):
        self._closed = True
        set_desktop_keyboard(False)
        if self._volume_timer is not None:
            GLib.source_remove(self._volume_timer)
        self._audio_workers.shutdown(wait=False, cancel_futures=True)
        self._icon_workers.shutdown(wait=False, cancel_futures=True)
        self.player.stop()
        self.osd.dismiss()
        self.osd.destroy()
        Gtk.main_quit()


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PLAYLIST

    screen = Gdk.Screen.get_default()
    if screen is None:
        print("No display found. This app draws a window, so it has to run on")
        print("the Pi's own screen - not over a plain SSH session.")
        print()
        print("  From the Pi:    python3 tv.py")
        print("  From SSH:       DISPLAY=:0 python3 tv.py")
        sys.exit(1)

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    win = TVWindow(path)
    win.show_all()
    win.apply_screen()    # shows Home, hides everything else, to start with
    win.grab_focus()
    play_chime()
    GLib.idle_add(win.resume_playback)
    Gtk.main()


if __name__ == "__main__":
    main()

TV_PY_EOF_9f3

echo "Installing channels.m3u ..."
cat > "$HOME/channels.m3u" <<'CHANNELS_EOF_9f3'
#EXTM3U
# Channels for the retro-TV build. Only streams verified as open are here.
# Logos and group-title categories come from the iptv-org database, or are
# set by hand for channels added outside it (e.g. the Al-Aqila network).
# Type @ + a category in the search bar to filter, e.g. @kids @news
# @sports @islamic @music @movies @series @documentary @culture
# @business @entertainment @family @education @comedy @classic
# @cooking @general

#EXTINF:-1 group-title="Kids" tvg-logo="https://upload.wikimedia.org/wikipedia/en/2/2b/Spacetoon_logo.png",Spacetoon
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-spacetoon/d8382fb9ab4b2307058f12c7ea90db54/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/LTD0jIm.png",Bahrain TV
https://5c7b683162943.streamlock.net/live/ngrp:bahraintvmain_all/playlist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/fBpLsbC.png",Bahrain Sports 1
https://5c7b683162943.streamlock.net/live/ngrp:sportsone_all/playlist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/ZkuZmIo.png",Bahrain Sports 2
https://5c7b683162943.streamlock.net/live/ngrp:bahrainsportstwo_all/playlist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/1omi7p8.png",Oman Sports TV
https://partneta.cdn.mgmlcdn.com/omsport/smil:omsport.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/R1hGX1d.png",KTV Sport
https://kwtspta.cdn.mangomolo.com/sp/smil:sp.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/l4oX0gf.png",KTV Sport Plus
https://kwtsplta.cdn.mangomolo.com/spl/smil:spl.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/GRQTndk.png",Al Saudiya
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-saudi-tv/2ad66056b51fd8c1b624854623112e43/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/9JSQglj.png",SBC
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-sbc/90e09c0c28db26435799b4a14892a167/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/WcRlHQm.png",Al Ekhbariya
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-al-ekhbaria/297b3ef1cd0633ad9cfba7473a686a06/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/sEOjApe.png",Al Saudiya Alaan
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-ksa-now/71ed3aa814c643306c0a8bc4fcc7d17f/index.m3u8
#EXTINF:-1 group-title="Culture" tvg-logo="https://shahid.mbc.net/mediaObject/55f69983-5b4b-47c7-9c25-06ed5ad860a4?height=auto&width=512&croppingPoint=&version=1&type=jpeg",Saudi Thaqafiya
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-thaqafeyyah/28c0d2a20dbf1dc049ce15d3973f494b/index.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://i.imgur.com/hdsrxvX.png",Taha TV
https://stream.starmenajo.com/hls/app/live/ts:fhd.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/er5hOK4.png",Bahrain Quran
https://5c7b683162943.streamlock.net/live/ngrp:bahrainquran_all/playlist.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/cTLj7Yt.png",Aflam
https://shd-amg-fast.edgenextcdn.net/tx001/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/aAGjAoW.png",Al Alam Al Yawm
https://mn-nl.mncdn.com/mekameleen/smil:mekameleentv.smil/chunklist_b928000.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://english.alarabiya.net/.resources/aa-fe-templating/webresources/dist/assets/gfx/logo/en-night-logo.svg",Al Arabiya English
https://live.alarabiya.net/alarabiapublish/english/playlist_dvr.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/De4SEWE.png",Al Hadath
https://av.alarabiya.net/alarabiapublish/alhadath.smil/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/7o4HgrP.png",Al Resalah
https://rotana.hibridcdn.net/rotananet/risala_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 tvg-logo="https://aloula.faulio.com/storage/mediagallery/37/1a/fullhd_399eddcc4305f34f41c7fab24c3518fab5d55d97.png",Al Riyadh Radio
https://live.kwikmotion.com/sbrksariyadhradiolive/srpksariyadhradio/playlist.m3u8
#EXTINF:-1 tvg-logo="https://shahid.mbc.net/mediaObject/61010cbc-91c5-4ce1-94a4-ed40adadb97b",Alkhuzama Radio
https://live.kwikmotion.com/sbrksakhuzamaradiolive/srpkhuzama/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/rtqVAxf.png",Alwesam TV
https://stream.addresses-sat.com/Alwesam/index.m3u8
#EXTINF:-1 group-title="Documentary" tvg-logo="https://i.imgur.com/Czxi7yk.png",Asharq Discovery
https://svs.itworkscdn.net/asharqdiscoverylive/asharqd.smil/playlist_dvr.m3u8
#EXTINF:-1 group-title="Documentary" tvg-logo="https://i.imgur.com/v6VsFEt.png",Asharq Documentary
https://svs.itworkscdn.net/asharqdocumentarylive/asharqdocumentary.smil/playlist_dvr.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/bqRC3sl.png",Asharq News
https://live-news.asharq.com/asharq.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/M6K8cD3.jpeg",Asharq Radio
https://svs.itworkscdn.net/asharqradiovlive/asharqradiov/playlist.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://i.imgur.com/Y2BqP9m.png",Atfal & Mawaheb TV
https://5aafcc5de91f1.streamlock.net/atfal1.com/atfal2/playlist.m3u8
#EXTINF:-1 group-title="Series" tvg-logo="https://i.imgur.com/QtlnZbq.png",Bab Al Hara
https://shd-amg-fast.edgenextcdn.net/tx010/playlist.m3u8
#EXTINF:-1 tvg-logo="https://shahid.mbc.net/mediaObject/4e042cb6-500b-4e4c-a8ca-21a5a7a7a71b",Big Time Plus
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-big-time-plus/924283f994779a311c1389698ff7e736/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://raw.githubusercontent.com/songwenhui239/Songwenhui239/refs/heads/main/Dr%20Pal%20TV.jpeg",Dr Pal TV
https://stream.cisk.tech/drpal/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://shahid.mbc.net/mediaObject/f809d51c-e83d-43c9-8236-78731c2216ad?type=png",Fairuz
https://shd-amg-fast.edgenextcdn.net/tx029/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://aloula.faulio.com/storage/mediagallery/14/da/fullhd_823bc2fe722ede75410492d57fd6c201208b4224.png",Holy Quran Radio
https://live.kwikmotion.com/sbrksaquranradiolive/srpksaquranradio/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/nUlZvSe.png",Iqraa Africa & Europe
https://playlist.fasttvcdn.com/pl/dlkqw1ftuvuuzkcb4pxdcg/Iqraafasttv1/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/HPVsIa4.png",Iqraa Arabic
https://playlist.fasttvcdn.com/pl/dlkqw1ftuvuuzkcb4pxdcg/Iqraafasttv3/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/HPVsIa4.png",Iqraa Quran
https://playlist.fasttvcdn.com/pl/dlkqw1ftuvuuzkcb4pxdcg/Iqraafasttv2/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://aloula.faulio.com/storage/mediagallery/bd/f5/fullhd_527bf54a5adb56ac17f572ac2cd0801304db3baf.png",Jeddah Radio
https://live.kwikmotion.com/sbrksajeddahradiolive/srpksajeddahradio/chunks.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://s3.eu-central-1.amazonaws.com/rotana.website/channels/1688402500.webp",LBC
http://185.9.2.18/chid_327/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.discogs.com/Fk9Bm8gTYJYeVXIJKX-EOGmYQ90sVQPtkIW5ZK4fydo/rs:fit/g:sm/q:90/h:372/w:412/czM6Ly9kaXNjb2dz/LWRhdGFiYXNlLWlt/YWdlcy9MLTE2OTY4/MzMtMTU2ODk0NjI5/MC01Njk2LmpwZWc.jpeg",Majid Al Mohandis
https://shd-amg-fast.edgenextcdn.net/tx019/playlist.m3u8
#EXTINF:-1 group-title="Series" tvg-logo="https://shahid.mbc.net/mediaObject/d089a559-4f41-4def-a786-f98fcfbf0464?height=auto&width=288&croppingPoint=&version=1&type=png",Maraya
https://shd-amg-fast.edgenextcdn.net/tx008/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/mptwwLs.png",MBC Loud
https://radio-loud-fm.mbc.net/radio-loud-fm_1.m3u8
#EXTINF:-1 group-title="Series" tvg-logo="https://media0070.elcinema.com/tvguide/1399_1.png",MBC Masr Drama
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-masr-drama/567b703c19ede6598222de81b0e4508b/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://shahid.mbc.net/mediaObject/c2b6a882-458b-446e-b0fe-f97f7992149a?height=auto&width=144&croppingPoint=&version=1&type=png",MBC Mood
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-mood/78367bf48ccdba501d0d014a10c21031/index.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/lxWdjXG.png",MBC+ Drama
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-plus-drama/e37251ec2aac8f6c98f75cd0fa37cd28/index.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/NIVhISa.png",Movies Action
https://shd-amg-fast.edgenextcdn.net/tx011/playlist.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/JWihdcl.png",Movies Thriller
https://shd-amg-fast.edgenextcdn.net/tx012/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://aloula.faulio.com/storage/mediagallery/0f/c5/fullhd_5da380cdfc304fd7d4672a83aeb6c62bc1d3d3e8.png",Nidae AlIslam Radio
https://live.kwikmotion.com/sbrksanedaradiolive/srpksanedaradio/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/JkDD3bK.png",Panorama FM
https://d6izdil55uftn.cloudfront.net/out/v1/0a06d1d6377c47edbd48721ed724bd08/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://shahid.mbc.net/mediaObject/b98b0635-c8ed-4a7c-9efa-5856e278f54b?type=png",Rabeh Saqer
https://shd-amg-fast.edgenextcdn.net/tx004/playlist.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/pGgp38I.png",Rotana Cinema KSA
https://rotana.hibridcdn.net/rotananet/cinema_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="Classic" tvg-logo="https://i.imgur.com/pMMUvkt.png",Rotana Classic
https://rotana.hibridcdn.net/rotananet/classical_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/nhREk0o.png",Rotana Clip
https://rotana.hibridcdn.net/rotananet/clip_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="Comedy" tvg-logo="https://i.imgur.com/IlT8U6S.png",Rotana Comedy
https://rotana.hibridcdn.net/rotananet/comedy_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="Series" tvg-logo="https://i.imgur.com/btnhPjZ.png",Rotana Drama
https://rotana.hibridcdn.net/rotananet/drama_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/6HMluzv.png",Rotana Khalijia
https://rotana.hibridcdn.net/rotananet/khaleejiya_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/2zFQbQi.png",Rotana Music
https://rotana.hibridcdn.net/rotananet/music_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 tvg-logo="https://aloula.faulio.com/storage/mediagallery/32/f9/fullhd_4c7e170fe0169d36ed17d45a645d4e69fb961793.png",Saudia Radio
https://live.kwikmotion.com/sbrksasaudiaradiolive/srpksasaudiaradio/playlist.m3u8
#EXTINF:-1 group-title="Classic" tvg-logo="https://i.imgur.com/AKa1X9d.png",Thikrayat TV
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-thikrayat/8cfa8fe0c96275735745b89c683b27e3/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/t6Lmntr.png",Bahrain International
https://5c7b683162943.streamlock.net/live/ngrp:bahraininternational_all/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/pHpFGeg.png",Ch4Teen Documentary
https://ch14.tv/live/ch4teendoc/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/kG0d8Ay.png",KTV 1
https://kwtktv1ta.cdn.mangomolo.com/ktv1/smil:ktv1.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/hB57mNh.png",KTV 2
https://kwtktv2ta.cdn.mangomolo.com/ktv2/smil:ktv2.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/naVEZtj.png",KTV Al Qurain
https://kwtktvaqta.cdn.mangomolo.com/ktvaq/smil:tktvaq.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Culture" tvg-logo="https://i.imgur.com/jg3VAxO.png",KTV Arabe
https://kwtktvata.cdn.mangomolo.com/ktva/smil:tktva.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/hqEbc49.png",KTV Ethraa
https://kwtethta.cdn.mangomolo.com/eth/smil:eth.stream.smil/chunklist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/F2PzEaw.png",Marina TV
https://ffs.gulfsat.com/Marina-TV-HD/index.m3u8
#EXTINF:-1 group-title="Entertainment" tvg-logo="https://play-lh.googleusercontent.com/aO-2614npPjbJny21ljgGDRqfixPUG39uLfXwG-xX6fd2y5sxjp_SR6ty92d9l08yt10",Ritmu TV
https://659605a54e9a6.streamlock.net:8443/live/livestream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/2FPtYZr.png",Alistiqama TV
https://jmc-live.ercdn.net/alistiqama/alistiqama.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/YMqWEe4.png",Al Araby TV
https://live.kwikmotion.com/alaraby1live/alaraby_abr/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/Gp5mNea.png",Al Araby TV 2
https://live.kwikmotion.com/alaraby2live/alaraby2.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/miq8O1Q.png",Al Jazeera 2
https://live-hls-web-aja2-gcp.thehlive.com/AJA2/index.m3u8
#EXTINF:-1 group-title="Documentary" tvg-logo="https://i.imgur.com/5dNJlLo.png",Al Jazeera Documentary
https://live-hls-apps-ajd-fa.getaj.net/AJD/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/DfJI4t5.png",Al Jazeera Mubasher
https://live-hls-apps-ajm-fa.getaj.net/AJM/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/DfJI4t5.png",Al Jazeera Mubasher 24
https://live-hls-apps-ajm24-fa.getaj.net/AJM24/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/DfJI4t5.png",Al Jazeera Mubasher Broadcast 2
https://live-hls-apps-ajm2-fa.getaj.net/AJM2/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/QFnztgo.png",Al Maaref TV
https://bucharest.zeuscdn724.com/lb0/CH-AL-MA/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/4qB5iN0.png",Al Rayyan Old TV
https://alrayyancdn.vidgyor.com/pub-nooldraybinbdh/liveabr/playlist_dvr.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/Ts3RjTV.png",Al Rayyan TV
https://alrayyancdn.vidgyor.com/pub-noalrayy3pwz0l/liveabr/playlist_dvr.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/N5RB4sp.png",Qatar Television
https://live.kwikmotion.com/qtv1live/qtv1.smil/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/iWJxDUm.png",Qatar Television 2
https://live.kwikmotion.com/qtv2live/qtv2.smil/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://www.qmc.qa/img/LiveChannels/1ca67a44-9290-4b2a-8a16-d8c6e2260816.jpg",Qatar TV The Holy Quran
https://qatartv.akamaized.net/hls/live/20000612/qtvquran/master.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://www.qbc.news/_next/static/media/logo.0~2x9wpd284~a.svg",QBC
https://googlecdn1.alkassdigital.net/livestream/qbc4/main.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/hVNIwgE.png",Ajman TV
https://cdn1.logichost.in/ajmantv/live/playlist.m3u8
#EXTINF:-1 group-title="Business" tvg-logo="https://i.imgur.com/eEV4r6J.jpg",Al Arabiya Business
https://live.alarabiya.net/alarabiapublish/aswaaq.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/Hoc3cfO.png",Al Arabiya Programs
https://live.alarabiya.net/alarabiapublish/aaprograms.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/zkBT0C8.png",Al Qamar TV
https://streamer3.premio.link/alqamar/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/otAHLRo.png",Al Shallal TV
https://amg01480-alshallalfze-alshallal-ono-q0hfg.amagi.tv/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/m4qheI4.png",Al Sharqiya Min Kabla
https://svs.itworkscdn.net/kablatvlive/kabtv1.smil/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/zgMqQPQ.png",Al Wousta TV
https://svs.itworkscdn.net/alwoustalive/alwoustatv.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/rBixF3P.png",Al Yaum TV
https://hlspackager.akamaized.net/live/DB/ALYAUM_TV/HLS/ALYAUM_TV.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/NXFkYFj.png",Alarabiya
https://live.alarabiya.net/alarabiapublish/alarabiya.smil/playlist.m3u8
#EXTINF:-1 group-title="Business" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/e/ea/CNBC_Arabia_2025.svg",CNBC Arabiya
https://cnbc-live.akamaized.net/cnbc/master.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/UMmbyHv.png",Dubai TV International
http://185.9.2.18/chid_139/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/CiA3plN.png",MBC 1
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-1/15cf99af5de54063fdabfefe66adc075/index.m3u8
#EXTINF:-1 group-title="Entertainment" tvg-logo="https://i.imgur.com/BcXASJp.png",MBC 4
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-4/24f134f1cd63db9346439e96b86ca6ed/index.m3u8
#EXTINF:-1 group-title="Family" tvg-logo="https://i.imgur.com/fRWaDyF.png",MBC 5
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-5/ee6b000cee0629411b666ab26cb13e9b/index.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/TTAGFHG.png",MBC Bollywood
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-bollywood/546eb40d7dcf9a209255dd2496903764/index.m3u8
#EXTINF:-1 group-title="Entertainment" tvg-logo="https://i.imgur.com/g5PWnqp.png",MBC Drama
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-drama/2c28a458e2f3253e678b07ac7d13fe71/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/lF8UxvR.png",MBC FM
https://dbbv9umqcd7cs.cloudfront.net/out/v1/db15b75c3cc0400c91961468d6a232ac/index.m3u8
#EXTINF:-1 group-title="Entertainment" tvg-logo="https://i.imgur.com/4FXiyjn.png",MBC Persia
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-persia/818ee8e4b592dc497608f066d825bfb4/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://upload.wikimedia.org/wikipedia/en/8/8c/Nourtv_logo.jpg",Nour TV
https://cdn.bestream.io:19360/elfaro4/elfaro4.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/1ztVXUi.png",Peace TV Bangla
https://dzkyvlfyge.erbvr.com/PeaceTvBangla/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://github.com/fawazahmed0/tiger/raw/master/peace/chinese.jpg",Peace TV Chinese
https://dzkyvlfyge.erbvr.com/PeaceTvChinese/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/rjgCM2B.png",Peace TV English
https://dzkyvlfyge.erbvr.com/PeaceTvEnglish/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://github.com/fawazahmed0/tiger/raw/master/peace/urdu.jpg",Peace TV Urdu
https://dzkyvlfyge.erbvr.com/PeaceTvUrdu/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/AbrHI7K.png",PMC
https://pmchls.wns.live/hls/stream.m3u8
#EXTINF:-1 group-title="Music",PMC Royale
https://pmcrohls.wns.live/hls/stream.m3u8
#EXTINF:-1 tvg-logo="https://maraya.faulio.com/storage/mediagallery/60/26/fullhd_d5c3c81b0562a76bc63f073a5e0947f309b0215b.png",Pulse95 Radio
https://svs.itworkscdn.net/pulse95live/pulse96/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Wd3Xvd1.png",Sharjah 2
https://svs.itworkscdn.net/smc2live/smc2tv.smil/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/q7GGALe.png",Sharjah Radio
https://svs.itworkscdn.net/smcradiolive/smcradiolive/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/MxZlOvc.png",Sharjah Radio Quran
https://live.kwikmotion.com/smcquranlive/quranradiolive/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Oz2bPOt.png",Sharjah TV
https://live.kwikmotion.com/smc1live/smc1tv.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/SvjU4h6.png",Sky News Arabia
https://live-stream.skynewsarabia.com/c-horizontal-channel/horizontal-stream/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/FjtzQQs.png",Sky News Arabia Vertical
https://live-stream.skynewsarabia.com/c-vertical-channel/vertical-stream/index.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://upload.wikimedia.org/wikipedia/en/2/2b/Spacetoon_logo.png",Spacetoon Arabic
https://live-uae-next.spacetoongo.com/ST_MENA_NEXT/hls/r9p2hjipmw2kl.m3u8
#EXTINF:-1 tvg-logo="https://maraya.faulio.com/storage/mediagallery/33/d7/fullhd_b25ca838c984b6ee2a9a254560f1e7bc1b04aa33.png",Watar Radio
https://svs.itworkscdn.net/smcwatarlive/smcwatar/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/WhPlJzh.jpeg",ABNsat
https://mediaserver.abnvideos.com/streams/abnsat.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://afarin.tv/images/baxcha.png",Afarin Baxcha
https://5dcabf026b188.streamlock.net/afarinTV/livestream/playlist.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://i.imgur.com/6MnXD7g.png",Afarin TV
https://65f16f0fdfc51.streamlock.net/afarinTV/livestream/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/8qQouTW.jpg",Al Iraqia
https://imn-live.esite-lab.com/hls/iraqia-general.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/DrrlxTO.png",Al Iraqia Sport
https://imn-live.esite-lab.com/hls/iraqia-sports-1.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/rxDh6W1.png",Al Janoub TV
https://live.alissahost.net/hls/test.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/ltyRjPK.png",Al Rasheed TV
https://media1.livaat.com/static/AL-RASHEED-HD/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/mJIG5IV.png",Al Sharqiya
http://185.9.2.18/chid_144/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/PeAcXB9.png",Al Sharqiya News
https://5d94523502c2d.streamlock.net/alsharqiyalive/mystream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Eo3UYCK.png",Al-Jawadain TV
https://live.aljawadain.org/live/aljawadaintv/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://gitlab.com/alabbassia-tv/alabbassia-tv-source/-/raw/main/Logo_PNG.png",Alabbassia TV
https://stream.alabbassia.com/live/alabbassia/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/3Kv0t3X.png",Alawla TV
https://live.alawla.tv/hls/stream.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/YPj6kXq.png",Alghadeer TV
https://sd343444.vodu.store:3356/live/Alghadeer/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/lqVwrAF.png",Alquran
https://ktvlive.online/stream/hls/ch1.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/sseqFsO.png",Amozhgary TV
https://app-live.org/live/3268334b/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/JazFBkW.jpeg",Avar TV
https://avr.host247.net/live/AvarTv/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/s8PfUQy.png",BeitolAbbas TV Channel
https://live.beitolabbas.tv/live/beitolabbastv.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/thumb/4/40/Channel8corp.png/960px-Channel8corp.png",Channel8
https://live.channel8.com/Channel8-Kurdish/index.fmp4.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/kyzH3G5.png",Dijlah TV
https://ghaasiflu.online/Dijlah/index.m3u8
#EXTINF:-1 group-title="Family" tvg-logo="https://i.imgur.com/QmgaPSi.png",EmanTv
https://avr.host247.net/live/emantv/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/x4KCQlH.png",FarmodaTV
https://avr.host247.net/live/FarmodaTV/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/9lOuzHQ.png",I News
https://live.i-news.tv/hls/stream.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/pDdUvz7.png",Imam Hussein TV 1
https://live.imamhossaintv.com/live/ih1.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/IXVSPdJ.png",Imam Hussein TV 2
https://live.imamhossaintv.com/live/ih2.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/emQRHQZ.png",Imam Hussein TV 3
https://live.imamhossaintv.com/live/ih3.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/0UYcylY.png",Imam Hussein TV 4
https://live.imamhossaintv.com/live/ih4.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Oq2Ve7C.png",Imam Hussein TV 5
http://live.al-zahratv.com/live/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/lqhU0PY.png",Imam Hussein TV 6
http://live.imamhossaintv.com/live/ih6.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/Z7woTe5.png",Iraq Future
https://viewmedia7219.bozztv.com/wmedia/viewmedia100/web_040/Stream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/qzApokm.png",Ishtar TV
https://stream.ishtartv.com/live/iShtarHD/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://www.karbala-tv.iq/documentary/static/img/logo.png",Karbala Documentary
https://ktvlive.online/stream/hls/ch3.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/xPwzad9.png",Kurd Channel
https://kurdchhls.wns.live/hls/stream.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/9QWs2ms.png",Kurdistan 24
https://hlspackager.akamaized.net/live/DB/K24/HLS/K24.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/mjQptpc.png",Kurdistan TV
https://5a3ed7a72ed4b.streamlock.net/live/SMIL:myStream.smil/playlist.m3u8
#EXTINF:-1 group-title="Entertainment" tvg-logo="https://i.imgur.com/UAbSwYA.png",Kurdsat
https://hlspackager.akamaized.net/live/DB/KURDSAT_HD/HLS/KURDSAT_HD.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/F3XRwkt.png",Kurdsat News
https://hlspackager.akamaized.net/live/DB/KURDSAT_NEWS/HLS/KURDSAT_NEWS.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/voyoljW.png",Manu Chat
https://vmi747311.contaboserver.net/hls/livetv.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/LsYYkUI.png",Marjaeyat TV Arabic
https://livefa.marjaeyattv.com/mtv_ar/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Dvf61Jp.png",Marjaeyat TV English
https://livefa.marjaeyattv.com/mtv_en/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/fCj05f0.png",Marjaeyat TV Persian
https://livefa.marjaeyattv.com/mtv_fa/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/D0LxiPE.png",MBC Iraq
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-iraq/e38c44b1b43474e1c39cb5b90203691e/index.m3u8
#EXTINF:-1 group-title="Family" tvg-logo="https://i.imgur.com/WHeH5i7.png",Mixkurdy
https://avr.host247.net/live/Mix-kurdy/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/qySEibb.png",Payam TV
https://hlspackager.akamaized.net/live/DB/PAYAM_TV/HLS/PAYAM_TV.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/Zo3IWOn.png",Rudaw TV
https://hlspackager.akamaized.net/live/DB/RUDAW/HLS/RUDAW.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/7uQoIXi.png",Samarra TV
https://live.bradosti.net/live/samaraweb_playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://www.semakurd.net/sites/default/files/imagecache/400xY/shemis-tv.jpg",Shams TV
https://stream.shams.tv/hls/stream.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/rK0y02d.png",Waar TV
https://hlspackager.akamaized.net/live/DB/WAAR_HD/HLS/WAAR_HD.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/9Mspf32.png",Zagros TV
https://5a3ed7a72ed4b.streamlock.net/zagrostv/SMIL:myStream.smil/playlist.m3u8
#EXTINF:-1 group-title="News",Alhaqeqa Aldawlia
https://ghaasiflu.online/alhqeqa/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/YTyCBvB.png",Altaghier TV
https://jmc-live.ercdn.net/altaghier/altaghier.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/5l7kw0b.png",Amman TV
https://ammantv-live.ercdn.net/ammantvhd/ammantvhd.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/8UrCl4k.png",Jordan Archive
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/Archive/playlist.m3u8
#EXTINF:-1 group-title="Comedy" tvg-logo="https://i.imgur.com/DuwwoO2.png",Jordan Comedy
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/Comedy/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/gvIAEsJ.png",Jordan Drama
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/Drama/playlist.m3u8
#EXTINF:-1 group-title="Cooking" tvg-logo="https://i.imgur.com/B45qcQX.png",Jordan Kitchen
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/cooking/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/1DE7Gmw.png",Jordan Songs
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/Song/playlist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/2EmrZPQ.png",Jordan Sport
https://jrtv-live.ercdn.net/jordansporthd/jordansporthd.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/gpeIoU9.png",Jordan Tourism
https://playlist.fasttvcdn.com/pl/cc0blorawy1ibohhrupraa/Tourism/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/0XozB5N.png",Jordan TV
https://jrtv-live.ercdn.net/jordanhd/jordanhd.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/J8omcNz.png",Melody FM
https://cdn3.wowza.com/1/OVRrOWxXUEswS2Yv/eGVxSWZy/hls/live/playlist.m3u8
#EXTINF:-1 tvg-logo="https://cdn-profiles.tunein.com/s142626/images/logod.jpg",Radio Fann Jordan Studio
http://45.63.116.205/hls2/stream1.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/wHOQU0R.png",Radio Yaqeen Jordan City View
http://45.63.116.205/hls4/stream1.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/xGDjlp5.png",Rotana Radio Jordan Studio
http://45.63.116.205/hls/stream1.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/NjgOBts.png",Rotana Tarab Jordan City View
http://45.63.116.205/hls3/stream1.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/WX80rty.png",Roya TV
https://live.kwikmotion.com/royatvpublic/royatv.smil/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/o6HSfNg.png",Aghani Aghani TV
https://cdn.streamlane.tv/hls/aghanitv/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/QMUjPXx.png",Al Ittihad TV
http://185.105.4.151:8080/_defapp_/ittihad/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/CfxR8o3.png",Al Jadeed
http://185.9.2.18/chid_391/mono.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/sOQLV7L.png",Al-Manar
https://edge.fastpublish.me/live/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/1vqhmNz.png",ALWifak News TV
http://alwifaklive.info:1935/live/myStream/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/sTOoDy1.png",Arabica TV
http://istream.binarywaves.com:8081/hls/arabica/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/U9z8WBY.png",Charity TV
https://652930de05533.streamlock.net/live/ngrp:livestream_all/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/xPoycVY.png",Lana TV
https://cdn.streamlane.tv/hls/ltv/master.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/h26xtUv.png",LBC International
http://185.9.2.18/chid_521/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://www.mtv.com.lb/images/header/mfm-logo.svg",mfm
https://hms.pfs.gdn/hms/v1/broadcast/hlmvmp2hfriode891/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://upload.wikimedia.org/wikipedia/commons/7/75/Murr_tv.png",MTV Lebanon
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mtv-lebanon/b8ebb2a5affb812f1541712adde10e26/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/dF4Mvts.png",Nour Al Koddass
https://svs.itworkscdn.net/nour1satlive/livestream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/EEy2dUr.png",Nour Al Sharq
https://svs.itworkscdn.net/nour8satlive/livestream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/6Zs5rx4.png",Noursat
https://svs.itworkscdn.net/nour4satlive/livestream/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/RC5Kw82.png",Noursat English
https://svs.itworkscdn.net/noursatenglive/noursateng.smil/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/O4DuR9G.png",One TV
https://hms.pfs.gdn/v1/broadcast/one/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.ibb.co/Vp2G9wTz/onefmlb.png",OneFM
https://hms.pfs.gdn/v1/broadcast/onefm/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/toxFMeY.png",OTV
https://otv.hibridcdn.net/otv/tv_abr/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/n8dSgx4.png",Palestine Al Yawm
https://live.paltodaytv.com/paltv/live/playlist_sfm4s.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/bWwY885.png",Red TV Lebanon
https://live.kwikmotion.com/redtvlive/redtv.smil/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/hnTx8eK.png",Senses TV
http://31.14.41.69:8080/hls/sensesonline/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/5VPYxJi.png",Tele Liban
https://cdn.catiacast.video/abr/ed8f807e2548db4507d2a6f4ba0c4a06/playlist.m3u8
#EXTINF:-1 group-title="News",UNews
https://cdn.catiacast.video/abr/9436b5ab3c1171ab04a59af11951292f/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/f8WcqRY.png",Voice of Lebanon
https://svs.itworkscdn.net/vdltvlive/vdltv.smil/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://upload.wikimedia.org/wikipedia/en/e/eb/AghapyTV.jpg",Aghapy TV
https://5b622f07944df.streamlock.net/aghapy.tv/aghapy.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/ga6NXb9.png",Al Ghad TV
https://eazyvwqssi.erbvr.com/alghadtv/alghadtv.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/wTeOM2J.png",Al Masriyah
http://185.9.2.18/chid_247/index.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://www.ctvchannel.tv/images/CTV-logo-white.png",Coptic TV
https://ctv.icopts.app/CTV/index.fmp4.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://www.9090.fm/images/logo.png",El Radio 9090 FM
https://9090video.mobtada.com/hls/stream.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/1UUjU26.png",Huda TV
https://cdn.bestream.io:19360/elfaro1/elfaro1.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://i.imgur.com/zojMTP9.png",Koogi TV
https://5d658d7e9f562.streamlock.net/koogi.tv/koogi.smil/playlist.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/P7PUHIx.png",Mazzika
http://149.100.11.235:8080/Mazzika/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/CiA3plN.png",MBC 1 Egypt
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-1-na/eec141533c90dd34722c503a296dd0d8/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/o2elx0u.png",MBC Masr
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-masr/956eac069c78a35d47245db6cdbb1575/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/KHo7Gtn.png",MBC Masr 2
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-mbc-masr-2/754931856515075b0aabf0e583495c68/index.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/1ENdbZn.png",Mix Hollywood
https://ml-pull-hwc.myco.io/MixTV/hls/index.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/krp3kgv.png",NogoumFMTV
https://nogoumtv.nrpstream.com/hls/stream.m3u8
#EXTINF:-1 group-title="Movies" tvg-logo="https://i.imgur.com/dGlKoLW.png",Rotana Cinema Egypt
https://rotana.hibridcdn.net/rotananet/cinemamasr_net-7Y83PP5adWixDF93/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/pZyKaUH.png",Watan TV
https://rp.tactivemedia.com/watantv_source/live/playlist.m3u8
#EXTINF:-1 group-title="Family" tvg-logo="https://i.imgur.com/8FILgXT.jpeg",Al-Souriya TV
https://shd-gcp-live.edgenextcdn.net/live/bitmovin-al-souriya-tv/e3150760fa5fd62776225433b8c3d406/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://alikhbariah.com/wp-content/themes/alekhbariah-custom-theme/img/logo.webp",Alikhbaria Syria
http://185.9.2.18/chid_423/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://www.althania.tv/themes/custom/althania/assets/images/stv-logo.svg",Althania
https://live.kwikmotion.com/syriatv02live/syriatv02.smil/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://pbs.twimg.com/profile_images/1779495135841075200/aPINrLwe_400x400.png",Halab Today TV
https://halabtoday-live.lg.mncdn.com/halabtoday/livestream/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/42noysO.png",Rojava TV
https://hlspackager.akamaized.net/live/DB/ROJAVA_HD/HLS/ROJAVA_HD.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/JSvJpD8.png",Ronahi TV
https://hlspackager.akamaized.net/live/DB/RONAHI_TV/HLS/RONAHI_TV.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/FjuVuXF.jpeg",Syria TV
https://live.kwikmotion.com/syriatvlive/syriatv.smil/playlist_dvr.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://avatars.githubusercontent.com/u/213803648?s=400&u=e27c09d39f813b9698de9c6559cbf7f196bf6fce&v=4",Welat TV
https://stream.badinan.xyz/welat/tv/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/i6Y7beR.jpg",Ajyal TV
http://htvajyal.mada.ps:8888/ajyal/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/NVOeM3P.png",Al Madina
https://streaming.zaytonatube.com:8081/AlMadinatv/almadina21/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/c2bwn4G.png",Al Najah News
https://streaming.najah.edu:8443/hls/AlNajah.m3u8
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/6B3Cims.png",Falastini TV
https://rp.tactivemedia.com/palestiniantv_source/live/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/hRFa03k.png",Ma'an TV
https://htvmada.mada.ps:4443/maannews/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/GB2Q9kl.png",Musawa Channel
https://pbc.furrera.ps/musawahd/index.m3u8
#EXTINF:-1 group-title="Education" tvg-logo="https://i.imgur.com/AwVHXyC.png",Palestine Edu
https://pbc.furrera.ps/PalestineEDU/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/68llVTZ.png",Palestine Mubasher
https://pbc.furrera.ps/palestinelivehd/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/4B5FvmX.png",Palestine Satellite Channel
https://pbc.furrera.ps/palestinehd/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/BS8XXug.png",Palestine Today
https://live.paltodaytv.com/paltv/live/playlist.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/6Cx22ya.png",Rajeen TV
https://mn-nl.mncdn.com/palabroad/live/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/1d25a9Q.png",Seraj TV
https://43869de4e1a0d641.servers.dvcloud.tv/hls/al_aqsa_channel/6udfi7v8a3eof6nlps6e9ovfrs65c7l7.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/4Cyz4Bn.png",Shabab FM
https://streaming.zaytonatube.com:8081/ShababFM/shabab/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/jdr22Sk.jpeg",Watar TV
http://htvint.mada.ps:8889/orient/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/sf2A9vT.png",Wattan TV
https://htvmada.mada.ps:4443/wattan/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/V055t5e.png",Al Masirah
https://live.cdnbridge.tv/Almasirah/Almasirah_all/playlist.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/0xHb3XM.jpg",Al Masirah Mubacher
https://live2.cdnbridge.tv/AlmasirahMubasher/Mubasher_All/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/UVndAta.png",Al-Sahat TV
https://assahat.b-cdn.net/Assahat/assahatobs/index.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/8TzcJu5.png",Yemen Today TV
https://video.yementdy.tv/hls/yementoday.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://play-lh.googleusercontent.com/FHPrsr391mPFqKfTq6ZdvWPZNVfsZeTAVQ8rjQF-NosnRdNipUy5xa43RWkiF4tGcQU",Al Masar TV
https://starmenajo.com/hls/almasar/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/KSUny9D.jpeg",Libya Al Wataniya
https://cdn-globecast.akamaized.net/live/eds/libya_al_watanya/hls_roku/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/iBAhM2v.png",Tanasuh TV
https://kilolink.pulsarstarsolutions.com/live/smil:tanasuhtv.smil/manifest.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/f9pL2NE.png",Wasat TV
https://alwasattv.hibridcdn.net/alwasattv/alwasat_abr/playlist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/gNr2V14.png",El Watania 1
https://sw1.tanitweb.net/TunisiaTV/_definst_/watania1/chunklist.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/kgkrD3V.png",El Watania 2
https://sw1.tanitweb.net/TunisiaTV/_definst_/watania2/playlist.m3u8?DVR
#EXTINF:-1 group-title="Music" tvg-logo="https://i.imgur.com/GDUykah.png",Mosaique FM
https://webcam.mosaiquefm.net/mosatv/_definst_/studio/playlist.m3u8?DVR
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/vyVEXYL.png",AL24 News
https://cdn.live.easybroadcast.io/abr_corp/66_al24_u4yga6h/corp/66_al24_u4yga6h_240p/chunks.m3u8
#EXTINF:-1 group-title="Kids" tvg-logo="https://i.imgur.com/L8UPGPC.png",Amou Yazid TV
http://mkstream.servehttp.com:1940/AmouYazid/ay1/playlist.m3u8
#EXTINF:-1 group-title="Islamic" tvg-logo="https://i.imgur.com/Ki3ySUE.png",CNA
https://live.creacast.com/cna/stream/playlist.m3u8
#EXTINF:-1 group-title="Sports" tvg-logo="https://i.imgur.com/cDkIDIA.png",El-Heddaf TV
https://live.elheddaftv.com:8081/elheddaftv/index.m3u8
#EXTINF:-1 group-title="General" tvg-logo="https://i.imgur.com/VEb631f.png",TV2
http://185.9.2.18/chid_347/index.m3u8
#EXTINF:-1 group-title="Education" tvg-logo="https://i.imgur.com/40rR4hD.png",TV7
http://185.9.2.18/chid_352/index.m3u8
#EXTINF:-1 group-title="News" tvg-logo="https://i.imgur.com/BH1N6TA.png",Dabanga TV
https://hls.dabangasudan.org/hls/stream.m3u8
#EXTINF:-1 tvg-logo="https://i.imgur.com/XUPAYAA.png",Sudan TV
https://cdn-globecast.akamaized.net/live/eds/sudan_tv/hls_roku/index.m3u8
#EXTINF:-1 group-title="Islamic",Al-Aqila TV
https://www.youtube.com/channel/UCin5m2zcyjogTCbvyetPP2Q/live
#EXTINF:-1 group-title="Islamic",Umm Al-Baneen TV
https://www.youtube.com/channel/UC8wkX3D5Jnq1oHecGFFHXqg/live
#EXTINF:-1 group-title="Islamic",Saout Al-Aqila TV
https://www.youtube.com/channel/UCc2DU9zpuUH-zgwKLYvIYMg/live
CHANNELS_EOF_9f3

echo "Installing chime.wav ..."
base64 -d <<'CHIME_B64_EOF_9f3' > "$HOME/chime.wav"
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
BP3k/8QCeQXXB74JGgvlCyUM7QtYC4QKjwmTCKMHyAYGBlgFswQOBF4DnQLJAeYA+v8N/yv+WP2Y
/On7Rfug+vH5LvlT+GL3Z/Zz9aP0E/Ti8yr0/PRg9k34sPpm/UUAIQPLBRkI7Qk1C+wLGwzVCzYL
XQpmCWwIfgeoBukFPQWaBPQDQwOAAqsBxgDa/+/+D/4//YP81vsz+4763vkY+Tr4SPdN9l31lPQQ
9O3zR/Qs9aH2nvgM+8j9pwB9AxoGWAgZCkwL8AsODLsLFAs1Cj4JRQhbB4gGzQUjBYEE2wMoA2MC
jAGmALv/0v4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAA=
CHIME_B64_EOF_9f3

echo
echo "Done. Installed to:"
echo "  $HOME/tv.py"
echo "  $HOME/channels.m3u"
echo "  $HOME/chime.wav"
echo
echo "Run it with:"
echo "  python3 $HOME/tv.py"

