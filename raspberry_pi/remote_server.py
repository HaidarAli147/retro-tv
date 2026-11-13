#!/usr/bin/env python3
"""Phone remote for Retro TV.

tv.py starts this in a background thread. It serves remote_page.html to
phones on the same Wi-Fi and turns their button presses into real key
presses, mouse movement and volume changes on the Pi.

How a phone gets control:
    1. tv.py shows a QR code: http://<pi-ip>:<port>/#code=123456
    2. The page sends the 6-digit code to POST /api/pair and gets a token.
    3. Every command (POST /api/cmd) must carry that token.

Safety rules:
    - Runs as the normal desktop user, never root.
    - Only answers phones with a local-network address (192.168.x.x etc.).
    - The code changes every time tv.py starts; 5 wrong codes per minute
      from one phone locks that phone out for the rest of the minute, and
      20 wrong codes from any phones in a minute makes a brand-new code.
    - No power/shutdown command exists here on purpose.
    - Does not use or change rpi_bridge.py: it makes its own virtual
      keyboard and mouse, so the Arduino controls keep working alongside.
"""
import ipaddress
import json
import logging
import os
import secrets
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

log = logging.getLogger("remote_server")

PAGE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "remote_page.html")
DEFAULT_PORTS = range(8080, 8090)
MAX_BODY = 4096
MAX_TEXT = 200
MAX_DELTA = 200
WRONG_LIMIT = 5          # wrong codes allowed per phone ...
WRONG_WINDOW = 60.0      # ... in this many seconds
GLOBAL_WRONG_LIMIT = 20  # wrong codes from ALL phones per window -> new code
HANDLER_TIMEOUT = 10     # seconds a phone connection may sit idle
MAX_TOKENS = 20

# Button name on the phone -> evdev key name (same keys as the Arduino bridge).
KEY_NAMES = {
    "UP": "KEY_UP",
    "DOWN": "KEY_DOWN",
    "LEFT": "KEY_LEFT",
    "RIGHT": "KEY_RIGHT",
    "ENTER": "KEY_ENTER",
    "BACK": "KEY_ESC",
    "BACKSPACE": "KEY_BACKSPACE",
}

# Characters typed without Shift on a US keyboard layout.
_PLAIN = {
    " ": "KEY_SPACE", "-": "KEY_MINUS", "=": "KEY_EQUAL",
    "[": "KEY_LEFTBRACE", "]": "KEY_RIGHTBRACE", "\\": "KEY_BACKSLASH",
    ";": "KEY_SEMICOLON", "'": "KEY_APOSTROPHE", "`": "KEY_GRAVE",
    ",": "KEY_COMMA", ".": "KEY_DOT", "/": "KEY_SLASH",
}
# Characters that need Shift, and the key they share.
_SHIFTED = {
    "!": "KEY_1", "@": "KEY_2", "#": "KEY_3", "$": "KEY_4", "%": "KEY_5",
    "^": "KEY_6", "&": "KEY_7", "*": "KEY_8", "(": "KEY_9", ")": "KEY_0",
    "_": "KEY_MINUS", "+": "KEY_EQUAL", "{": "KEY_LEFTBRACE",
    "}": "KEY_RIGHTBRACE", "|": "KEY_BACKSLASH", ":": "KEY_SEMICOLON",
    '"': "KEY_APOSTROPHE", "~": "KEY_GRAVE", "<": "KEY_COMMA",
    ">": "KEY_DOT", "?": "KEY_SLASH",
}


class RateLimited(Exception):
    """Too many wrong pairing codes from one phone."""


# ---------------------------------------------------------------- pairing
class Pairing:
    """Holds the 6-digit code and the tokens of phones that entered it."""

    def __init__(self, code=None, clock=time.monotonic):
        self.code = code or self._new_code()
        self._clock = clock
        self._tokens = []          # oldest first
        self._wrong = {}           # ip -> [times of wrong attempts]
        self._all_wrong = []       # times of wrong attempts from anyone
        self._lock = threading.Lock()

    @staticmethod
    def _new_code():
        return "%06d" % secrets.randbelow(1_000_000)

    def pair(self, ip, code):
        """Returns a new token for the right code, None for a wrong one."""
        with self._lock:
            now = self._clock()
            recent = [t for t in self._wrong.get(ip, []) if now - t < WRONG_WINDOW]
            self._wrong[ip] = recent
            if len(recent) >= WRONG_LIMIT:
                raise RateLimited()
            if not _same(code, self.code):
                recent.append(now)
                self._all_wrong = [t for t in self._all_wrong if now - t < WRONG_WINDOW]
                self._all_wrong.append(now)
                if len(self._all_wrong) >= GLOBAL_WRONG_LIMIT:
                    # Someone is guessing from many addresses: start over with
                    # a new code. Phones already paired keep their tokens.
                    self.code = self._new_code()
                    self._all_wrong = []
                    log.warning("phone remote: too many wrong codes, new code made")
                return None
            token = secrets.token_urlsafe(24)
            self._tokens.append(token)
            del self._tokens[:-MAX_TOKENS]
            return token

    def valid(self, token):
        if not token:
            return False
        with self._lock:
            return any(_same(token, t) for t in self._tokens)

    def count(self):
        with self._lock:
            return len(self._tokens)


