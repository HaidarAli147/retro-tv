"""Offline checks for the phone remote: python3 -m unittest tests.test_remote_server -v

No GTK, display, uinput, speaker or internet needed.
"""
import json
import pathlib
import re
import subprocess
import sys
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "raspberry_pi"))
import remote_server as rs


class FakeClock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


class FakeInput:
    def __init__(self, available=True):
        self.available = available
        self.calls = []

    def key(self, name): self.calls.append(("key", name))
    def type_text(self, text): self.calls.append(("text", text))
    def move(self, dx, dy): self.calls.append(("move", dx, dy))
    def click(self, button): self.calls.append(("click", button))
    def scroll(self, step): self.calls.append(("scroll", step))
    def close(self): pass


class PairingTests(unittest.TestCase):
    def test_code_is_six_digits(self):
        for _ in range(50):
            self.assertRegex(rs.Pairing().code, r"^\d{6}$")

    def test_pair_right_and_wrong_code(self):
        p = rs.Pairing(code="123456")
        self.assertIsNone(p.pair("192.168.1.5", "000000"))
        token = p.pair("192.168.1.5", "123456")
        self.assertTrue(token)
        self.assertTrue(p.valid(token))
        self.assertFalse(p.valid("made-up"))
        self.assertFalse(p.valid(""))

    def test_rate_limit_after_five_wrong_then_recovers(self):
        clock = FakeClock()
        p = rs.Pairing(code="123456", clock=clock)
        for _ in range(5):
            self.assertIsNone(p.pair("192.168.1.5", "111111"))
        with self.assertRaises(rs.RateLimited):
            p.pair("192.168.1.5", "123456")      # even the right code waits
        self.assertTrue(p.pair("192.168.1.9", "123456"))  # other phone fine
        clock.now += 61
        self.assertTrue(p.pair("192.168.1.5", "123456"))

    def test_many_wrong_codes_from_many_phones_changes_code(self):
        clock = FakeClock()
        p = rs.Pairing(code="123456", clock=clock)
        old = p.pair("192.168.1.2", "123456")
        for i in range(rs.GLOBAL_WRONG_LIMIT):
            p.pair("192.168.1.%d" % (10 + i // 4), "000000")
        self.assertNotEqual(p.code, "123456")            # guessing restarts
        self.assertIsNone(p.pair("192.168.1.99", "123456"))
        self.assertTrue(p.valid(old))                    # paired phones keep working

    def test_non_ascii_code_or_token_does_not_crash(self):
        p = rs.Pairing(code="123456")
        self.assertIsNone(p.pair("192.168.1.5", "١٢٣٤٥٦"))
        self.assertFalse(p.valid("tökén"))

    def test_tokens_unique_and_counted(self):
        p = rs.Pairing(code="123456")
        a, b = p.pair("10.0.0.2", "123456"), p.pair("10.0.0.3", "123456")
        self.assertNotEqual(a, b)
        self.assertEqual(p.count(), 2)
        self.assertTrue(p.valid(a) and p.valid(b))   # two phones at once

    def test_local_ip_filter(self):
        for ip in ("192.168.1.5", "10.0.0.2", "172.16.4.1", "127.0.0.1",
                   "169.254.1.1", "::1", "::ffff:192.168.1.5"):
            self.assertTrue(rs.is_local_client(ip), ip)
        for ip in ("8.8.8.8", "2001:4860::1", "junk", ""):
            self.assertFalse(rs.is_local_client(ip), ip)


class CommandTests(unittest.TestCase):
    def test_parse_command_valid(self):
        self.assertEqual(rs.parse_command({"type": "key", "name": "UP"}), ("key", "UP"))
        self.assertEqual(rs.parse_command({"type": "text", "text": "hi"}), ("text", "hi"))
        self.assertEqual(rs.parse_command({"type": "move", "dx": 999, "dy": -3.7}), ("move", 200, -3))
        self.assertEqual(rs.parse_command({"type": "click", "button": "right"}), ("click", "right"))
        self.assertEqual(rs.parse_command({"type": "scroll", "step": -1}), ("scroll", -1))
        self.assertEqual(rs.parse_command({"type": "volume", "action": "mute"}), ("volume", "mute"))

    def test_parse_command_invalid(self):
        bad = [
            {"type": "key", "name": "POWER"},
            {"type": "power"},
            {"type": "text", "text": "x" * 201},
            {"type": "text", "text": ""},
            {"type": "text", "text": "مرحبا"},
            {"type": "move", "dx": "1", "dy": 0},
            {"type": "move", "dx": True, "dy": 0},
            {"type": "click", "button": "middle"},
            {"type": "scroll", "step": 5},
            {"type": "volume", "action": "max"},
            [], "UP", None,
        ]
        for data in bad:
            with self.assertRaises(ValueError, msg=repr(data)):
                rs.parse_command(data)

    def test_text_to_keys(self):
        self.assertEqual(rs.text_to_keys("Ab1!"), [
            ("KEY_A", True), ("KEY_B", False), ("KEY_1", False), ("KEY_1", True)])
        self.assertEqual(rs.text_to_keys("a b"), [
            ("KEY_A", False), ("KEY_SPACE", False), ("KEY_B", False)])
        self.assertEqual(rs.text_to_keys("@."), [("KEY_2", True), ("KEY_DOT", False)])
        with self.assertRaises(ValueError):
            rs.text_to_keys("é")

    def test_qr_matrix(self):
        m = rs.qr_matrix("http://192.168.1.20:8080/#code=123456")
        if m is None:
            self.skipTest("python3-qrcode not installed here")
        self.assertGreaterEqual(len(m), 21 + 8)
        self.assertTrue(all(len(row) == len(m) for row in m))

    @patch.object(rs.subprocess, "run")
    def test_volume_runs_wpctl(self, run):
        self.assertTrue(rs.set_volume("up"))
        self.assertEqual(run.call_args.args[0],
                         ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%+"])
        rs.set_volume("mute")
        self.assertEqual(run.call_args.args[0],
                         ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
        run.side_effect = FileNotFoundError()
        self.assertFalse(rs.set_volume("down"))


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.fake = FakeInput()
        self.srv = rs.RemoteServer(input_backend=self.fake, ports=[0])
        self.assertTrue(self.srv.start())
        self.base = "http://127.0.0.1:%d" % self.srv.port

    def tearDown(self):
        self.srv.stop()

    def req(self, path, data=None, token=None, raw=None):
        body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
        r = urllib.request.Request(self.base + path, data=body,
                                   method="POST" if body is not None else "GET")
        r.add_header("Content-Type", "application/json")
        if token:
            r.add_header("X-Remote-Token", token)
        try:
            with urllib.request.urlopen(r, timeout=5) as resp:
                text = resp.read()
                return resp.status, (json.loads(text) if text and resp.headers.get_content_type() == "application/json" else text)
        except urllib.error.HTTPError as err:
            return err.code, json.loads(err.read() or b"null")

    def pair(self):
        status, body = self.req("/api/pair", {"code": self.srv.pairing.code})
        self.assertEqual(status, 200)
        return body["token"]

    def test_full_flow_pair_then_commands(self):
        token = self.pair()
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "UP"}, token)[0], 204)
        self.assertEqual(self.req("/api/cmd", {"type": "text", "text": "Hi"}, token)[0], 204)
        self.assertEqual(self.req("/api/cmd", {"type": "move", "dx": 5, "dy": -2}, token)[0], 204)
        self.assertEqual(self.fake.calls, [("key", "UP"), ("text", "Hi"), ("move", 5, -2)])
        self.assertEqual(self.req("/api/status", token=token)[1], {"paired": True, "input": True})

    def test_wrong_code_403_and_rate_limit_429(self):
        for _ in range(5):
            self.assertEqual(self.req("/api/pair", {"code": "nope"})[0], 403)
        self.assertEqual(self.req("/api/pair", {"code": self.srv.pairing.code})[0], 429)

    def test_cmd_without_or_with_bad_token_401(self):
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "UP"})[0], 401)
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "UP"}, "fake")[0], 401)
        self.assertEqual(self.fake.calls, [])

    def test_restart_invalidates_token(self):
        token = self.pair()
        self.srv.stop()
        self.srv = rs.RemoteServer(input_backend=self.fake, ports=[0])
        self.srv.start()
        self.base = "http://127.0.0.1:%d" % self.srv.port
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "UP"}, token)[0], 401)

    def test_stopped_server_ignores_open_connections(self):
        import http.client
        token = self.pair()
        conn = http.client.HTTPConnection("127.0.0.1", self.srv.port, timeout=5)
        body = json.dumps({"type": "key", "name": "UP"})
        headers = {"Content-Type": "application/json", "X-Remote-Token": token}
        conn.request("POST", "/api/cmd", body, headers)
        self.assertEqual(conn.getresponse().read() or 204, 204)
        self.srv.stop()
        try:
            conn.request("POST", "/api/cmd", body, headers)
            status = conn.getresponse().status
        except (OSError, http.client.HTTPException):
            status = None                      # connection closed: also fine
        self.assertNotEqual(status, 204)
        self.assertEqual(self.fake.calls, [("key", "UP")])
        self.srv = rs.RemoteServer(input_backend=self.fake, ports=[0])
        self.srv.start()

    def test_bad_input_400_413_and_server_survives(self):
        token = self.pair()
        self.assertEqual(self.req("/api/cmd", raw=b"{not json", token=token)[0], 400)
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "POWER"}, token)[0], 400)
        self.assertEqual(self.req("/api/cmd", raw=b"x" * 5000, token=token)[0], 413)
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "DOWN"}, token)[0], 204)

    def test_input_unavailable(self):
        self.fake.available = False
        token = self.pair()
        self.assertEqual(self.req("/api/status", token=token)[1]["input"], False)
        self.assertEqual(self.req("/api/cmd", {"type": "key", "name": "UP"}, token)[0], 503)
        with patch.object(rs, "set_volume", return_value=True):
            self.assertEqual(self.req("/api/cmd", {"type": "volume", "action": "up"}, token)[0], 204)

    def test_non_local_client_rejected(self):
        with patch.object(rs, "is_local_client", return_value=False):
            self.assertEqual(self.req("/api/pair", {"code": self.srv.pairing.code})[0], 403)
            self.assertEqual(self.req("/")[0], 403)

    def test_handler_has_timeout(self):
        self.assertTrue(0 < rs._make_handler(self.srv).timeout <= 15)

    def test_foreign_host_header_rejected(self):
        import http.client
        for host, expected in (("evil.example:8080", 403), ("192.168.1.20:8080", 200),
                               ("localhost:8080", 200), ("[::1]:8080", 200)):
            conn = http.client.HTTPConnection("127.0.0.1", self.srv.port, timeout=5)
            conn.putrequest("GET", "/api/status", skip_host=True)
            conn.putheader("Host", host)
            conn.endheaders()
            self.assertEqual(conn.getresponse().status, expected, host)
            conn.close()

    def test_error_reply_closes_connection(self):
        import http.client
        conn = http.client.HTTPConnection("127.0.0.1", self.srv.port, timeout=5)
        conn.request("POST", "/api/cmd", json.dumps({"type": "key", "name": "UP"}),
                     {"Content-Type": "application/json", "X-Remote-Token": "nope"})
        resp = conn.getresponse()
        self.assertEqual(resp.status, 401)
        self.assertEqual(resp.getheader("Connection"), "close")

    def test_page_served_and_self_contained(self):
        status, page = self.req("/")
        self.assertEqual(status, 200)
        html = page.decode()
        self.assertIn("/api/pair", html)
        self.assertIn("#7851A9".lower(), html.lower())
        self.assertNotRegex(html, r'(src|href)\s*=\s*["\']https?://')
        self.assertNotIn("POWER", html)

    def test_qr_link_contains_code(self):
        link = self.srv.qr_link()
        self.assertTrue(link.endswith("#code=" + self.srv.pairing.code))
        self.assertRegex(link, r"^http://[\d.]+:\d+/#code=\d{6}$")


