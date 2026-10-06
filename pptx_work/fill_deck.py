from pptx import Presentation

SRC = r"C:\Users\haals\Downloads\TV Series Social Media by Slidesgo.pptx"
OUT = r"C:\Users\haals\AppData\Roaming\Claude\scratch-workspaces\8ad54198-bc4a-404a-ac38-ba080c4dbefd\40c8920e-8774-4a4f-aa7b-40d3444157cf\scratch-2026-09-10-eb756b\pptx_work\deck_filled.pptx"

prs = Presentation(SRC)


def by_id(slide, shape_id):
    for shape in slide.shapes:
        if shape.shape_id == shape_id:
            return shape
    raise KeyError(f"shape id {shape_id} not found on slide")


def set_text(slide, shape_id, new_text):
    shape = by_id(slide, shape_id)
    tf = shape.text_frame
    first_para = tf.paragraphs[0]
    if not first_para.runs:
        first_para.add_run()
    first_para.runs[0].text = new_text
    # clear any extra runs in the first paragraph
    for r in first_para.runs[1:]:
        r.text = ""
    # clear any extra paragraphs, keep them empty (preserves spacing/formatting)
    for p in tf.paragraphs[1:]:
        for r in p.runs:
            r.text = ""


def set_cell(shape, r, c, text):
    shape.table.cell(r, c).text = text


slides = list(prs.slides)

# ---------------------------------------------------------------- Slide 7
s = slides[6]
set_text(s, 1403, "PROBLEMS BY TYPE")
set_text(s, 1442, "SOFTWARE VS HARDWARE")
set_text(s, 1531, "60%")
set_text(s, 1532, "40%")
set_text(s, 1443, "TIME TO FIX")
set_text(s, 1444, "Under a day")
set_text(s, 1445, "Multiple days")
set_text(s, 1452, "MOST COMMON CAUSES")

# ---------------------------------------------------------------- Slide 8
s = slides[7]
set_text(s, 1537, "BIGGEST TIME SINKS")
set_text(s, 1538, "35%")
set_text(s, 1539, "Tracking down the PipeWire bug that sent audio out the wrong HDMI port")
set_text(s, 1541, "40%")
set_text(s, 1540, "Getting the joystick reliably read as arrow keys under the Wayland compositor")
set_text(s, 1543, "25%")
set_text(s, 1542, "Repairing the LCD panel after its LVDS connector latch broke")

# ---------------------------------------------------------------- Slide 9
s = slides[8]
set_text(s, 1632, "COMPONENT ISSUES")
set_text(s, 1633, "WHAT WENT WRONG")
t1 = by_id(s, 1635)
set_cell(t1, 0, 0, "COMPONENT"); set_cell(t1, 0, 1, "ISSUE")
set_cell(t1, 1, 0, "Audio output"); set_cell(t1, 1, 1, "Routed to the wrong HDMI port by PipeWire")
set_cell(t1, 2, 0, "Volume knob"); set_cell(t1, 2, 1, "Changed the app AND system volume at once")
set_cell(t1, 3, 0, "LCD panel"); set_cell(t1, 3, 1, "LVDS connector latch broke during repair")
t2 = by_id(s, 1634)
set_cell(t2, 0, 0, "COMPONENT"); set_cell(t2, 0, 1, "ISSUE")
set_cell(t2, 1, 0, "Joystick hole"); set_cell(t2, 1, 1, "Wider than the module's own screw spacing")
set_cell(t2, 2, 0, "Speaker grille"); set_cell(t2, 2, 1, "Size was an unconfirmed placeholder")
set_cell(t2, 3, 0, "Volume keys"); set_cell(t2, 3, 1, "Real multimedia keys got grabbed by the desktop")

# ---------------------------------------------------------------- Slide 10
s = slides[9]
set_text(s, 1782, "FOUR MAIN PROBLEMS")
set_text(s, 1784, "AUDIO ROUTING")
set_text(s, 1783, "mpv sent sound out the wrong HDMI port until it was pointed at the correct ALSA device directly")
set_text(s, 1786, "DOUBLE VOLUME CONTROL")
set_text(s, 1785, "The knob changed the app volume and the system volume at the same time")
set_text(s, 1788, "BROKEN SCREEN CONNECTOR")
set_text(s, 1787, "The screen's video connector latch snapped during a repair attempt")
set_text(s, 1790, "JOYSTICK HOLE VS SCREWS")
set_text(s, 1789, "The enclosure's joystick hole ended up wider than the module's own screw spacing")

# ---------------------------------------------------------------- Slide 12
s = slides[11]
set_text(s, 1929, "HOW I FIXED THEM")
set_text(s, 1930, "PRIORITY FIX")
set_text(s, 1932, "SYSTEM VOLUME")
set_text(s, 1936, "Rewired the volume knob to call wpctl directly, so it controls whatever speaker is plugged in")
set_text(s, 1933, "DIRECT AUDIO DEVICE")
set_text(s, 1931, "Pointed mpv at the exact ALSA HDMI device, skipping PipeWire's routing entirely")
set_text(s, 1934, "RELIABLE KEY DETECTION")
set_text(s, 1935, "Checked both the keysym and the raw hardware keycode, since synthetic input devices name keys unreliably")