def _same(given, expected):
    """Constant-time compare that never crashes on odd (non-ASCII) input."""
    given = str(given).encode("utf-8", "replace")
    return secrets.compare_digest(given, expected.encode())


def is_local_host_header(host):
    """Blocks DNS-rebinding: the address bar must hold an IP or 'localhost',
    never someone's domain name."""
    if not host:
        return True                       # HTTP/1.0 clients may omit it
    host = host.strip()
    if host.startswith("["):              # [::1]:8080
        name = host[1:host.find("]")] if "]" in host else ""
    else:
        name = host.rsplit(":", 1)[0] if host.count(":") == 1 else host
    if name.lower() == "localhost":
        return True
    try:
        ipaddress.ip_address(name)
        return True
    except ValueError:
        return False


def is_local_client(ip):
    """True only for addresses that can belong to a device on the home network."""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    if getattr(addr, "ipv4_mapped", None):
        addr = addr.ipv4_mapped
    return addr.is_private or addr.is_loopback or addr.is_link_local


def _clamp(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("not a number")
    return int(max(-MAX_DELTA, min(MAX_DELTA, value)))


def parse_command(data):
    """Checks a command from the phone and returns it as a tuple."""
    if not isinstance(data, dict):
        raise ValueError("command must be an object")
    kind = data.get("type")
    if kind == "key":
        name = data.get("name")
        if name not in KEY_NAMES:
            raise ValueError("unknown key")
        return ("key", name)
    if kind == "text":
        text = data.get("text")
        if not isinstance(text, str) or not text or len(text) > MAX_TEXT:
            raise ValueError("bad text")
        text_to_keys(text)                      # rejects non-ASCII early
        return ("text", text)
    if kind == "move":
        return ("move", _clamp(data.get("dx")), _clamp(data.get("dy")))
    if kind == "click":
        if data.get("button") not in ("left", "right"):
            raise ValueError("bad button")
        return ("click", data["button"])
    if kind == "scroll":
        step = data.get("step")
        if step not in (1, -1):
            raise ValueError("bad scroll")
        return ("scroll", step)
    if kind == "volume":
        if data.get("action") not in ("up", "down", "mute"):
            raise ValueError("bad volume action")
        return ("volume", data["action"])
    raise ValueError("unknown command")


def text_to_keys(text):
    """'Ab!' -> [('KEY_A', False), ('KEY_B', True), ('KEY_1', True)]."""
    keys = []
    for ch in text:
        if "a" <= ch <= "z":
            keys.append(("KEY_" + ch.upper(), False))
        elif "A" <= ch <= "Z":
            keys.append(("KEY_" + ch, True))
        elif "0" <= ch <= "9":
            keys.append(("KEY_" + ch, False))
        elif ch in _PLAIN:
            keys.append((_PLAIN[ch], False))
        elif ch in _SHIFTED:
            keys.append((_SHIFTED[ch], True))
        else:
            raise ValueError("only English letters, numbers and symbols can be typed")
    return keys


def declared_key_names():
    """Only the keys the phone can actually press (no power/sleep keys)."""
    names = {"KEY_LEFTSHIFT"} | set(KEY_NAMES.values()) | set(_PLAIN.values()) | set(_SHIFTED.values())
    names |= {"KEY_" + c for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"}
    return sorted(names)


def qr_matrix(text):
    """QR code as rows of True (black) / False, with its white border.
    Returns None when python3-qrcode is not installed."""
    try:
        import qrcode
    except ImportError:
        return None
    qr = qrcode.QRCode(border=4, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(text)
    qr.make(fit=True)
    return qr.get_matrix()


def lan_ip():
    """The Pi's address on the home network (no packet is actually sent)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("10.255.255.255", 1))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


def set_volume(action):
    """Same speaker control as the knob: the user's PipeWire default sink."""
    if action == "mute":
        cmd = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
    else:
        cmd = ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@",
               "5%+" if action == "up" else "5%-"]
    try:
        subprocess.run(cmd, timeout=2, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


# ------------------------------------------------------------------ input
class InputBackend:
    """Virtual keyboard + mouse through /dev/uinput (python3-evdev).

    Needs write access to /dev/uinput; install_remote.sh adds a udev rule for
    the 'input' group. Without it, available is False and nothing crashes."""

    def __init__(self):
        self._lock = threading.Lock()
        self._kbd = self._mouse = self._e = None
        self._tried = False
        self._ok = False            # read without the lock (screen thread)

    def _open(self):
        if self._tried:
            return self._kbd is not None
        self._tried = True
        try:
            from evdev import UInput, ecodes as e
            keys = [getattr(e, name) for name in declared_key_names()]
            self._kbd = UInput({e.EV_KEY: keys}, name="retro-tv-phone-keyboard")
            self._mouse = UInput(
                {e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL],
                 e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT]},
                name="retro-tv-phone-mouse")
            self._e = e
            time.sleep(0.3)          # let udev publish the new devices
            self._ok = True
            return True
        except Exception as exc:     # ImportError, OSError (permission), ...
            log.warning("phone remote input unavailable: %s", exc)
            self._kbd = self._mouse = None
            return False

    @property
    def available(self):
        """Never blocks: safe to call from tv.py's screen every second."""
        return self._ok

    def ensure(self):
        """Opens the devices if needed (may take ~0.3 s). Server threads only."""
        with self._lock:
            return self._open()

    def _tap(self, code, shift=False):
        e, k = self._e, self._kbd
        if shift:
            k.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        k.write(e.EV_KEY, code, 1)
        k.syn()
        k.write(e.EV_KEY, code, 0)
        if shift:
            k.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        k.syn()

    def key(self, name):
        with self._lock:
            if self._open():
                self._tap(getattr(self._e, KEY_NAMES[name]))

    def type_text(self, text):
        with self._lock:
            if self._open():
                for key_name, shift in text_to_keys(text):
                    self._tap(getattr(self._e, key_name), shift)
                    time.sleep(0.005)

    def move(self, dx, dy):
        with self._lock:
            if self._open():
                e, m = self._e, self._mouse
                m.write(e.EV_REL, e.REL_X, dx)
                m.write(e.EV_REL, e.REL_Y, dy)
                m.syn()

    def click(self, button):
        with self._lock:
            if self._open():
                e, m = self._e, self._mouse
                code = e.BTN_LEFT if button == "left" else e.BTN_RIGHT
                m.write(e.EV_KEY, code, 1)
                m.syn()
                m.write(e.EV_KEY, code, 0)
                m.syn()

    def scroll(self, step):
        with self._lock:
            if self._open():
                self._mouse.write(self._e.EV_REL, self._e.REL_WHEEL, step)
                self._mouse.syn()

    def close(self):
        with self._lock:
            for dev in (self._kbd, self._mouse):
                try:
                    if dev is not None:
                        dev.close()
                except Exception:
                    pass
            self._kbd = self._mouse = None
            self._ok = False


# ----------------------------------------------------------------- server
class RemoteServer:
    def __init__(self, input_backend=None, ports=DEFAULT_PORTS, page_path=PAGE_PATH):
        self.input = input_backend if input_backend is not None else InputBackend()
        self.ports = ports
        self.page_path = page_path
        self.pairing = Pairing()
        self.port = None
        self._httpd = None
        self._thread = None
        self.running = False

    def start(self):
        """Starts listening on the first free port. False if none was free."""
        handler = _make_handler(self)
        for port in self.ports:
            try:
                self._httpd = ThreadingHTTPServer(("0.0.0.0", port), handler)
                break
            except OSError:
                continue
        else:
            log.warning("phone remote: no free port in %s", list(self.ports))
            return False
        self._httpd.daemon_threads = True
        self.running = True
        self.port = self._httpd.server_address[1]
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()
        ensure = getattr(self.input, "ensure", None)
        if ensure is not None:
            threading.Thread(target=ensure, daemon=True).start()
        return True

    def stop(self):
        self.running = False      # phones still connected get turned away
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd.server_close()
            self._httpd = None
        close = getattr(self.input, "close", None)
        if close:
            close()

    def url(self):
        return "http://%s:%d/" % (lan_ip(), self.port)

    def qr_link(self):
        return self.url() + "#code=" + self.pairing.code

    def run_command(self, cmd):
        """Returns False if the TV could not act on it (no input device)."""
        kind = cmd[0]
        if kind == "volume":
            return set_volume(cmd[1])
        ensure = getattr(self.input, "ensure", None)
        if not (ensure() if ensure is not None else self.input.available):
            return False
        if kind == "key":
            self.input.key(cmd[1])
        elif kind == "text":
            self.input.type_text(cmd[1])
        elif kind == "move":
            self.input.move(cmd[1], cmd[2])
        elif kind == "click":
            self.input.click(cmd[1])
        elif kind == "scroll":
            self.input.scroll(cmd[1])
        return True


def _make_handler(remote):
    class Handler(BaseHTTPRequestHandler):
        server_version = "RetroTVRemote/1"
        protocol_version = "HTTP/1.1"
        timeout = HANDLER_TIMEOUT

        def log_message(self, fmt, *args):      # keep the terminal quiet
            log.debug("%s " + fmt, self.client_address[0], *args)

        def _send(self, status, body=b"", ctype="application/json"):
            if isinstance(body, (dict, list)):
                body = json.dumps(body).encode()
            if status >= 400:
                # The request body may be unread: never reuse this connection.
                self.close_connection = True
            self.send_response(status)
            if status >= 400:
                self.send_header("Connection", "close")
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            if body:
                self.wfile.write(body)

        def _local_only(self):
            if not remote.running:
                self.close_connection = True
                self._send(503, {"error": "the TV remote has stopped"})
                return False
            if is_local_client(self.client_address[0]) and \
                    is_local_host_header(self.headers.get("Host", "")):
                return True
            self._send(403, {"error": "same Wi-Fi only"})
            return False

        def _json_body(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1
            if length < 0 or length > MAX_BODY:
                self.close_connection = True
                self._send(413, {"error": "too large"})
                return None
            try:
                data = json.loads(self.rfile.read(length) or b"null")
            except (ValueError, UnicodeDecodeError):
                self._send(400, {"error": "bad json"})
                return None
            if not isinstance(data, dict):
                self._send(400, {"error": "bad json"})
                return None
            return data

        def do_GET(self):
            if not self._local_only():
                return
            path = self.path.split("?", 1)[0]
            if path == "/":
                try:
                    with open(remote.page_path, "rb") as f:
                        page = f.read()
                except OSError:
                    self._send(500, b"remote_page.html is missing next to remote_server.py",
                               "text/plain; charset=utf-8")
                    return
                self._send(200, page, "text/html; charset=utf-8")
            elif path == "/api/status":
                token = self.headers.get("X-Remote-Token", "")
                self._send(200, {"paired": remote.pairing.valid(token),
                                 "input": bool(remote.input.available)})
            else:
                self._send(404, {"error": "not found"})

        def do_POST(self):
            if not self._local_only():
                return
            if self.path == "/api/pair":
                data = self._json_body()
                if data is None:
                    return
                try:
                    token = remote.pairing.pair(self.client_address[0], data.get("code", ""))
                except RateLimited:
                    self._send(429, {"error": "too many wrong codes, wait a minute"})
                    return
                if token is None:
                    self._send(403, {"error": "wrong code"})
                else:
                    self._send(200, {"token": token})
            elif self.path == "/api/cmd":
                if not remote.pairing.valid(self.headers.get("X-Remote-Token", "")):
                    self._send(401, {"error": "scan the QR code on the TV again"})
                    return
                data = self._json_body()
                if data is None:
                    return
                try:
                    cmd = parse_command(data)
                except ValueError as exc:
                    self._send(400, {"error": str(exc)})
                    return
                if remote.run_command(cmd):
                    self._send(204)
                else:
                    self._send(503, {"error": "the TV could not do that"})
            else:
                self._send(404, {"error": "not found"})

    return Handler


if __name__ == "__main__":
    # Manual test without tv.py:  python3 remote_server.py
    logging.basicConfig(level=logging.INFO)
    srv = RemoteServer()
    if not srv.start():
        raise SystemExit("no free port")
    print("Open on your phone:", srv.qr_link())
    print("Pairing code:", srv.pairing.code, " (Ctrl+C to stop)")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        srv.stop()
