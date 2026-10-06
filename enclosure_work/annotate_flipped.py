from PIL import Image, ImageDraw, ImageFont
import math

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'

try:
    font = ImageFont.truetype("arialbd.ttf", 30)
    font_sm = ImageFont.truetype("arialbd.ttf", 24)
except Exception:
    font = font_sm = ImageFont.load_default()

RED = (200, 20, 20)
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


def callout(draw, text, targets, box_pos, f=font_sm, align="left"):
    if isinstance(targets, tuple):
        targets = [targets]
    for t in targets:
        dot(draw, t)
        draw.line([t, box_pos], fill=RED, width=3)
    lines = text.split("\n")
    widths = [draw.textbbox((0, 0), l, font=f)[2] for l in lines]
    w = max(widths) + 20
    h = len(lines) * (f.size + 8) + 16
    x, y = box_pos
    if align == "left":
        rect = [x, y - h/2, x + w, y + h/2]
    else:
        rect = [x - w, y - h/2, x, y + h/2]
    draw.rectangle(rect, fill=WHITE, outline=RED, width=2)
    ty = rect[1] + 10
    for l in lines:
        draw.text((rect[0]+10, ty), l, fill=RED, font=f)
        ty += f.size + 8


base = Image.open(FINAL + r'\render_main_flipped.png').convert("RGB")
W, H = base.size
PAD_R, PAD_T, PAD_B = 620, 90, 140
canvas = Image.new("RGB", (W+PAD_R, H+PAD_T+PAD_B), (255, 255, 255))
canvas.paste(base, (0, PAD_T))
draw = ImageDraw.Draw(canvas)

draw.text((40, 15), "MAIN BODY - TOP PANEL NOW PERMANENTLY JOINED, VIEWED UPSIDE DOWN",
          fill=RED, font=font)

near_left = (285, 347+PAD_T); far_back = (999, 157+PAD_T)
far_right = (1294, 306+PAD_T); near_front = (541, 540+PAD_T)

callout(draw,
        "BOTTOM PANEL SCREW HOLES - 4x\n"
        "(the same 4 corner posts as before -\n"
        "the top panel side is now sealed shut,\n"
        "these are the only screws left to do)\n"
        "0.34 cm dia, SCREW: M3 x 12mm self-tapping",
        [near_left, far_back, far_right, near_front], (W+40, 400))

draw.text((40, H+PAD_T+10),
          "This is the box flipped bottom-up: the vent grid you see through the\n"
          "opening is the top panel, fused flush with no gap. The open face toward\n"
          "you is the bottom - screw the bottom panel on here.",
          fill=RED, font=font_sm)

canvas.save(FINAL + r'\dimensions_main_body_flipped.png')
print("saved")
