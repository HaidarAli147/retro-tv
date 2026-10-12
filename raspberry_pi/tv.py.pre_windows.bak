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
import urllib.parse
import urllib.request

# mpv is embedded via an X11 window id, so run under X11 (Xwayland is fine).
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
# Cap which quality is taken from an adaptive stream, in bits per second.
# 2.5 Mbps lands on the 720p feed of most channels.
HLS_MAX_BITRATE = 2500000
TOD_URL = "https://tod.tv"
# Web apps serve their normal site, so present as an ordinary desktop browser.
WEB_USER_AGENT = (
    "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
            ["mpv", "--no-video", "--really-quiet",
             "--ao=%s" % AUDIO_OUTPUT_DRIVER, CHIME],
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
AUDIO_OUTPUT_DRIVER = "pipewire"

SEGMENTS = 16          # blocks in the volume bar
START_VOLUME = 70      # where the app starts, 0 - 100
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

    def show_level(self, level, muted=False):
        """level is 0.0 - 1.0."""
        lit = 0 if muted else int(round(level * SEGMENTS))
        for i, seg in enumerate(self.segments):
            ctx = seg.get_style_context()
            ctx.remove_class("seg-on" if i >= lit else "seg-off")
            ctx.add_class("seg-on" if i < lit else "seg-off")
        self.caption.set_text(
            "MUTED" if muted else "VOLUME  %d%%" % int(round(level * 100)))

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


class Player:
    """One mpv process drawing into our video area.

    Volume is mpv's own, not the system's. Changing the system volume makes
    the desktop pop up its own indicator, which we do not want over the top
    of this app.
    """

    SOCKET = "/tmp/tv-mpv.sock"

    def __init__(self):
        self.proc = None

    def _ipc(self, payload):
        """Fire a command at the running mpv. Returns True if it landed."""
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.4)
            s.connect(self.SOCKET)
            s.sendall((json.dumps(payload) + "\n").encode())
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
        try:
            os.unlink(self.SOCKET)
        except OSError:
            pass
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
            # Zero-copy V4L2 decoding straight into EGL.
            "--hwdec=v4l2m2m", "--vo=gpu", "--gpu-context=x11egl",
            "--hls-bitrate=%d" % HLS_MAX_BITRATE,
            "--ao=%s" % AUDIO_OUTPUT_DRIVER,
            # Our own volume, and a socket so we can change it while playing
            "--volume=%d" % volume,
            "--mute=%s" % ("yes" if muted else "no"),
            "--input-ipc-server=%s" % self.SOCKET,
            url,
        ])

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None

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
        self.search_row = None
        self.keyboard_open = False
        self.osk_row, self.osk_col = 1, 0
        self.osk_widgets = []
        self.home_apps = []
        self.home_tiles = []
        self.home_index = 0

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

            name_lab = Gtk.Label(label=app["name"].upper())
            name_lab.get_style_context().add_class("tile-name")
            name_lab.set_ellipsize(Pango.EllipsizeMode.END)
            name_lab.set_max_width_chars(15)
            tile.pack_start(name_lab, False, False, 0)

            self.home_tile_box.pack_start(tile, False, False, 0)
            self.home_tiles.append(tile)

        self.home_tile_box.show_all()
        self.select_home_tile(self.home_index)

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
        self.displayed = items

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
        """Fetch logos off the main thread so the list appears immediately."""
        slots = list(self.logo_slots)

        def worker():
            for img, url in slots:
                if not url:
                    continue
                path = cached_logo(url)
                if path:
                    GLib.idle_add(self._set_logo, img, path)

        threading.Thread(target=worker, daemon=True).start()

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
            xid = win.get_xid()
        except AttributeError:
            self.status.set_text(" NEEDS X11: GDK_BACKEND=x11 python3 tv.py ")
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
        self.osd.show_level(self.volume / 100.0, muted=self.muted)

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
            self.web_box.pack_start(self.webview, True, True, 0)
        else:
            notice = Gtk.Label(
                label="WEB APPS NEED WEBKIT.\n\n"
                      "sudo apt install -y gir1.2-webkit2-4.1\n\n"
                      "THEN RESTART THIS APP.",
                xalign=0)
            notice.get_style_context().add_class("notice")
            self.web_box.pack_start(notice, True, True, 0)

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
        self.store_screen.pack_start(self.store_name_entry, False, False, 4)

        self.store_url_entry = Gtk.Entry()
        self.store_url_entry.set_placeholder_text("https://...")
        self.store_url_entry.connect(
            "activate", lambda *_: self.add_app_from_form())
        self.store_screen.pack_start(self.store_url_entry, False, False, 4)

        self.store_status = Gtk.Label(label=" TYPE A URL AND PRESS ENTER TO ADD ",
                                       xalign=0)
        self.store_status.get_style_context().add_class("status")
        self.store_screen.pack_start(self.store_status, False, False, 4)

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
        self.player.stop()
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
