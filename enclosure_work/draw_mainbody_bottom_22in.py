"""Flat, to-scale drill sheet for the 22" main body seen UPSIDE DOWN
(looking into the open bottom), in the same style as the bottom-panel
sheet. Values match enclosure_22in.scad."""
from PIL import Image, ImageDraw, ImageFont
import math

OUT = r'C:\Users\haals\AppData\Local\Temp\osc\final22\dimensions_main_body_upside_down_22in.png'

W, D, t, corner_sq = 560, 215, 3, 15
pilot_d, hole_depth = 2.6, 7
# monitor side guides (from the scad): x positions and depth they reach from the front wall
panel_x0 = (W - 510) / 2
fit_clr, guide_t, slot, lip_t, shelf_z = 0.4, 2, 55 + 3 + 3*0.4, 2, 70
gl = panel_x0 - fit_clr - guide_t
gr = panel_x0 + 510 + fit_clr
guide_depth = t + slot + lip_t

S = 2.6
X0, Y0 = 200, 210
CW, CH = 2050, 1250
RED, BLUE, GREEN, GREY, BLACK, ORANGE = (200, 20, 20), (20, 70, 200), (0, 120, 60), (90, 90, 90), (0, 0, 0), (200, 100, 0)

img = Image.new("RGB", (CW, CH), "white")
d = ImageDraw.Draw(img)
f = lambda n: ImageFont.truetype("arialbd.ttf", n)
F_T, F, F_S = f(34), f(24), f(20)


def P(x, y):
    return X0 + x*S, Y0 + (D - y)*S


def arrow_dim(p1, p2, text, color=BLUE, font=F, off=(0, 0)):
    d.line([p1, p2], fill=color, width=3)
    for a, b in ((p1, p2), (p2, p1)):
        ang = math.atan2(a[1]-b[1], a[0]-b[0])
        for da in (0.4, -0.4):
            d.line([b, (b[0]+14*math.cos(ang+da), b[1]+14*math.sin(ang+da))], fill=color, width=3)
    if text:
        mx, my = (p1[0]+p2[0])/2 + off[0], (p1[1]+p2[1])/2 + off[1]
        tw = d.textbbox((0, 0), text, font=font)[2]
        d.rectangle([mx-tw/2-6, my-16, mx+tw/2+6, my+16], fill="white")
        d.text((mx-tw/2, my-13), text, fill=color, font=font)


d.text((40, 25), "MAIN BODY (22\") - UPSIDE DOWN, looking into the open bottom - 56.0 x 21.5 cm, 39.0 cm tall",
       fill=RED, font=F_T)
d.text((40, 72), "Only the 4 corner-post holes are drilled from this side (they take the bottom panel's screws). "
                 "Drawn to scale.", fill=GREY, font=F)
d.text((40, 106), "Monitor size is still a PLACEHOLDER (typical 22\") - confirm the monitor before cutting.",
       fill=ORANGE, font=F_S)

# outer outline + walls
d.rectangle([P(0, D), P(W, 0)], fill=(200, 230, 200), outline=BLACK, width=4)
d.rectangle([P(t, D-t), P(W-t, t)], fill=(245, 245, 245), outline=GREY, width=2)
d.text((P(W/2, 0)[0]-110, P(0, 0)[1]+12), "FRONT WALL (screen side)", fill=BLACK, font=F_S)
d.text((P(W/2, D)[0]-60, P(0, D)[1]-36), "BACK WALL", fill=BLACK, font=F_S)

# monitor guides (they start 7 cm up inside, shown for reference)
for gx in (gl, gr):
    d.rectangle([P(gx, guide_depth), P(gx+guide_t, t)], fill=ORANGE)
d.text((P(gl, 0)[0]+14, P(0, guide_depth)[1]-30), "monitor guide (starts 7 cm up inside)", fill=ORANGE, font=F_S)

# corner posts + pilot holes
corners = [(0, 0), (W-corner_sq, 0), (0, D-corner_sq), (W-corner_sq, D-corner_sq)]
holes = []
for cx0, cy0 in corners:
    d.rectangle([P(cx0, cy0+corner_sq), P(cx0+corner_sq, cy0)], fill=(120, 170, 120), outline=BLACK, width=2)
    hx, hy = cx0 + corner_sq/2, cy0 + corner_sq/2
    holes.append((hx, hy))
    px, py = P(hx, hy); r = pilot_d/2*S + 4
    d.ellipse([px-r, py-r, px+r, py+r], fill=RED)

# dimensions
arrow_dim((P(0, 0)[0], P(0, 0)[1]+70), (P(W, 0)[0], P(W, 0)[1]+70), "WIDTH 56.0 cm", color=RED)
arrow_dim((P(0, 0)[0]-80, P(0, D)[1]), (P(0, 0)[0]-80, P(0, 0)[1]), "DEPTH 21.5 cm", color=RED, font=F_S)
# post size + hole inset, front-right corner
px, py = P(W, 0)
arrow_dim((px+30, P(0, corner_sq)[1]), (px+30, py), "", color=GREEN)
d.text((px+50, py-58), "corner post", fill=GREEN, font=F_S)
d.text((px+50, py-34), "1.5 x 1.5 cm", fill=GREEN, font=F_S)
hx, hy = P(W-7.5, 7.5)
d.line([(hx, hy), (px+40, hy-120)], fill=RED, width=2)
d.text((px+50, hy-150), "hole 0.75 cm in", fill=RED, font=F_S)
d.text((px+50, hy-126), "from each edge", fill=RED, font=F_S)
# wall thickness, back-left
wx, wy = P(0, D/2)
d.line([(wx, wy), (wx+30*S, wy-40)], fill=BLUE, width=2)
d.text((wx+30*S+8, wy-56), "walls 0.3 cm thick", fill=BLUE, font=F_S)

# info table
ty = Y0 + D*S + 130
d.text((40, ty), "RED - CORNER-POST PILOT HOLES (4x)", fill=RED, font=F)
d.text((40, ty+34), "drill 0.26 cm wide, 0.7 cm deep, straight down into the centre of each post", fill=GREY, font=F_S)
d.text((40, ty+60), "SCREW: M3 x 12mm self-tapping (goes through the 0.3 cm bottom panel into the post)",
       fill=GREY, font=F_S)
for i, (x, y) in enumerate(holes):
    d.text((40, ty+96+i*30), "%d)  %.2f cm from the side,  %.2f cm from the front" % (i+1, x/10, y/10),
           fill=BLACK, font=F_S)
d.text((1060, ty), "GOOD TO KNOW", fill=BLUE, font=F)
notes = ["- The pattern is symmetric: every hole is 0.75 cm in from both",
         "  outside edges, so it doesn't matter which way the box is turned.",
         "- Nothing else is drilled from this side. The joystick, knob, button,",
         "  speaker grilles and screen are cut in the FRONT wall (see the front",
         "  drill sheet).",
         "- Bottom panel holes line up exactly with these (same 0.75 cm inset)."]
for i, n in enumerate(notes):
    d.text((1060, ty+40+i*28), n, fill=BLACK, font=F_S)

img = img.crop((0, 0, CW, ty + 96 + 4*30 + 40))
img.save(OUT)
print("saved", OUT, img.size)