class InputBackendTests(unittest.TestCase):
    def test_available_never_blocks_or_opens(self):
        backend = rs.InputBackend()
        with patch.object(backend, "_open", side_effect=AssertionError("opened")):
            backend._lock.acquire()          # typing in progress elsewhere
            try:
                self.assertFalse(backend.available)
            finally:
                backend._lock.release()

    def test_declared_keys_are_only_what_is_used(self):
        names = rs.declared_key_names()
        self.assertIn("KEY_A", names)
        self.assertIn("KEY_LEFTSHIFT", names)
        self.assertIn("KEY_ESC", names)
        for banned in ("KEY_POWER", "KEY_SLEEP", "KEY_SUSPEND", "KEY_WAKEUP"):
            self.assertNotIn(banned, names)


class SafetyTests(unittest.TestCase):
    def test_install_scripts_never_touch_bridge(self):
        for name in ("install_remote.sh", "uninstall_remote.sh"):
            text = (ROOT / "raspberry_pi" / name).read_text()
            for banned in ("rpi-bridge", "rpi_bridge", "power-button", "power_button",
                           "setup.sh", "channels.m3u", "chime.wav"):
                self.assertNotIn(banned, text, "%s mentions %s" % (name, banned))

    def test_bridge_and_setup_unchanged_on_branch(self):
        out = subprocess.run(
            ["git", "-C", str(ROOT), "diff", "main", "--",
             "raspberry_pi/rpi_bridge.py", "raspberry_pi/setup.sh"],
            capture_output=True, text=True)
        if out.returncode != 0:
            self.skipTest("git/main not available")
        self.assertEqual(out.stdout, "")


if __name__ == "__main__":
    unittest.main()
