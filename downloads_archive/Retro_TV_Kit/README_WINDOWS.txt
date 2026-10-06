RETRO TV ON WINDOWS
===================
tv.py needs GTK3, PyGObject and mpv. On Windows the easy way to get all
three is MSYS2.

1. Install MSYS2 (default folder C:\msys64):   https://www.msys2.org
2. Open "MSYS2 UCRT64" from the Start menu and run this one line:

   pacman -S --needed mingw-w64-ucrt-x86_64-gtk3 mingw-w64-ucrt-x86_64-python-gobject mingw-w64-ucrt-x86_64-mpv

3. Double-click run_tv_windows.bat (keep it in the same folder as tv.py and channels.m3u).

Differences from the Pi
 - Video is embedded in the window the same way (mpv --wid with the window handle).
 - Audio uses mpv's normal Windows output; the PipeWire settings are Pi-only.
 - There is no embedded browser (WebKitGTK is not available on Windows), so
   opening TOD or an added web app opens it in your normal browser instead.
 - Controls are the keyboard: arrows, Enter, Backspace/Escape for back, F11 full screen, Ctrl+Q quit.
   The Arduino bridge is not used.
 - Settings and state are stored in your user folder (C:\Users\<you>\.config\brack-tv).
