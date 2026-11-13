"""Offline checks for SOUND OUTPUT in Settings:
/usr/bin/python3 -m unittest tests.test_sound_output -v

Needs the app's GTK bindings, but no display, speaker or Pi.
"""
import pathlib
import subprocess
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi"))
import tv

# Real `wpctl status` output from the Pi (2026-11-13), trimmed.
PI_STATUS = """PipeWire 'pipewire-0' [1.4.2, alshowaikh@raspberrypi, cookie:123]
 └─ Clients:
        33. WirePlumber                         [1.4.2, alshowaikh@raspberrypi, pid:1]

Audio
 ├─ Devices:
 │      48. Built-in Audio                      [alsa]
 │      49. Built-in Audio                      [alsa]
 │
 ├─ Sinks:
 │      35. Built-in Audio Digital Stereo (HDMI) [vol: 0.65]
 │  *   57. Built-in Audio Stereo               [vol: 0.30]
 │
 ├─ Sources:
 │
 ├─ Filters:
 │
 └─ Streams:
        88. mpv
             90. output_FL       > bcm2835 Headphones:playback_FL       [active]

Video
 ├─ Devices:
 ├─ Sinks:
 │      70. Some Video Sink
 └─ Streams:

Settings
 └─ Default Configured Devices:
         0. Audio/Sink    alsa_output.platform-fe00b840.mailbox.stereo-fallback
"""


class ParseSinkTests(unittest.TestCase):
    def test_parses_only_audio_sinks_from_pi_output(self):
        self.assertEqual(tv.parse_sinks(PI_STATUS), [
            {"id": 35, "name": "Built-in Audio Digital Stereo (HDMI)", "default": False},
            {"id": 57, "name": "Built-in Audio Stereo", "default": True},
        ])

    def test_usb_speaker_and_no_sinks(self):
        text = "Audio\n ├─ Sinks:\n │  *   61. USB Audio Speaker Analog Stereo [vol: 1.00]\n ├─ Sources:\n"
        self.assertEqual(tv.parse_sinks(text),
                         [{"id": 61, "name": "USB Audio Speaker Analog Stereo", "default": True}])
        self.assertEqual(tv.parse_sinks(""), [])
        self.assertEqual(tv.parse_sinks("Audio\n ├─ Sinks:\n │\n ├─ Sources:\n"), [])

    def test_friendly_labels(self):
        self.assertEqual(tv.sink_label("Built-in Audio Stereo"), "SPEAKER (3.5MM JACK)")
        self.assertEqual(tv.sink_label("Built-in Audio Digital Stereo (HDMI)"), "TV / MONITOR (HDMI)")
        self.assertEqual(tv.sink_label("Built-in Audio Digital Stereo (HDMI 2)"), "TV / MONITOR (HDMI 2)")
        self.assertEqual(tv.sink_label("JBL Go 3"), "JBL GO 3")

    def test_next_sink_wraps_from_current_default(self):
        sinks = tv.parse_sinks(PI_STATUS)
        self.assertEqual(tv.next_sink(sinks, 1)["id"], 35)     # 57 -> wraps to 35
        self.assertEqual(tv.next_sink(sinks, -1)["id"], 35)
        self.assertIsNone(tv.next_sink([], 1))

    def test_saved_choice(self):
        sinks = tv.parse_sinks(PI_STATUS)
        self.assertEqual(tv.saved_sink_to_apply(sinks, "Built-in Audio Digital Stereo (HDMI)"), 35)
        self.assertIsNone(tv.saved_sink_to_apply(sinks, "Built-in Audio Stereo"))   # already default
        self.assertIsNone(tv.saved_sink_to_apply(sinks, "Unplugged USB thing"))     # not there now
        self.assertIsNone(tv.saved_sink_to_apply(sinks, None))


class WpctlTests(unittest.TestCase):
    @patch.object(tv, "IS_WINDOWS", False)
    def test_list_and_set_use_wpctl_with_timeouts(self):
        with patch.object(tv.subprocess, "run", return_value=SimpleNamespace(stdout=PI_STATUS)) as run:
            self.assertEqual(len(tv.list_sinks()), 2)
            self.assertEqual(run.call_args.args[0], ["wpctl", "status"])
            self.assertTrue(run.call_args.kwargs["timeout"] <= 3)
        with patch.object(tv.subprocess, "run") as run:
            self.assertTrue(tv.set_default_sink(35))
            self.assertEqual(run.call_args.args[0], ["wpctl", "set-default", "35"])
        for error in (FileNotFoundError(), subprocess.TimeoutExpired("wpctl", 2),
                      subprocess.CalledProcessError(1, "wpctl")):
            with patch.object(tv.subprocess, "run", side_effect=error):
                self.assertEqual(tv.list_sinks(), [])
                self.assertFalse(tv.set_default_sink(35))

    @patch.object(tv, "IS_WINDOWS", True)
    def test_windows_never_runs_wpctl(self):
        with patch.object(tv.subprocess, "run") as run:
            self.assertEqual(tv.list_sinks(), [])
            self.assertFalse(tv.set_default_sink(1))
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
