#!/usr/bin/env python3
"""Prints every key event this window receives: the keysym name and the
raw hardware keycode. Turn the volume knob while this window has focus
and read off both numbers - that is what tv.py actually sees.

Usage:  python3 key_debug.py   (must run on the Pi's own screen)
"""
import os
os.environ.setdefault("GDK_BACKEND", "x11")

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk


def on_key(_widget, event):
    name = Gdk.keyval_name(event.keyval) or "?"
    print(f"keyval={event.keyval:<8} name={name:<24} hardware_keycode={event.hardware_keycode}")
    return True


win = Gtk.Window(title="Key Debug")
win.set_default_size(500, 200)
win.connect("key-press-event", on_key)
win.connect("destroy", Gtk.main_quit)
label = Gtk.Label(label="Turn the volume knob. Watch the terminal.\nCtrl+C in the terminal to quit.")
win.add(label)
win.show_all()
Gtk.main()
