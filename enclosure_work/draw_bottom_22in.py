"""Flat, to-scale top view of the 22" enclosure's bottom panel, with every
hole position printed on the drawing (values match enclosure_22in.scad)."""
from PIL import Image, ImageDraw, ImageFont

OUT = r'C:\Users\haals\AppData\Local\Temp\osc\final22\dimensions_bottom_22in.png'

# --- values from enclosure_22in.scad ---
W, D = 560, 215                 # panel width (X) and depth (Y), mm; Y=0 is the FRONT
corner_sq, hole_d = 15, 3.4
corner_holes = [(corner_sq/2, corner_sq/2), (W-corner_sq/2, corner_sq/2),
                (corner_sq/2, D-corner_sq/2), (W-corner_sq/2, D-corner_sq/2)]
pi = [(20, 120), (20, 169), (78, 120), (78, 169)]
uno0 = (130, 120)
uno = [(uno0[0]+x, uno0[1]+y) for x, y in [(15.24, 2.54), (15.24, 50.80), (66.04, 17.78), (66.04, 45.72)]]

S = 2.6                          # px per mm
X0, Y0 = 200, 210                # drawing origin = panel's BACK-left corner on screen
CW, CH = 2050, 1400
RED, BLUE, GREEN, GREY, BLACK = (200, 20, 20), (20, 70, 200), (0, 120, 60), (90, 90, 90), (0, 0, 0)

img = Image.new("RGB", (CW, CH), "white")
d = ImageDraw.Draw(img)
f = lambda n: ImageFont.truetype("arialbd.ttf", n)
F_T, F, F_S = f(34), f(24), f(20)


def P(x, y):
    """mm (front-left origin) -> px. Front edge is drawn at the bottom."""
    return X0 + x*S, Y0 + (D - y)*S


def arrow_dim(p1, p2, text, color=BLUE, off=(0, 0), font=F):
    d.line([p1, p2], fill=color, width=3)
    for a, b in ((p1, p2), (p2, p1)):
        import math
        ang = math.atan2(a[1]-b[1], a[0]-b[0])
        for da in (0.4, -0.4):
            d.line([b, (b[0]+14*math.cos(ang+da), b[1]+14*math.sin(ang+da))], fill=color, width=3)
    mx, my = (p1[0]+p2[0])/2 + off[0], (p1[1]+p2[1])/2 + off[1]
    tw = d.textbbox((0, 0), text, font=font)[2]
    d.rectangle([mx-tw/2-6, my-16, mx+tw/2+6, my+16], fill="white")
    d.text((mx-tw/2, my-13), text, fill=color, font=font)


def cm(v):
    return ("%.2f" % (v/10)).rstrip('0').rstrip('.') + " cm"


# title
d.text((40, 25), "BOTTOM PANEL (22\" version) - 56.0 x 21.5 x 0.3 cm - seen from ABOVE", fill=RED, font=F_T)
d.text((40, 72), "All positions measured from the FRONT-LEFT corner (the screen side is FRONT). "
                 "Drawn to scale.", fill=GREY, font=F)
d.text((40, 106), "Monitor size is still a PLACEHOLDER (typical 22\") - this panel's size follows the box, "
                  "so confirm the monitor before cutting.", fill=(200, 100, 0), font=F_S)

# panel outline
d.rectangle([P(0, D), P(W, 0)], fill=(236, 214, 236), outline=BLACK, width=4)
d.text((P(W/2, 0)[0]-60, P(0, 0)[1]+12), "FRONT (screen side)", fill=BLACK, font=F_S)
d.text((P(W/2, D)[0]-30, P(0, D)[1]-36), "BACK", fill=BLACK, font=F_S)

# holes
for x, y in corner_holes:
    cx, cy = P(x, y); r = hole_d/2*S + 3
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=RED)
for pts, col in ((pi, GREEN), (uno, BLUE)):
    for x, y in pts:
        cx, cy = P(x, y); r = 6.5/2*S
        d.ellipse([cx-r, cy-r, cx+r, cy+r], outline=col, width=4)
        d.ellipse([cx-4, cy-4, cx+4, cy+4], fill=col)

# overall dimensions
arrow_dim((P(0, 0)[0], P(0, 0)[1]+70), (P(W, 0)[0], P(W, 0)[1]+70), "WIDTH 56.0 cm", color=RED)
arrow_dim((P(0, 0)[0]-80, P(0, D)[1]), (P(0, 0)[0]-80, P(0, 0)[1]), "DEPTH 21.5 cm", color=RED, off=(0, 0), font=F_S)

# corner hole inset (front-right corner)
cx, cy = P(W-7.5, 7.5)
arrow_dim((P(W, 7.5)[0], cy), (cx, cy), "", color=RED)
d.text((P(W, 0)[0]+16, cy-14), "0.75 cm in from", fill=RED, font=F_S)
d.text((P(W, 0)[0]+16, cy+10), "each edge (all 4)", fill=RED, font=F_S)

# Pi block dimensions
a, b = P(20, 169), P(78, 169)
arrow_dim((a[0], a[1]-40), (b[0], b[1]-40), "5.8 cm", color=GREEN, font=F_S)
a, b = P(78, 120), P(78, 169)
arrow_dim((a[0]+40, a[1]), (b[0]+40, b[1]), "4.9 cm", color=GREEN, font=F_S)

# hole table (right side)
tx, ty = P(W, 0)[0] - 640, P(0, D)[1] + 30
rows = [("RED - CORNER HOLES (4x)", RED, "0.34 cm through-hole, M3 x 12mm screw", [(x, y) for x, y in corner_holes]),
        ("GREEN - RASPBERRY PI STANDOFFS (4x)", GREEN, "post 0.65 cm wide, 0.6 cm tall, 0.2 cm pilot, M2.5 x 6mm", pi),
        ("BLUE - ARDUINO UNO STANDOFFS (4x)", BLUE, "post 0.65 cm wide, 0.6 cm tall, 0.25 cm pilot, M3 x 6mm", uno)]
ty = Y0 + D*S + 130
col_x = [40, 700, 1360]
for (title, col, spec, pts), cx0 in zip(rows, col_x):
    d.text((cx0, ty), title, fill=col, font=F)
    d.text((cx0, ty+34), spec, fill=GREY, font=F_S)
    for i, (x, y) in enumerate(pts):
        d.text((cx0, ty+70+i*30), "%d)  %s from left,  %s from front" % (i+1, cm(x), cm(y)), fill=BLACK, font=F_S)

img = img.crop((0, 0, CW, ty + 70 + 4*30 + 40))
img.save(OUT)
print("saved", OUT, img.size)
