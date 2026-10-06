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


base = Image.open(FINAL + r'\render_backplate.png').convert("RGB")
W, H = base.size
PAD_R, PAD_B, PAD_T = 620, 260, 40
canvas = Image.new("RGB", (W+PAD_R, H+PAD_B+PAD_T), (255, 255, 255))
canvas.paste(base, (0, PAD_T))
draw = ImageDraw.Draw(canvas)

# corners as seen in render (screen-space pixel coords), shifted by PAD_T
TL = (363, 476+PAD_T)   # top-left hole
TR = (1188, 243+PAD_T)  # top-right hole
BL = (398, 984+PAD_T)   # bottom-left hole
BR = (1152, 690+PAD_T)  # bottom-right hole

draw.text((40, 20), "SCREEN BACKPLATE (rear cover) - 32.4 x 19.3 x 0.3 cm", fill=RED, font=font)

callout(draw, "MOUNTING SCREWS - 4x\n0.34 cm dia (M3 clearance)\n1.0 cm in from each edge\n(corner-to-corner: 30.4 x 17.3 cm)\nSCREW: M3 x 10-12mm self-tapping\n(same type as the main body posts)",
        TR, (W+40, 260))
dot(draw, TL); draw.line([TL, (W+40, 260)], fill=RED, width=2)
dot(draw, BR); draw.line([BR, (W+40, 260)], fill=RED, width=2)
dot(draw, BL); draw.line([BL, (W+40, 260)], fill=RED, width=2)

draw.text((40, H+PAD_T+40),
          "Screws through, self-tapping into whatever frame material sits behind\n"
          "each corner - confirm there is solid material there (not open slot) before\n"
          "drilling. Plate still seats in the slide channel; screws add real retention\n"
          "instead of relying on the friction fit alone.",
          fill=RED, font=font_sm)

canvas.save(FINAL + r'\dimensions_backplate.png')
print("saved")
