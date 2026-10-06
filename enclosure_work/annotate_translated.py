import sys
sys.path.insert(0, r'C:\Users\haals\AppData\Local\Temp\osc')
from PIL import Image, ImageDraw
import math
from shape_text import draw_shaped, draw_bidi_line, shape_line, _split_bidi_runs

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'
ARIAL = r'C:\Windows\Fonts\arial.ttf'
ARIALBD = r'C:\Windows\Fonts\arialbd.ttf'
NIRMALA = r'C:\Windows\Fonts\Nirmala.ttc'

RED = (200, 20, 20)
WHITE = (255, 255, 255)

TITLE_SZ = 30
BODY_SZ = 24


def measure(lines, lang):
    """Returns (max_width, line_height) using the same fonts/sizes draw() uses."""
    w = 0
    h = 0
    for line in lines:
        if lang == 'ar':
            ww, hh = draw_bidi_line(Image.new("RGB", (4, 4)), line, (0, 0), ARIALBD, 0, ARIALBD,
                                     BODY_SZ, RED, align="left")
        else:
            ww, hh = draw_shaped(Image.new("RGB", (4, 4)), line, (0, 0), NIRMALA, BODY_SZ, RED,
                                  face_index=0, rtl=False)
        w = max(w, ww)
        h = max(h, hh)
    return w, h


def draw_line(canvas, line, x, y, lang, size=BODY_SZ, align="left", color=RED):
    if lang == 'ar':
        return draw_bidi_line(canvas, line, (x, y), ARIALBD, 0, ARIALBD, size, color, align=align)
    else:
        a = "left" if align == "left" else ("right" if align == "right" else "center")
        return draw_shaped(canvas, line, (x, y), NIRMALA, size, color, face_index=0,
                            rtl=False, align=a)


def arrow_line(draw, p1, p2, color=RED, width=4, head=13):
    draw.line([p1, p2], fill=color, width=width)
    ang = math.atan2(p1[1] - p2[1], p1[0] - p2[0])
    for da in (0.35, -0.35):
        hx = p2[0] + head * math.cos(ang + da)
        hy = p2[1] + head * math.sin(ang + da)
        draw.line([p2, (hx, hy)], fill=color, width=width)


def dot(draw, p, r=9, color=RED):
    draw.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=color)


def callout(canvas, draw, lines, targets, box_pos, lang, box_align="left"):
    """targets: single (x,y) or list of (x,y). box_pos: anchor point;
    box_align 'left' -> box extends right from box_pos.x; 'right' -> extends left."""
    if isinstance(targets, tuple):
        targets = [targets]
    for t in targets:
        dot(draw, t)
        draw.line([t, box_pos], fill=RED, width=2)

    max_w, line_h = measure(lines, lang)
    pad = 14
    box_w = max_w + pad * 2
    box_h = len(lines) * (line_h + 10) + pad * 2 - 10
    x, y = box_pos
    if box_align == "left":
        rect = [x, y - box_h/2, x + box_w, y + box_h/2]
        text_x0 = x + pad
        text_align = "left"
    else:
        rect = [x - box_w, y - box_h/2, x, y + box_h/2]
        text_x0 = x - pad
        text_align = "right"

    draw.rectangle(rect, fill=WHITE, outline=RED, width=2)
    ty = rect[1] + pad
    for line in lines:
        draw_line(canvas, line, text_x0, ty, lang, align=text_align)
        ty += line_h + 10


def title_text(canvas, draw, text, x, y, lang):
    draw_line(canvas, text, x, y, lang, size=TITLE_SZ, align="left")


def make_canvas(src, pad_r, pad_b, pad_t=0, pad_l=0):
    base = Image.open(src).convert("RGB")
    W, H = base.size
    canvas = Image.new("RGB", (W + pad_r + pad_l, H + pad_b + pad_t), (255, 255, 255))
    canvas.paste(base, (pad_l, pad_t))
    return canvas, ImageDraw.Draw(canvas), W, H