# ---------------------------------------------------------------- Slide 13
s = slides[12]
set_text(s, 1941, "DEBUGGING TOOLBOX")
set_text(s, 1944, "wpctl status, to see where audio was actually routing")
set_text(s, 1945, "key_debug.py, to print the real keysym and hardware keycode for any key")
set_text(s, 1946, "The flashlight test, to tell a dead backlight from a dead video signal")
set_text(s, 1942, "The iptv-org database, to verify channels before adding them")
set_text(s, 1947, "A BFS simulation, to prove the on-screen keyboard is reachable by joystick alone")
set_text(s, 1943, "Round-trip extraction tests before ever sending the installer")

# ---------------------------------------------------------------- Slide 14
s = slides[13]
set_text(s, 1987, "WHERE THIS STANDS NOW")
set_text(s, 2038, "Every major software problem has a working fix - audio, volume control, and key detection are all solid. The screen connector repair is still in progress.")

# ---------------------------------------------------------------- Slide 16
s = slides[15]
set_text(s, 2136, "WIRING OVERVIEW")
set_text(s, 2143, "JOYSTICK")
set_text(s, 2144, "Wired to Arduino digital pins for direction, plus one for the click button")
set_text(s, 2145, "VOLUME KNOB")
set_text(s, 2146, "A 10K potentiometer wired to an Arduino analog input")
set_text(s, 2147, "POWER BUTTON")
set_text(s, 2148, "Its own Arduino digital pin, held for 2 seconds to shut down")
set_text(s, 2137, "ARDUINO -> PI")
set_text(s, 2138, "Connected over USB, sending plain text commands over serial")
set_text(s, 2139, "PI -> DRIVER BOARD")
set_text(s, 2140, "HDMI out from the Pi into the universal LCD controller board")
set_text(s, 2141, "DRIVER BOARD -> SCREEN")
set_text(s, 2142, "LVDS ribbon cable plus a separate backlight power connector")

# ---------------------------------------------------------------- Slide 17
s = slides[16]
set_text(s, 2177, "HOW A BUTTON PRESS TRAVELS")
set_text(s, 2178, "1. ARDUINO")
set_text(s, 2179, "Reads the joystick, knob, and button, and sends a plain text command over serial")
set_text(s, 2180, "2. THE BRIDGE")
set_text(s, 2181, "rpi_bridge.py on the Pi turns that command into a real key or mouse event")
set_text(s, 2182, "3. THE APP")
set_text(s, 2183, "tv.py receives it like any keyboard input and reacts on screen")

# ---------------------------------------------------------------- Slide 18
s = slides[17]
set_text(s, 2228, "WIRING IN PROGRESS")
set_text(s, 2229, "Every input component runs back to the Arduino on its own pin, and the Arduino talks to the Pi over a single USB serial cable - no extra wiring needed between the controller and the software.")

# ---------------------------------------------------------------- Slide 19
s = slides[18]
set_text(s, 2256, "THE FINISHED CONTROLLER")

# ---------------------------------------------------------------- Slide 20
s = slides[19]
set_text(s, 2261, "THREE MAIN CONNECTIONS")
set_text(s, 2366, "USB SERIAL")
set_text(s, 2353, "Arduino to Raspberry Pi, carrying every joystick, knob, and button command")
set_text(s, 2367, "GPIO")
set_text(s, 2354, "The power button wired straight to the Pi for a direct, reliable shutdown")
set_text(s, 2368, "HDMI")
set_text(s, 2361, "Raspberry Pi to the driver board, carrying video to the recycled laptop screen")

# ---------------------------------------------------------------- Slide 21
s = slides[20]
set_text(s, 2377, "WIRING REFERENCE TABLE")
t = by_id(s, 2378)
rows = [
    ("ARDUINO", "Joystick X/Y/click", "Knob wiper", "Button pin"),
    ("PI", "USB from Arduino", "HDMI to driver board", "GPIO to power button"),
    ("DRIVER BOARD", "HDMI in", "LVDS out to panel", "Backlight power out"),
    ("SCREEN", "LVDS in", "Backlight in", "-"),
    ("POWER", "5V to Pi", "12V to driver board", "Shared ground"),
]
for r, row in enumerate(rows):
    for c, val in enumerate(row):
        set_cell(t, r, c, val)

# ---------------------------------------------------------------- Slide 22
s = slides[21]
set_text(s, 2397, "BUILD MILESTONES")
set_text(s, 2398, "PHASE 1")
set_text(s, 2399, "PHASE 2")
set_text(s, 2404, "Step 1")
set_text(s, 2405, "Wire joystick, knob, and button to the Arduino")
set_text(s, 2406, "Step 2")
set_text(s, 2407, "Flash the Arduino sketch and test raw serial output")
set_text(s, 2400, "Step 3")
set_text(s, 2401, "Get rpi_bridge.py turning serial commands into real key/mouse events")
set_text(s, 2402, "Step 4")
set_text(s, 2403, "Wire the driver board, screen, and power button into the enclosure")

# ---------------------------------------------------------------- Slide 24
s = slides[23]
set_text(s, 2564, "GOALS")
set_text(s, 2565, "GOAL 1")
set_text(s, 2566, "Build a fully working retro TV controllable end-to-end with just the joystick")
set_text(s, 2567, "GOAL 2")
set_text(s, 2568, "Fit everything into a custom laser-cut enclosure sized for the recycled screen")

# ---------------------------------------------------------------- Slide 25
s = slides[24]
set_text(s, 2649, "264")
set_text(s, 2650, "Channels curated for the custom IPTV channel list, each checked twice before being added")

prs.save(OUT)
print("Saved", OUT)
print("Slide count:", len(prs.slides))
