from PIL import Image, ImageDraw, ImageFont
import math

SRC = r'C:\Users\haals\AppData\Local\Temp\osc\final\preview_assembly.png'
OUT = r'C:\Users\haals\AppData\Local\Temp\osc\final\dimensions_front.png'

base = Image.open(SRC).convert("RGB")
W, H = base.size
PAD_R, PAD_B = 480, 260
canvas = Image.new("RGB", (W+PAD_R, H+PAD_B), (255,255,255))
canvas.paste(base, (0,0))
draw = ImageDraw.Draw(canvas)

try:
    font = ImageFont.truetype("arialbd.ttf", 30)
    font_sm = ImageFont.truetype("arialbd.ttf", 24)
except Exception:
    font = font_sm = ImageFont.load_default()

RED = (200,20,20)
WHITE = (255,255,255)

def arrow_line(p1, p2, color=RED, width=4, head=13):
    draw.line([p1,p2], fill=color, width=width)
    ang = math.atan2(p1[1]-p2[1], p1[0]-p2[0])
    for da in (0.35,-0.35):
        hx = p2[0] + head*math.cos(ang+da)
        hy = p2[1] + head*math.sin(ang+da)
        draw.line([p2,(hx,hy)], fill=color, width=width)

def dot(p, r=8, color=RED):
    draw.ellipse([p[0]-r,p[1]-r,p[0]+r,p[1]+r], fill=color)

def callout(text, target, box_pos, f=font_sm, align="left"):
    dot(target)
    draw.line([target, box_pos], fill=RED, width=3)
    lines = text.split("\n")
    widths = [draw.textbbox((0,0),l,font=f)[2] for l in lines]
    w = max(widths)+20
    h = len(lines)*(f.size+8)+16
    x,y = box_pos
    if align=="left":
        rect=[x, y-h/2, x+w, y+h/2]
    else:
        rect=[x-w, y-h/2, x, y+h/2]
    draw.rectangle(rect, fill=WHITE, outline=RED, width=2)
    ty = rect[1]+10
    for l in lines:
        tx = rect[0]+10
        draw.text((tx,ty), l, fill=RED, font=f)
        ty += f.size+8

# ---- feature points (original image coords) ----
screen_TL=(615,565); screen_TR=(1250,360)
joystick=(865,935)
knob=(942,902)
button=(1017,872)
spk_L=(720,1050)
spk_R=(1135,865)

# screen opening
callout("SCREEN OPENING\n31.5 x 17.9 cm", screen_TL, (W+40, 120), align="left")
draw.line([screen_TR,(W+40,120)], fill=RED, width=3)
dot(screen_TR)

# joystick
callout("JOYSTICK HOLE\n2.7 cm round", joystick, (W+40, 520))
# knob
callout("VOLUME KNOB\n0.5 cm round", knob, (W+40, 650))
# button
callout("POWER BUTTON\n0.5 x 0.7 cm oval", button, (W+40, 780))
# speaker right
callout("SPEAKER GRILLE (R)\n10.0 x 4.4 cm", spk_R, (W+40, 910))
# speaker left
callout("SPEAKER GRILLE (L)\n10.0 x 4.4 cm", spk_L, (300, H+80))

# overall dims (reuse bottom + left edges)
D=(563,565); E=(563,1130); C=(1290,320); F=(1290,1030); A=(280,345)
off=55
arrow_line((E[0],E[1]+off),(F[0],F[1]+off))
draw.text(((E[0]+F[0])/2-90,(E[1]+F[1])/2+off+16), "WIDTH 38.4 cm", fill=RED, font=font)
off=70
arrow_line((D[0]-off,D[1]),(E[0]-off,E[1]))
draw.text((D[0]-off-190,(D[1]+E[1])/2-15), "HEIGHT 26.0 cm", fill=RED, font=font)

canvas.save(OUT)
print("saved", OUT)