# =====================================================================
# TEXT CONTENT (English keys -> {ar, hi})
# =====================================================================
T = {
    'mb_title': {'ar': "الهيكل الرئيسي (الإطار الجانبي) - براغي الأعمدة الزاوية",
                 'hi': "मुख्य ढांचा (साइड फ्रेम) - कोने के खंभों के पेंच"},
    'mb_callout': {
        'ar': ["أعمدة الزوايا - 4 قطع، واحد أسفل كل زاوية",
               "عمود مربع 15 × 15 مم، بارتفاع الصندوق بالكامل",
               "ثقب توجيهي داخل العمود: قطر 0.26 سم، عمق 0.7 سم",
               "(ذاتي التنصيت M3)",
               "ثقب تخليص عبر اللوح السفلي:",
               "قطر 0.34 سم (يطابق ثقوب زوايا اللوح)",
               "البرغي: M3 x 12mm ذاتي التنصيت",
               "(نفس البرغي يربط اللوح السفلي واللوح الخلفي",
               "بهذا الإطار - اللوح العلوي مثبّت بالفعل)"],
        'hi': ["कोने के खंभे - 4x, हर कोने के नीचे एक",
               "15 x 15 मिमी वर्गाकार खंभा, पूरे बॉक्स की ऊंचाई तक",
               "खंभे में पायलट छेद: व्यास 0.26 सेमी, गहराई 0.7 सेमी",
               "(सेल्फ-टैप M3)",
               "नीचे के पैनल के आर-पार क्लीयरेंस छेद:",
               "व्यास 0.34 सेमी (पैनल के कोने के छेद जैसा)",
               "पेंच: M3 x 12mm सेल्फ-टैपिंग",
               "(यही पेंच नीचे के पैनल और बैकप्लेट को",
               "इस फ्रेम से जोड़ता है - ऊपर का पैनल पहले से जुड़ा है)"],
    },
    'mb_caption': {
        'ar': ["ملاحظة: النجار وصل اللوح العلوي بالهيكل الرئيسي بشكل دائم بالفعل.",
               "يبقى فقط اللوح السفلي واللوح الخلفي يُبرغيان في نفس أعمدة الزوايا الأربعة",
               "بنوع البرغي M3 x 12mm ذاتي التنصيت."],
        'hi': ["ध्यान दें: बढ़ई ने ऊपर के पैनल को मुख्य ढांचे से पहले ही स्थायी रूप से जोड़ दिया है।",
               "अब सिर्फ नीचे का पैनल और बैकप्लेट इन्हीं 4 कोने के खंभों में",
               "M3 x 12mm सेल्फ-टैपिंग पेंच से जुड़ते हैं।"],
    },

    'bp_title': {'ar': "اللوح السفلي - 38.4 × 21.5 × 0.3 سم، مصمت (بدون قطع نافذ)",
                 'hi': "निचला पैनल - 38.4 x 21.5 x 0.3 सेमी, ठोस (कोई आर-पार कटाव नहीं)"},
    'bp_width': {'ar': "العرض 38.4 سم", 'hi': "चौड़ाई 38.4 सेमी"},
    'bp_depth': {'ar': "العمق 21.5 سم", 'hi': "गहराई 21.5 सेमी"},
    'bp_corner': {
        'ar': ["ثقوب الزوايا - 4 قطع", "قطر 0.34 سم (تخليص M3)", "0.75 سم من كل حافة",
               "البرغي: M3 x 12mm ذاتي التنصيت", "(نفس برغي أعمدة الهيكل الرئيسي)"],
        'hi': ["कोने के छेद - 4x", "व्यास 0.34 सेमी (M3 क्लीयरेंस)", "हर किनारे से 0.75 सेमी अंदर",
               "पेंच: M3 x 12mm सेल्फ-टैपिंग", "(मुख्य ढांचे के खंभों जैसा ही पेंच)"],
    },
    'bp_pi': {
        'ar': ["حوامل رازبيري باي - 4 قطع", "عمود 0.65 سم، ارتفاع 0.6 سم",
               "ثقب توجيهي 0.2 سم (ذاتي التنصيت M2.5)", "مستطيل 58 × 49 مم",
               "المركز عند (20.0، 12.0) سم من الحافة", "البرغي: M2.5 x 6mm ذاتي التنصيت"],
        'hi': ["रास्पबेरी पाई स्टैंडऑफ़ - 4x", "0.65 सेमी खंभा, 0.6 सेमी ऊँचा",
               "0.2 सेमी पायलट (सेल्फ-टैप M2.5)", "58 x 49 मिमी आयत",
               "केंद्र किनारे से (20.0, 12.0) सेमी पर", "पेंच: M2.5 x 6mm सेल्फ-टैपिंग"],
    },
    'bp_uno': {
        'ar': ["حوامل أردوينو أونو - 4 قطع", "عمود 0.65 سم، ارتفاع 0.6 سم",
               "ثقب توجيهي 0.25 سم (ذاتي التنصيت M3)", "نمط ثقوب Uno R3",
               "المركز عند (13.0، 12.0) سم من الحافة", "البرغي: M3 x 6mm ذاتي التنصيت"],
        'hi': ["आर्डुइनो Uno स्टैंडऑफ़ - 4x", "0.65 सेमी खंभा, 0.6 सेमी ऊँचा",
               "0.25 सेमी पायलट (सेल्फ-टैप M3)", "Uno R3 छेद पैटर्न",
               "केंद्र किनारे से (13.0, 12.0) सेमी पर", "पेंच: M3 x 6mm सेल्फ-टैपिंग"],
    },

    'pl_title': {'ar': "اللوح الخلفي للشاشة (الغطاء الخلفي) - 32.4 × 19.3 × 0.3 سم",
                 'hi': "स्क्रीन बैकप्लेट (पिछला कवर) - 32.4 x 19.3 x 0.3 सेमी"},
    'pl_callout': {
        'ar': ["براغي التثبيت - 4 قطع", "قطر 0.34 سم (تخليص M3)", "1.0 سم من كل حافة",
               "(من زاوية لزاوية: 30.4 × 17.3 سم)",
               "البرغي: M3 x 10-12mm ذاتي التنصيت",
               "(نفس نوع براغي أعمدة الهيكل الرئيسي)"],
        'hi': ["माउंटिंग पेंच - 4x", "व्यास 0.34 सेमी (M3 क्लीयरेंस)", "हर किनारे से 1.0 सेमी अंदर",
               "(कोने से कोने तक: 30.4 x 17.3 सेमी)",
               "पेंच: M3 x 10-12mm सेल्फ-टैपिंग",
               "(मुख्य ढांचे के खंभों जैसा ही प्रकार)"],
    },
    'mbf_title': {'ar': "الهيكل الرئيسي - اللوح العلوي مثبّت الآن بشكل دائم، بمنظور مقلوب",
                  'hi': "मुख्य ढांचा - ऊपर का पैनल अब स्थायी रूप से जुड़ा हुआ है, उल्टा देखा गया"},
    'mbf_callout': {
        'ar': ["ثقوب براغي اللوح السفلي - 4 قطع",
               "(نفس أعمدة الزوايا الأربعة كما كانت -",
               "جانب اللوح العلوي مغلق الآن بإحكام،",
               "وهذه هي البراغي الوحيدة المتبقية)",
               "قطر 0.34 سم، البرغي: M3 x 12mm ذاتي التنصيت"],
        'hi': ["निचले पैनल के पेंच छेद - 4x",
               "(वही पहले वाले 4 कोने के खंभे -",
               "ऊपर के पैनल की तरफ अब पूरी तरह बंद है,",
               "बस यही पेंच बाकी रह गए हैं)",
               "व्यास 0.34 सेमी, पेंच: M3 x 12mm सेल्फ-टैपिंग"],
    },
    'mbf_caption': {
        'ar': ["هذا هو الصندوق مقلوبًا من الأسفل للأعلى: شبكة التهوية التي تراها عبر",
               "الفتحة هي اللوح العلوي، ملتحم تمامًا بدون أي فجوة. الوجه المفتوح",
               "الذي يواجهك هو الأسفل - قم ببرغي اللوح السفلي هنا."],
        'hi': ["यह बॉक्स है नीचे से ऊपर पलटा हुआ: जो वेंट ग्रिल आपको खुलने वाली जगह से",
               "दिख रही है वह ऊपर का पैनल है, बिना किसी गैप के पूरी तरह जुड़ा हुआ। आपकी तरफ",
               "जो खुला हिस्सा है वह नीचे का हिस्सा है - यहीं पर निचला पैनल पेंच करें।"],
    },

    'pl_caption': {
        'ar': ["براغي عبر اللوح، تُثبَّت ذاتيًا في أي مادة إطار خلفها",
               "كل زاوية - تأكد من وجود مادة مصمتة هناك (وليست فتحة مفتوحة) قبل",
               "الحفر. اللوح لا يزال يستقر في قناة الانزلاق؛ البراغي تضيف تثبيتًا حقيقيًا",
               "بدلاً من الاعتماد على تثبيت الاحتكاك فقط."],
        'hi': ["पेंच आर-पार, पीछे जो भी फ्रेम सामग्री हो उसमें सेल्फ-टैप होंगे",
               "हर कोना - ड्रिल करने से पहले पुष्टि करें कि वहाँ ठोस सामग्री है (खुला स्लॉट नहीं)",
               "प्लेट अभी भी स्लाइड चैनल में बैठती है; पेंच असली पकड़ जोड़ते हैं",
               "सिर्फ घर्षण फिट पर निर्भर रहने के बजाय।"],
    },
}


