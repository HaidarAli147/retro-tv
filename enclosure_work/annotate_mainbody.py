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


def dot(draw, p, r=9, color=RED):
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


base = Image.open(FINAL + r'\drill_front.png').convert("RGB")
W, H = base.size
PAD_R, PAD_B, PAD_T = 680, 200, 40
canvas = Image.new("RGB", (W+PAD_R, H+PAD_B+PAD_T), (255, 255, 255))
canvas.paste(base, (0, PAD_T))
draw = ImageDraw.Draw(canvas)

# the 4 small red corner-post dots already baked into drill_front.png by
# DRILL_MARKERS, located at the top-panel/bottom-panel screw positions
near_top = (297, 353+PAD_T)
far_top = (1004, 158+PAD_T)
near_bottom = (541, 546+PAD_T)
far_bottom = (1294, 306+PAD_T)

draw.text((40, 5), "MAIN BODY (side_frame) - CORNER POST SCREWS", fill=RED, font=font)

callout(draw,
        "CORNER POSTS - 4x, one under each corner\n"
        "15 x 15 mm square post, full box height\n"
        "Pilot hole INTO post: 0.26 cm dia, 0.7 cm deep\n"
        "(self-tap M3)\n"
        "Clearance hole THROUGH top/bottom panel:\n"
        "0.34 cm dia (matches the panel corner holes)\n"
        "SCREW: M3 x 12mm self-tapping\n"
        "(same screw joins top panel, bottom panel,\n"
        "and the backplate to this same frame)",
        far_top, (W+40, 420))
dot(draw, near_top); draw.line([near_top, (W+40, 420)], fill=RED, width=2)
dot(draw, near_bottom); draw.line([near_bottom, (W+40, 420)], fill=RED, width=2)
dot(draw, far_bottom); draw.line([far_bottom, (W+40, 420)], fill=RED, width=2)

draw.text((40, H+PAD_T+30),
          "One screw type (M3 x 12mm self-tapping) ties the whole enclosure together:\n"
          "top panel, bottom panel, and backplate all screw into these same 4 corner posts.",
          fill=RED, font=font_sm)

canvas.save(FINAL + r'\dimensions_main_body_screws.png')
print("saved")
