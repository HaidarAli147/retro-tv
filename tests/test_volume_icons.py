"""Offline checks: /usr/bin/python3 -m unittest discover -s tests -v.

Needs the app's GTK/GdkPixbuf bindings, but no display, speaker or internet.
"""
import base64
import pathlib
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import tv


class SpeakerTests(unittest.TestCase):
    def test_parse_percentage_mute_and_amplified_output(self):
        self.assertEqual(tv.parse_speaker_volume("Volume: 0.45\n"), (0.45, False))
        self.assertEqual(tv.parse_speaker_volume("Volume: 0.70 [MUTED]"), (0.70, True))
        self.assertEqual(tv.parse_speaker_volume("Volume: 1.25"), (1.25, False))
        for value in ("", "Volume: nan", "Error", "Volume: -1", "Volume: 0.5 junk"):
            with self.assertRaises(ValueError):
                tv.parse_speaker_volume(value)

    @patch.object(tv, "IS_WINDOWS", False)
    def test_current_default_sink_and_bounded_subprocess(self):
        with patch.object(tv.subprocess, "run", return_value=SimpleNamespace(stdout="Volume: 0.25")) as run:
            self.assertEqual(tv.read_speaker_volume(), (0.25, False))
            self.assertEqual(run.call_args.args[0], ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"])
            self.assertEqual(run.call_args.kwargs["timeout"], 1)
        for error in (FileNotFoundError(), subprocess.TimeoutExpired("wpctl", 1),
                      subprocess.CalledProcessError(1, "wpctl")):
            with patch.object(tv.subprocess, "run", side_effect=error):
                self.assertIsNone(tv.read_speaker_volume())

    @patch.object(tv, "IS_WINDOWS", True)
    def test_windows_never_executes_wpctl(self):
        with patch.object(tv.subprocess, "run") as run:
            self.assertIsNone(tv.read_speaker_volume())
            run.assert_not_called()

    def test_sink_changes_mute_loss_and_recovery(self):
        window = SimpleNamespace(_closed=False, _volume_busy=True,
                                 _speaker_level=None, speaker_bar=Mock(), osd=Mock())
        apply = lambda value: tv.TVWindow._apply_speaker_level(window, value)
        apply((0.45, False))
        window.speaker_bar.set_text.assert_called_with("SPEAKER  45%")
        window.osd.show_level.assert_not_called()
        apply((0.45, True))
        window.osd.show_level.assert_called_with(0.45, True)
        window.speaker_bar.set_fraction.assert_called_with(0)
        apply((1.25, False))
        window.speaker_bar.set_fraction.assert_called_with(1.0)
        window.speaker_bar.set_text.assert_called_with("SPEAKER  125%")
        apply(None)
        window.speaker_bar.set_text.assert_called_with("SPEAKER UNAVAILABLE")
        window.osd.dismiss.assert_called_once()
        apply((0.2, False))
        window.speaker_bar.set_text.assert_called_with("SPEAKER  20%")

    def test_no_overlapping_audio_requests(self):
        window = SimpleNamespace(_closed=False, _volume_busy=False,
                                 _audio_workers=Mock(), _speaker_read_done=Mock())
        tv.TVWindow._poll_speaker(window)
        tv.TVWindow._poll_speaker(window)
        window._audio_workers.submit.assert_called_once_with(tv.read_speaker_volume)


class IconTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cache_patch = patch.object(tv, "APP_ICON_CACHE", self.temp.name)
        self.cache_patch.start()
        self.addCleanup(self.cache_patch.stop)
        pixbuf = tv.GdkPixbuf.Pixbuf.new(tv.GdkPixbuf.Colorspace.RGB, True, 8, 8, 8)
        pixbuf.fill(0xD0A050FF)
        _, self.png = pixbuf.save_to_bufferv("png", [], [])

    def test_relative_touch_icon_discovery_and_offline_cache(self):
        def resource(url):
            if url == "https://example.test/app":
                return (b'<base href="/assets/"><link rel="apple-touch-icon" href="touch.png">',
                        "https://example.test/app")
            self.assertEqual(url, "https://example.test/assets/touch.png")
            return self.png, url
        with patch.object(tv, "read_icon_resource", side_effect=resource) as read:
            self.assertIsNotNone(tv.fetch_app_icon("https://example.test/app"))
            self.assertEqual(read.call_count, 2)
        with patch.object(tv, "read_icon_resource", side_effect=OSError("offline")) as read:
            self.assertIsNotNone(tv.fetch_app_icon("https://example.test/app"))
            read.assert_not_called()

    def test_bad_declared_image_falls_back_to_favicon(self):
        def resource(url):
            if url.endswith("/favicon.ico"):
                return self.png, url
            if url.endswith("/bad.png"):
                return b"not an image", url
            return b'<link rel="shortcut icon" href="/bad.png">', url
        with patch.object(tv, "read_icon_resource", side_effect=resource):
            self.assertIsNotNone(tv.fetch_app_icon("https://example.test"))

    def test_missing_site_icon_returns_text_fallback(self):
        with patch.object(tv, "read_icon_resource", side_effect=OSError("offline")):
            self.assertIsNone(tv.fetch_app_icon("https://example.test"))

    def test_reject_non_http_and_credentials(self):
        for url in ("file:///etc/passwd", "data:image/png;base64,AA", "https://user:secret@example.test/icon"):
            with self.assertRaises(ValueError):
                tv.http_icon_url("https://example.test", url)
        self.assertEqual(tv.http_icon_url("https://example.test/path/", "icon.png"),
                         "https://example.test/path/icon.png")

    def test_oversized_resource_is_rejected(self):
        response = Mock()
        response.geturl.return_value = "https://example.test/icon.png"
        response.read.return_value = b"x" * (tv.ICON_MAX_BYTES + 1)
        context = Mock()
        context.__enter__ = Mock(return_value=response)
        context.__exit__ = Mock(return_value=False)
        opener = Mock()
        opener.open.return_value = context
        with patch.object(tv.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(ValueError):
                tv.read_icon_resource("https://example.test/icon.png")

    def test_deleted_tile_callback_does_not_touch_widgets(self):
        tile = Mock()
        window = SimpleNamespace(_closed=False, _icon_generation=2)
        tv.TVWindow._apply_app_icon(window, Mock(), Mock(), tile, 1)
        tile.remove.assert_not_called()


class DistributionTests(unittest.TestCase):
    def test_active_app_copies_match(self):
        root = pathlib.Path(__file__).resolve().parents[1]
        source = (root / "tv.py").read_text()
        self.assertEqual(source, (root / "pi_kit/tv.py").read_text())
        installer = (root / "install_tv.sh").read_text()
        embedded = installer.split("<<'TV_PY_EOF_9f3'\n", 1)[1].split("\nTV_PY_EOF_9f3", 1)[0]
        self.assertEqual(source.rstrip("\n"), embedded.rstrip("\n"))


if __name__ == "__main__":
    unittest.main()