def build_main_body(lang):
    canvas, draw, W, H = make_canvas(FINAL + r'\drill_front.png', pad_r=760, pad_b=220, pad_t=40)
    near_top = (297, 353+40); far_top = (1004, 158+40)
    near_bottom = (541, 546+40); far_bottom = (1294, 306+40)

    title_text(canvas, draw, T['mb_title'][lang], 40, 5, lang)
    callout(canvas, draw, T['mb_callout'][lang],
            [near_top, near_bottom, far_bottom, far_top], (W+40, 420), lang, box_align="left")

    ty = H+40+30
    for line in T['mb_caption'][lang]:
        draw_line(canvas, line, 40, ty, lang, align="left")
        ty += 40

    canvas.save(FINAL + f'\\dimensions_main_body_screws_{lang}.png')
    print("saved main body", lang)


def build_bottom(lang):
    PAD_L = 300
    canvas, draw, W, H = make_canvas(FINAL + r'\drill_bottom.png', pad_r=800, pad_b=60, pad_l=PAD_L)
    corner_TL = (228+PAD_L, 633); corner_R = (1358+PAD_L, 578); corner_front = (507+PAD_L, 880)
    pi_cluster = (390+PAD_L, 670); uno_cluster = (680+PAD_L, 590)

    off = 45
    arrow_line(draw, (corner_front[0], corner_front[1]+off), (corner_R[0]-40, corner_R[1]+off*1.6))
    draw_line(canvas, T['bp_width'][lang], (corner_front[0]+corner_R[0])/2 - 90,
              (corner_front[1]+corner_R[1])/2 + off*1.4, lang, align="left")
    off = 40
    arrow_line(draw, (corner_TL[0]-off, corner_TL[1]), (corner_front[0]-off*0.5, corner_front[1]))
    draw_line(canvas, T['bp_depth'][lang], corner_TL[0]-off-260, (corner_TL[1]+corner_front[1])/2-15,
              lang, align="left")

    title_text(canvas, draw, T['bp_title'][lang], 40, 40, lang)
    callout(canvas, draw, T['bp_corner'][lang], corner_front, (W+PAD_L+40, 120), lang, box_align="left")
    callout(canvas, draw, T['bp_pi'][lang], pi_cluster, (W+PAD_L+40, 460), lang, box_align="left")
    callout(canvas, draw, T['bp_uno'][lang], uno_cluster, (W+PAD_L+40, 820), lang, box_align="left")

    canvas.save(FINAL + f'\\dimensions_bottom_{lang}.png')
    print("saved bottom", lang)


