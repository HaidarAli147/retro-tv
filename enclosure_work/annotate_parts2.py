from PIL import Image, ImageDraw, ImageFont
import math

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'

try:
    font = ImageFont.truetype("arialbd.ttf", 28)
    font_sm = ImageFont.truetype("arialbd.ttf", 23)
except Exception:
    font = font_sm = ImageFont.load_default()

RED = (200, 20, 20)
WHITE = (255, 255, 255)


def make_canvas(src, pad_r=560, pad_b=140, pad_t=0, pad_l=0):
    base = Image.open(src).convert("RGB")
    W, H = base.size
    canvas = Image.new("RGB", (W + pad_r + pad_l, H + pad_b + pad_t), (255, 255, 255))
    canvas.paste(base, (pad_l, pad_t))
    return canvas, ImageDraw.Draw(canvas), W, H


def arrow_line(draw, p1, p2, color=RED, width=4, head=13):
    draw.line([p1, p2], fill=color, width=width)
    ang = math.atan2(p1[1] - p2[1], p1[0] - p2[0])
    for da in (0.35, -0.35):
        hx = p2[0] + head * math.cos(ang + da)
        hy = p2[1] + head * math.sin(ang + da)
        draw.line([p2, (hx, hy)], fill=color, width=width)


def dot(draw, p, r=8, color=RED):
    draw.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=color)


def callout(draw, text, target, box_pos, f=font_sm, align="left"):
    dot(draw, target)
    draw.line([target, box_pos], fill=RED, width=3)
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


# =====================================================================
# BOTTOM PANEL
# =====================================================================
PAD_L = 260
canvas, draw, W, H = make_canvas(FINAL + r'\drill_bottom.png', pad_r=720, pad_b=60, pad_l=PAD_L)
corner_TL = (228+PAD_L, 633); corner_back = (1022+PAD_L, 378); corner_R = (1358+PAD_L, 578); corner_front = (507+PAD_L, 880)
pi_cluster = (390+PAD_L, 670)
uno_cluster = (680+PAD_L, 590)

off = 45
arrow_line(draw, (corner_front[0], corner_front[1]+off), (corner_R[0]-40, corner_R[1]+off*1.6))
draw.text(((corner_front[0]+corner_R[0])/2 - 90, (corner_front[1]+corner_R[1])/2 + off*1.4),
          "WIDTH 38.4 cm", fill=RED, font=font)
off = 40
arrow_line(draw, (corner_TL[0]-off, corner_TL[1]), (corner_front[0]-off*0.5, corner_front[1]))
draw.text((corner_TL[0]-off-230, (corner_TL[1]+corner_front[1])/2-15), "DEPTH 21.5 cm", fill=RED, font=font)

callout(draw, "CORNER HOLES - 4x\n0.34 cm dia (M3 clearance)\n0.75 cm in from each edge\nSCREW: M3 x 12mm self-tapping\n(same screw as the main body posts)",
        corner_front, (W+40, 120))
callout(draw, "RASPBERRY PI STANDOFFS - 4x\n0.65 cm post, 0.6 cm tall\n0.2 cm pilot (self-tap M2.5)\n58 x 49 mm rectangle\ncenter at (20.0, 12.0) cm from edge\nSCREW: M2.5 x 6mm self-tapping",
        pi_cluster, (W+40, 420))
callout(draw, "ARDUINO UNO STANDOFFS - 4x\n0.65 cm post, 0.6 cm tall\n0.25 cm pilot (self-tap M3)\nUno R3 hole pattern\ncenter at (13.0, 12.0) cm from edge\nSCREW: M3 x 6mm self-tapping",
        uno_cluster, (W+40, 780))
draw.text((40, 40), "BOTTOM PANEL - 38.4 x 21.5 x 0.3 cm, solid (no through-cuts)", fill=RED, font=font_sm)

canvas.save(FINAL + r'\dimensions_bottom.png')
print("saved bottom")

# =====================================================================
# BACKPLATE (laptop screen rear cover)
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL + r'\render_backplate.png', pad_r=40, pad_b=220, pad_t=40)
draw.text((40, 20), "SCREEN BACKPLATE (rear slide-in cover)", fill=RED, font=font)
draw.text((40, 70), "32.4 x 19.3 x 0.3 cm", fill=RED, font=font_sm)
draw.text((40, H+40+30), "NO holes - a plain flat plate. It slides into the frame's rear\n"
                          "channel and is held in place by the frame's retaining lip, not screwed down.",
          fill=RED, font=font_sm)
canvas.save(FINAL + r'\dimensions_backplate.png')
print("saved backplate")

# =====================================================================
# KNOB COVER
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL + r'\render_knob_cover.png', pad_r=620, pad_b=40)
center = (795, 555)
screws = [(862, 378), (408, 518), (730, 762), (1205, 590)]
draw.text((40, 30), "KNOB BACK-COVER PLATE - 2.5 x 2.5 x 0.3 cm", fill=RED, font=font_sm)
callout(draw, "CENTER HOLE\n0.5 cm dia\n(matches the 5mm knob hole)", center, (W+40, 300))
callout(draw, "MOUNTING SCREWS - 4x\n0.2 cm dia (self-tap M2)\n0.4 cm in from each edge",
        screws[0], (W+40, 560))
for s in screws[1:]:
    dot(draw, s)
    draw.line([s, (W+40, 560)], fill=RED, width=2)
canvas.save(FINAL + r'\dimensions_knob_cover.png')
print("saved knob cover")

# =====================================================================
# BUTTON COVER
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL + r'\render_button_cover.png', pad_r=620, pad_b=40)
center = (795, 555)
screws = [(862, 378), (408, 518), (730, 762), (1205, 590)]
draw.text((40, 30), "BUTTON BACK-COVER PLATE - 2.5 x 2.7 x 0.3 cm", fill=RED, font=font_sm)
callout(draw, "CENTER HOLE (oval)\n0.5 x 0.7 cm\n(matches the button hole)", center, (W+40, 300))
callout(draw, "MOUNTING SCREWS - 4x\n0.2 cm dia (self-tap M2)\n0.4 cm in from each edge",
        screws[0], (W+40, 560))
for s in screws[1:]:
    dot(draw, s)
    draw.line([s, (W+40, 560)], fill=RED, width=2)
canvas.save(FINAL + r'\dimensions_button_cover.png')
print("saved button cover")
