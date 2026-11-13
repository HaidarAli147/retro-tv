"""Offline checks for opening GOAAAL LIVE in Chromium:
python3 -m unittest tests.test_external_browser -v"""
import pathlib
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi"))
import tv
import remote_server as rs


class ChromiumTests(unittest.TestCase):
    def test_goaaal_tile_uses_chromium(self):
        tiles = [a for a in tv.home_app_list([]) if a["name"] == "GOAAAL LIVE"]
        self.assertEqual(len(tiles), 1)
        self.assertEqual(tiles[0]["kind"], "browser")
        self.assertIn("match-view", tiles[0]["url"])

    def test_find_chromium(self):
        with patch.object(tv.shutil, "which", side_effect=lambda n: "/usr/bin/chromium" if n == "chromium" else None):
            self.assertEqual(tv.find_chromium(), "/usr/bin/chromium")
        with patch.object(tv.shutil, "which", side_effect=lambda n: "/usr/bin/chromium-browser" if n == "chromium-browser" else None):
            self.assertEqual(tv.find_chromium(), "/usr/bin/chromium-browser")
        with patch.object(tv.shutil, "which", return_value=None):
            self.assertIsNone(tv.find_chromium())

    def test_command(self):
        cmd = tv.chromium_command("/usr/bin/chromium", "https://appendhub.com/go-wall/app/?match-view",
                                  "/home/u/.config/retro-tv/chromium", 3.0)
        self.assertEqual(cmd[0], "/usr/bin/chromium")
        self.assertIn("--kiosk", cmd)
        self.assertIn("--app=https://appendhub.com/go-wall/app/?match-view", cmd)
        self.assertIn("--user-data-dir=/home/u/.config/retro-tv/chromium", cmd)
        self.assertIn("--autoplay-policy=no-user-gesture-required", cmd)
        self.assertIn("--force-device-scale-factor=3.0", cmd)       # readable on the 4K TV
        self.assertIn("--no-first-run", cmd)

    def test_back_detection(self):
        ESC, KEY = 1, 1                                            # evdev KEY_ESC=1, EV_KEY=1
        self.assertTrue(tv.is_back_press(KEY, ESC, 1))
        self.assertFalse(tv.is_back_press(KEY, ESC, 0))            # release
        self.assertFalse(tv.is_back_press(KEY, 28, 1))             # Enter
        self.assertFalse(tv.is_back_press(2, ESC, 1))              # not a key event

    def test_bridge_device_name_matches_bridge(self):
        bridge = (pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi" / "rpi_bridge.py").read_text()
        self.assertIn('name="%s"' % tv.BRIDGE_KEYBOARD_NAME, bridge)


class BridgeWatcherTests(unittest.TestCase):
    def test_joystick_back_on_bridge_keyboard_closes_chromium(self):
        import os, threading, types
        from types import SimpleNamespace as NS
        r, w = os.pipe()
        class Dev:
            def __init__(self, path):
                self.name = {"/dev/input/event5": tv.BRIDGE_KEYBOARD_NAME}.get(path, "other keyboard")
                self.closed = False
            def fileno(self): return r
            def read(self):
                os.read(r, 1)
                return [NS(type=1, code=28, value=1), NS(type=1, code=1, value=0),
                        NS(type=1, code=1, value=1)]          # Enter, Esc up, Esc down
            def close(self): self.closed = True
        fake = types.ModuleType("evdev")
        fake.list_devices = lambda: ["/dev/input/event3", "/dev/input/event5"]
        fake.InputDevice = Dev
        calls = []
        stop = threading.Event()
        window = SimpleWindow = NS(close_chromium=lambda: calls.append("close"))
        with patch.dict(sys.modules, {"evdev": fake}), \
             patch.object(tv.GLib, "idle_add", side_effect=lambda fn, *a: fn(*a)):
            t = threading.Thread(target=tv.TVWindow._watch_bridge_back, args=(window, stop))
            t.start()
            os.write(w, b"x")
            for _ in range(50):
                if calls: break
                threading.Event().wait(0.05)
            stop.set(); t.join(3)
        os.close(r); os.close(w)
        self.assertEqual(calls, ["close"])          # only the Esc press, once
        self.assertFalse(t.is_alive())


class RemoteBackHookTests(unittest.TestCase):
    def test_phone_back_calls_hook(self):
        seen = []
        srv = rs.RemoteServer(input_backend=type("F", (), {"available": True, "key": lambda s, n: None})(),
                              ports=[0])
        srv.on_key = seen.append
        self.assertTrue(srv.run_command(("key", "BACK")))
        self.assertTrue(srv.run_command(("key", "UP")))
        self.assertEqual(seen, ["BACK", "UP"])


class InstallRuleTests(unittest.TestCase):
    def test_udev_rule_lets_tv_read_bridge_keyboard(self):
        text = (pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi" / "install_remote.sh").read_text()
        self.assertIn('ATTRS{name}=="%s"' % tv.BRIDGE_KEYBOARD_NAME, text)
        self.assertIn("--subsystem-match=input", text)


if __name__ == "__main__":
    unittest.main()