def build_backplate(lang):
    canvas, draw, W, H = make_canvas(FINAL + r'\render_backplate.png', pad_r=780, pad_b=260, pad_t=40)
    TL = (363, 476+40); TR = (1188, 243+40); BL = (398, 984+40); BR = (1152, 690+40)

    title_text(canvas, draw, T['pl_title'][lang], 40, 5, lang)
    callout(canvas, draw, T['pl_callout'][lang], [TL, BR, BL], (W+40, 300), lang, box_align="left")
    dot(draw, TR); draw.line([TR, (W+40, 300)], fill=RED, width=2)

    ty = H+40+30
    for line in T['pl_caption'][lang]:
        draw_line(canvas, line, 40, ty, lang, align="left")
        ty += 38

    canvas.save(FINAL + f'\\dimensions_backplate_{lang}.png')
    print("saved backplate", lang)


def build_main_body_flipped(lang):
    canvas, draw, W, H = make_canvas(FINAL + r'\render_main_flipped.png', pad_r=760, pad_t=100, pad_b=180)
    near_left = (285, 347+100); far_back = (999, 157+100)
    far_right = (1294, 306+100); near_front = (541, 540+100)

    title_text(canvas, draw, T['mbf_title'][lang], 40, 15, lang)
    callout(canvas, draw, T['mbf_callout'][lang],
            [near_left, far_back, far_right, near_front], (W+40, 400), lang, box_align="left")

    ty = H+100+20
    for line in T['mbf_caption'][lang]:
        draw_line(canvas, line, 40, ty, lang, align="left")
        ty += 38

    canvas.save(FINAL + f'\\dimensions_main_body_flipped_{lang}.png')
    print("saved main body flipped", lang)


for lang in ('ar', 'hi'):
    build_main_body(lang)
    build_bottom(lang)
    build_backplate(lang)
    build_main_body_flipped(lang)
