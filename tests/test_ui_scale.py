"""Offline checks for automatic UI scaling: python3 -m unittest tests.test_ui_scale -v"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "raspberry_pi"))
import tv


class ScaleTests(unittest.TestCase):
    def tearDown(self):
        tv.UI_SCALE = 1.0

    def test_scale_follows_screen_height(self):
        self.assertEqual(tv.ui_scale_for(720), 1.0)
        self.assertEqual(tv.ui_scale_for(1080), 1.5)
        self.assertEqual(tv.ui_scale_for(2160), 3.0)       # the LG 4K TV
        self.assertEqual(tv.ui_scale_for(480), 1.0)        # never shrink below the design
        self.assertEqual(tv.ui_scale_for(4320), 4.0)       # capped
        self.assertEqual(tv.ui_scale_for(0), 1.0)          # unknown screen

    def test_px(self):
        tv.UI_SCALE = 3.0
        self.assertEqual(tv.px(190), 570)
        self.assertEqual(tv.px(-1), -1)                    # "natural size" stays -1
        self.assertEqual(tv.px(0), 0)
        tv.UI_SCALE = 1.5
        self.assertEqual(tv.px(38), 57)

    def test_scale_css_scales_every_px_value_only(self):
        css = b".a { font-size: 23px; padding: 12px 14px; border: 3px solid #404040; }\n.b { opacity: 0.5; }"
        out = tv.scale_css(css, 3.0).decode()
        self.assertIn("font-size: 69px", out)
        self.assertIn("padding: 36px 42px", out)
        self.assertIn("border: 9px solid #404040", out)     # colours untouched
        self.assertIn("opacity: 0.5", out)
        self.assertEqual(tv.scale_css(css, 1.0), css)

    def test_real_css_has_no_px_left_unscaled(self):
        import re
        out = tv.scale_css(tv.CSS, 3.0).decode()
        for value in re.findall(rb"(\d+)px", tv.CSS):
            self.assertIn("%dpx" % round(int(value) * 3), out)


class ScreenSizeChoiceTests(unittest.TestCase):
    def test_auto_and_fixed_choices(self):
        self.assertEqual(tv.effective_scale("auto", 2160), 3.0)
        self.assertEqual(tv.effective_scale(1.5, 2160), 1.5)
        self.assertEqual(tv.effective_scale("junk", 1080), 1.5)       # bad pref -> auto
        self.assertEqual(tv.scale_choice_label("auto", 2160), "AUTO (300%)")
        self.assertEqual(tv.scale_choice_label(0.5, 2160), "50%")
        self.assertEqual(tv.scale_choice_label(1.25, 720), "125%")

    def test_cycling_wraps_both_ways(self):
        self.assertEqual(tv.next_scale_choice("auto", 1), 0.5)
        self.assertEqual(tv.next_scale_choice("auto", -1), 4.0)
        self.assertEqual(tv.next_scale_choice(4.0, 1), "auto")
        self.assertEqual(tv.next_scale_choice(1.0, 1), 1.25)
        self.assertEqual(tv.next_scale_choice("junk", 1), 0.5)


if __name__ == "__main__":
    unittest.main()
