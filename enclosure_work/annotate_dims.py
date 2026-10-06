from PIL import Image, ImageDraw, ImageFont
import math

SRC = r'C:\Users\haals\AppData\Local\Temp\osc\final\preview_assembly.png'
OUT = r'C:\Users\haals\AppData\Local\Temp\osc\final\dimensions.png'

im = Image.open(SRC).convert("RGB")
draw = ImageDraw.Draw(im)

try:
    font = ImageFont.truetype("arialbd.ttf", 34)
except Exception:
    font = ImageFont.load_default()

RED = (200, 20, 20)
WHITE = (255, 255, 255)

def arrow_line(p1, p2, color=RED, width=4, head=14):
    draw.line([p1, p2], fill=color, width=width)
    for (a, b) in [(p1, p2), (p2, p1)]:
        ang = math.atan2(b[1]-a[1], b[0]-a[0])
        for da in (0.35, -0.35):
            hx = b[0] - head*math.cos(ang+da)
            hy = b[1] - head*math.sin(ang+da)
            draw.line([b, (hx, hy)], fill=color, width=width)

def label(text, pos, anchor="mm"):
    x, y = pos
    bbox = draw.textbbox((0, 0), text, font=font)
    w, h = bbox[2]-bbox[0], bbox[3]-bbox[1]
    pad = 6
    draw.rectangle([x-w/2-pad, y-h/2-pad-4, x+w/2+pad, y+h/2+pad-4], fill=WHITE, outline=RED, width=2)
    draw.text((x-w/2, y-h/2-8), text, fill=RED, font=font)

# Approximate box-edge endpoints read off the render (1600x1200)
D = (563, 565)    # front-top-left corner (top of the height edge)
E = (563, 1130)   # front-bottom-left corner
C = (1290, 320)   # front-top-right corner
F = (1290, 1030)  # front-bottom-right corner
A = (280, 345)    # back-top-left corner (top of the depth edge)

# WIDTH - offset below the bottom front edge
off = 55
arrow_line((E[0], E[1]+off), (F[0], F[1]+off))
label("WIDTH  38.4 cm", ((E[0]+F[0])/2, (E[1]+F[1])/2 + off + 34))

# HEIGHT - offset left of the front-left vertical edge
off = 70
arrow_line((D[0]-off, D[1]), (E[0]-off, E[1]))
label("HEIGHT  26.0 cm", (D[0]-off-95, (D[1]+E[1])/2))

# DEPTH - offset above the top-left depth edge
off = 40
arrow_line((A[0]-off*0.4, A[1]-off), (D[0]-off*0.4, D[1]-off))
label("DEPTH  21.5 cm", ((A[0]+D[0])/2 - off*1.6, (A[1]+D[1])/2 - off - 10))

im.save(OUT)
print("saved", OUT)
