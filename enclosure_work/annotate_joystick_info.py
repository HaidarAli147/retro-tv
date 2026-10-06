from PIL import Image, ImageDraw, ImageFont
import math

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'

try:
    font = ImageFont.truetype("arialbd.ttf", 30)
    font_sm = ImageFont.truetype("arialbd.ttf", 24)
except Exception:
    font = font_sm = ImageFont.load_default()

RED = (200, 20, 20)
ORANGE = (200, 100, 0)
WHITE = (255, 255, 255)


def arrow_line(draw, p1, p2, color=RED, width=4, head=13):
    draw.line([p1, p2], fill=color, width=width)
    ang = math.atan2(p1[1] - p2[1], p1[0] - p2[0])
    for da in (0.35, -0.35):
        hx = p2[0] + head * math.cos(ang + da)
        hy = p2[1] + head * math.sin(ang + da)
        draw.line([p2, (hx, hy)], fill=color, width=width)


def dot(draw, p, r=10, color=RED):
    draw.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=color)


def callout(draw, text, target, box_pos, f=font_sm, align="left", color=RED):
    dot(draw, target, color=color)
    draw.line([target, box_pos], fill=color, width=3)
    lines = text.split("\n")
    widths = [draw.textbbox((0, 0), l, font=f)[2] for l in lines]
    w = max(widths) + 20
    h = len(lines) * (f.size + 8) + 16
    x, y = box_pos
    if align == "left":
        rect = [x, y - h/2, x + w, y + h/2]
    else:
        rect = [x - w, y - h/2, x, y + h/2]
    draw.rectangle(rect, fill=WHITE, outline=color, width=2)
    ty = rect[1] + 10
    for l in lines:
        draw.text((rect[0]+10, ty), l, fill=color, font=f)
        ty += f.size + 8


base = Image.open(FINAL + r'\render_main_flipped.png').convert("RGB")
W, H = base.size
PAD_R, PAD_T, PAD_B = 680, 110, 220
canvas = Image.new("RGB", (W+PAD_R, H+PAD_T+PAD_B), (255, 255, 255))
canvas.paste(base, (0, PAD_T))
draw = ImageDraw.Draw(canvas)

draw.text((40, 15), "JOYSTICK MOUNTING - VIEWED FROM BEHIND (INSIDE, THROUGH THE OPEN BOTTOM)",
          fill=RED, font=font)
draw.text((40, 55), "Top panel and main body are now ONE fused part - no seam, shown joined here.",
          fill=(80, 80, 80), font=font_sm)

joystick = (590, 324+PAD_T)
knob = (666, 304+PAD_T)
button = (740, 286+PAD_T)

callout(draw,
        "JOYSTICK HOLE - 2.7 cm round\n"
        "4x mounting pilot holes needed:\n"
        "0.2 cm dia, self-tapping M2\n"
        "Spacing: 19.5mm (PLACEHOLDER -\n"
        "NOT CONFIRMED - measure the real\n"
        "module before drilling)",
        joystick, (W+40, 420))

callout(draw,
        "Standoff boss (0.4cm tall, like the\n"
        "Pi standoffs) NOT added here - at the\n"
        "current 19.5mm spacing the screw\n"
        "positions land only 0.29mm past the\n"
        "hole edge, so any boss overlaps and\n"
        "breaks the hole. Needs the real\n"
        "measurement first.",
        joystick, (W+40, 780), color=ORANGE)

callout(draw, "KNOB HOLE\n0.5 cm round", knob, (W+40, 220))

ty = H+PAD_T+30
for line in [
    "This view looks up into the box through the open bottom (bottom panel not",
    "yet attached), at the INSIDE face of the front wall - the joystick's mounting",
    "screws thread in from here, not from the front.",
]:
    draw.text((40, ty), line, fill=RED, font=font_sm)
    ty += 36

canvas.save(FINAL + r'\dimensions_joystick_mounting.png')
print("saved")
