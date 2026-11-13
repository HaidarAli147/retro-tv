"""Offline checks for RESOLUTION in Settings:
/usr/bin/python3 -m unittest tests.test_resolution -v

Needs the app's GTK bindings, but no display, monitor or Pi.
"""
import json
import pathlib
import subprocess
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi"))
import tv

# Typical `wlr-randr` text output on Raspberry Pi OS (labwc) with a 22" monitor.
TEXT = """HDMI-A-1 "Samsung Electric Company S22F350 H4ZN000000 (HDMI-A-1)"
  Make: Samsung Electric Company
  Model: S22F350
  Serial: H4ZN000000
  Physical size: 480x270 mm
  Enabled: yes
  Modes:
    720x400 px, 70.082001 Hz
    640x480 px, 59.939999 Hz
    1920x1080 px, 60.000000 Hz (preferred, current)
    1920x1080 px, 50.000000 Hz
    1280x720 px, 60.000000 Hz
    1280x720 px, 50.000000 Hz
    1024x768 px, 60.004002 Hz
  Position: 0,0
  Transform: normal
  Scale: 1.000000
  Adaptive Sync: disabled
HDMI-A-2 "Unknown"
  Enabled: no
  Modes:
"""

JSON = json.dumps([{
    "name": "HDMI-A-1", "description": "Samsung S22F350 (HDMI-A-1)", "enabled": True,
    "modes": [
        {"width": 1920, "height": 1080, "refresh": 60.0, "preferred": True, "current": True},
        {"width": 1280, "height": 720, "refresh": 60.0, "preferred": False, "current": False},
        {"width": 1280, "height": 720, "refresh": 50.0, "preferred": False, "current": False},
    ]}])


class ParseTests(unittest.TestCase):
    def test_text_output(self):
        outs = tv.parse_outputs_text(TEXT)
        self.assertEqual([o["name"] for o in outs], ["HDMI-A-1", "HDMI-A-2"])
        self.assertTrue(outs[0]["enabled"])
        self.assertFalse(outs[1]["enabled"])
        self.assertEqual(len(outs[0]["modes"]), 7)
        cur = [m for m in outs[0]["modes"] if m["current"]]
        self.assertEqual(cur, [{"w": 1920, "h": 1080, "refresh": 60.0, "current": True, "preferred": True}])

    def test_json_output(self):
        outs = tv.parse_outputs_json(JSON)
        self.assertEqual(outs[0]["name"], "HDMI-A-1")
        self.assertEqual(outs[0]["modes"][1], {"w": 1280, "h": 720, "refresh": 60.0,
                                               "current": False, "preferred": False})
        with self.assertRaises(ValueError):
            tv.parse_outputs_json("not json")

    def test_main_output_and_unique_sizes_biggest_first(self):
        out = tv.main_output(tv.parse_outputs_text(TEXT))
        self.assertEqual(out["name"], "HDMI-A-1")
        modes = tv.screen_modes(out)
        self.assertEqual([(m["w"], m["h"]) for m in modes],
                         [(1920, 1080), (1280, 720), (1024, 768), (640, 480), (720, 400)])
        self.assertEqual(modes[0]["refresh"], 60.0)          # keeps the current one
        self.assertEqual(modes[1]["refresh"], 60.0)          # highest refresh per size
        self.assertTrue(modes[0]["current"])
        self.assertIsNone(tv.main_output([]))
        self.assertIsNone(tv.main_output(tv.parse_outputs_text('HDMI-A-2 "x"\n  Enabled: no\n')))

    def test_labels_and_mode_argument(self):
        m = {"w": 1280, "h": 720, "refresh": 59.939999}
        self.assertEqual(tv.mode_label(m), "1280 x 720")
        self.assertEqual(tv.mode_arg(m), "1280x720@59.939999Hz")

    def test_saved_resolution(self):
        out = tv.main_output(tv.parse_outputs_text(TEXT))
        saved = {"output": "HDMI-A-1", "w": 1280, "h": 720, "refresh": 60.0}
        self.assertEqual(tv.saved_mode_to_apply(out, saved)["w"], 1280)
        self.assertIsNone(tv.saved_mode_to_apply(out, dict(saved, w=1920, h=1080)))  # already on
        self.assertIsNone(tv.saved_mode_to_apply(out, dict(saved, w=3840, h=2160)))  # not offered
        self.assertIsNone(tv.saved_mode_to_apply(out, dict(saved, output="HDMI-A-2")))
        self.assertIsNone(tv.saved_mode_to_apply(out, None))
        self.assertIsNone(tv.saved_mode_to_apply(None, saved))


class CommandTests(unittest.TestCase):
    @patch.object(tv, "IS_WINDOWS", False)
    def test_list_prefers_json_and_falls_back_to_text(self):
        with patch.object(tv.subprocess, "run", return_value=SimpleNamespace(stdout=JSON)) as run:
            self.assertEqual(tv.list_outputs()[0]["name"], "HDMI-A-1")
            self.assertEqual(run.call_args.args[0], ["wlr-randr", "--json"])
        calls = []
        def fake(cmd, **kw):
            calls.append(cmd)
            if "--json" in cmd:
                raise subprocess.CalledProcessError(1, cmd)   # older wlr-randr
            return SimpleNamespace(stdout=TEXT)
        with patch.object(tv.subprocess, "run", side_effect=fake):
            self.assertEqual(len(tv.list_outputs()), 2)
        self.assertEqual(calls, [["wlr-randr", "--json"], ["wlr-randr"]])
        with patch.object(tv.subprocess, "run", side_effect=FileNotFoundError()):
            self.assertEqual(tv.list_outputs(), [])

    @patch.object(tv, "IS_WINDOWS", False)
    def test_set_mode(self):
        with patch.object(tv.subprocess, "run") as run:
            self.assertTrue(tv.set_mode("HDMI-A-1", {"w": 1280, "h": 720, "refresh": 60.0}))
            self.assertEqual(run.call_args.args[0],
                             ["wlr-randr", "--output", "HDMI-A-1", "--mode", "1280x720@60.000000Hz"])
            self.assertTrue(run.call_args.kwargs["timeout"] <= 10)
        with patch.object(tv.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "x")):
            self.assertFalse(tv.set_mode("HDMI-A-1", {"w": 1, "h": 1, "refresh": 1}))

    @patch.object(tv, "IS_WINDOWS", True)
    def test_windows_never_runs_wlr_randr(self):
        with patch.object(tv.subprocess, "run") as run:
            self.assertEqual(tv.list_outputs(), [])
            self.assertFalse(tv.set_mode("x", {"w": 1, "h": 1, "refresh": 1}))
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
