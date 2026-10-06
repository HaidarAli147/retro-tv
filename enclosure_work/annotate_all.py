from PIL import Image, ImageDraw, ImageFont
import math

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'

try:
    font = ImageFont.truetype("arialbd.ttf", 30)
    font_sm = ImageFont.truetype("arialbd.ttf", 24)
except Exception:
    font = font_sm = ImageFont.load_default()

RED = (200,20,20)
WHITE = (255,255,255)

def make_canvas(src, pad_r=480, pad_b=260, pad_l=0, pad_t=0):
    base = Image.open(src).convert("RGB")
    W,H = base.size
    canvas = Image.new("RGB", (W+pad_l+pad_r, H+pad_t+pad_b), (255,255,255))
    canvas.paste(base, (pad_l,pad_t))
    return canvas, ImageDraw.Draw(canvas), W, H

def arrow_line(draw, p1, p2, color=RED, width=4, head=13):
    draw.line([p1,p2], fill=color, width=width)
    ang = math.atan2(p1[1]-p2[1], p1[0]-p2[0])
    for da in (0.35,-0.35):
        hx = p2[0] + head*math.cos(ang+da)
        hy = p2[1] + head*math.sin(ang+da)
        draw.line([p2,(hx,hy)], fill=color, width=width)

def dot(draw, p, r=8, color=RED):
    draw.ellipse([p[0]-r,p[1]-r,p[0]+r,p[1]+r], fill=color)

def callout(draw, text, target, box_pos, f=font_sm, align="left"):
    dot(draw, target)
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
        draw.text((rect[0]+10,ty), l, fill=RED, font=f)
        ty += f.size+8

# =====================================================================
# BACK PANEL
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL+r'\drill_back.png', pad_r=520)
D=(540,415); E=(540,1030); C=(1290,300); F=(1290,865)
connector=(940,857); vent_L=(705,660); vent_R=(1205,525)

off=55
arrow_line(draw,(E[0],E[1]+off),(F[0],F[1]+off))
draw.text(((E[0]+F[0])/2-90,(E[1]+F[1])/2+off+16), "WIDTH 38.4 cm", fill=RED, font=font)
off=60
arrow_line(draw,(D[0]-off,D[1]),(E[0]-off,E[1]))
draw.text((D[0]-off-190,(D[1]+E[1])/2-15), "HEIGHT 26.0 cm", fill=RED, font=font)

callout(draw, "CONNECTOR OPENING\n18.3 x 4.0 cm\ncentered, 1.8cm up from bottom", connector, (W+40,600))
callout(draw, "BACK VENTS (near side)\ncols @ 4.0 / 6.5 cm from edge\n9 slots, 0.4 x 5.0 cm,\n1.5cm pitch, 9.0-21.0cm up", vent_L, (W+40,880))
callout(draw, "BACK VENTS (far side)\ncols @ 29.5 / 32.0 cm from edge\nsame pattern as near side", vent_R, (W+40,240))

canvas.save(FINAL+r'\dimensions_back.png')
print("saved back")

# =====================================================================
# TOP PANEL
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL+r'\drill_top.png', pad_r=680, pad_b=120)
left=(225,625); back=(1015,375); right=(1360,565); near=(505,880)
grid=(750,555)

off=50
arrow_line(draw,(near[0],near[1]+off),(right[0],right[1]+off*0.55))
draw.text(((near[0]+right[0])/2-90,(near[1]+right[1])/2+off+10), "WIDTH 38.4 cm", fill=RED, font=font)
off=45
arrow_line(draw,(near[0]-off,near[1]),(left[0]-off*0.9,left[1]-off*0.3))
draw.text((near[0]-off-210,(near[1]+left[1])/2-10), "DEPTH 21.5 cm", fill=RED, font=font)

callout(draw, "VENT GRID - 36 slots (4 cols x 9 rows)\n0.4 x 6.0 cm each\ncolumns @ 4.95 / 12.45 / 19.95 / 27.45 cm\nrows @ 8.0-17.6 cm from front edge, 1.2cm pitch",
        grid, (W+40,540), align="left")

canvas.save(FINAL+r'\dimensions_top.png')
print("saved top")

# =====================================================================
# SIDE WALL (front + one side wall visible)
# =====================================================================
canvas, draw, W, H = make_canvas(FINAL+r'\drill_side.png', pad_r=560)
side_vents=(1080,650)
D=(870,140); E=(870,1150)  # side wall's own front-back top/bottom-ish left edge for height ref (approx)
off=40

callout(draw, "SIDE WALL VENTS - 3 slots\n0.6 x 5.0 cm each\nat 3.0 / 9.0 / 14.8 cm from front edge\nheight 20.5 / 22.0 / 23.5 cm up from floor",
        side_vents, (W+40,600), align="left")
draw.text((40,40), "SIDE WALL: 21.5 (depth) x 26.0 (height) cm", fill=RED, font=font)

canvas.save(FINAL+r'\dimensions_side.png')
print("saved side")
