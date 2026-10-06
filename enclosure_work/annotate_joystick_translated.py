import sys
sys.path.insert(0, r'C:\Users\haals\AppData\Local\Temp\osc')
from PIL import Image, ImageDraw
from shape_text import draw_shaped, draw_bidi_line

FINAL = r'C:\Users\haals\AppData\Local\Temp\osc\final'
ARIALBD = r'C:\Windows\Fonts\arialbd.ttf'
NIRMALA = r'C:\Windows\Fonts\Nirmala.ttc'

RED = (200, 20, 20)
ORANGE = (200, 100, 0)
WHITE = (255, 255, 255)
TITLE_SZ = 30
BODY_SZ = 24


def measure(lines, lang):
    w = h = 0
    for line in lines:
        if lang == 'ar':
            ww, hh = draw_bidi_line(Image.new("RGB", (4, 4)), line, (0, 0), ARIALBD, 0, ARIALBD,
                                     BODY_SZ, RED, align="left")
        else:
            ww, hh = draw_shaped(Image.new("RGB", (4, 4)), line, (0, 0), NIRMALA, BODY_SZ, RED,
                                  face_index=0, rtl=False)
        w, h = max(w, ww), max(h, hh)
    return w, h


def draw_line(canvas, line, x, y, lang, size=BODY_SZ, align="left", color=RED):
    if lang == 'ar':
        return draw_bidi_line(canvas, line, (x, y), ARIALBD, 0, ARIALBD, size, color, align=align)
    a = "left" if align == "left" else ("right" if align == "right" else "center")
    return draw_shaped(canvas, line, (x, y), NIRMALA, size, color, face_index=0, rtl=False, align=a)


def dot(draw, p, r=10, color=RED):
    draw.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=color)


def callout(canvas, draw, lines, target, box_pos, lang, box_align="left", color=RED):
    dot(draw, target, color=color)
    draw.line([target, box_pos], fill=color, width=3)
    max_w, line_h = measure(lines, lang)
    pad = 14
    box_w = max_w + pad * 2
    box_h = len(lines) * (line_h + 10) + pad * 2 - 10
    x, y = box_pos
    if box_align == "left":
        rect = [x, y - box_h/2, x + box_w, y + box_h/2]
        text_x0, text_align = x + pad, "left"
    else:
        rect = [x - box_w, y - box_h/2, x, y + box_h/2]
        text_x0, text_align = x - pad, "right"
    draw.rectangle(rect, fill=WHITE, outline=color, width=2)
    ty = rect[1] + pad
    for line in lines:
        draw_line(canvas, line, text_x0, ty, lang, align=text_align, color=color)
        ty += line_h + 10


T = {
    'title': {'ar': "تثبيت الجويستيك - منظور من الخلف (من الداخل، عبر الفتحة السفلية المفتوحة)",
              'hi': "जॉयस्टिक माउंटिंग - पीछे से देखा गया (अंदर से, खुले निचले हिस्से के आर-पार)"},
    'subtitle': {'ar': "اللوح العلوي والهيكل الرئيسي أصبحا الآن قطعة واحدة ملتحمة - بدون فاصل، موضحة هنا مدمجة.",
                 'hi': "ऊपर का पैनल और मुख्य ढांचा अब एक ही जुड़ा हुआ हिस्सा हैं - बिना किसी जोड़ के, यहाँ जुड़ा हुआ दिखाया गया है।"},
    'joystick': {
        'ar': ["ثقب الجويستيك - دائري 2.7 سم",
               "مطلوب 4 ثقوب توجيهية للتثبيت:",
               "قطر 0.2 سم، ذاتي التنصيت M2",
               "التباعد: 19.5 مم (قيمة مؤقتة -",
               "غير مؤكدة - قِس الوحدة الحقيقية",
               "قبل الحفر)"],
        'hi': ["जॉयस्टिक छेद - 2.7 सेमी गोल",
               "4x माउंटिंग पायलट छेद चाहिए:",
               "व्यास 0.2 सेमी, सेल्फ-टैपिंग M2",
               "दूरी: 19.5mm (अस्थायी -",
               "पुष्टि नहीं हुई - असली मॉड्यूल",
               "मापें ड्रिल करने से पहले)"],
    },
    'boss': {
        'ar': ["حامل بارز (بارتفاع 0.4 سم، مثل",
               "حوامل رازبيري باي) لم يُضف هنا - عند",
               "التباعد الحالي 19.5 مم، تقع مواضع",
               "البراغي على بُعد 0.29 مم فقط خلف",
               "حافة الثقب، لذا أي حامل يتداخل",
               "ويكسر الثقب. يحتاج إلى القياس",
               "الحقيقي أولاً."],
        'hi': ["स्टैंडऑफ़ बॉस (0.4 सेमी ऊँचा, जैसे",
               "पाई स्टैंडऑफ़) यहाँ नहीं जोड़ा गया - मौजूदा",
               "19.5mm दूरी पर पेंच की जगहें",
               "छेद के किनारे से केवल 0.29mm आगे",
               "पड़ती हैं, इसलिए कोई भी बॉस ओवरलैप करके",
               "छेद को तोड़ देता है। पहले असली माप",
               "चाहिए।"],
    },
    'knob': {'ar': ["ثقب المقبض", "دائري 0.5 سم"], 'hi': ["नॉब छेद", "0.5 सेमी गोल"]},
    'caption': {
        'ar': ["هذا المنظور ينظر للأعلى داخل الصندوق عبر الفتحة السفلية المفتوحة (اللوح السفلي",
               "لم يُركّب بعد)، عند الوجه الداخلي للجدار الأمامي - براغي تثبيت الجويستيك",
               "تُلولب من هنا، وليس من الأمام."],
        'hi': ["यह दृश्य खुले निचले हिस्से से बॉक्स के अंदर ऊपर की ओर देख रहा है (निचला पैनल",
               "अभी लगा नहीं है), सामने की दीवार के अंदरूनी हिस्से पर - जॉयस्टिक के माउंटिंग",
               "पेंच यहीं से लगते हैं, सामने से नहीं।"],
    },
}


def build(lang):
    base = Image.open(FINAL + r'\render_main_flipped.png').convert("RGB")
    W, H = base.size
    PAD_R, PAD_T, PAD_B = 780, 130, 220
    canvas = Image.new("RGB", (W+PAD_R, H+PAD_T+PAD_B), (255, 255, 255))
    canvas.paste(base, (0, PAD_T))
    draw = ImageDraw.Draw(canvas)

    draw_line(canvas, T['title'][lang], 40, 15, lang, size=TITLE_SZ, align="left")
    draw_line(canvas, T['subtitle'][lang], 40, 60, lang, size=BODY_SZ, align="left", color=(80, 80, 80))

    joystick = (590, 324+PAD_T); knob = (666, 304+PAD_T)

    callout(canvas, draw, T['joystick'][lang], joystick, (W+40, 460), lang)
    callout(canvas, draw, T['boss'][lang], joystick, (W+40, 900), lang, color=ORANGE)
    callout(canvas, draw, T['knob'][lang], knob, (W+40, 220), lang)

    ty = H+PAD_T+30
    for line in T['caption'][lang]:
        draw_line(canvas, line, 40, ty, lang, align="left")
        ty += 36

    canvas.save(FINAL + f'\\dimensions_joystick_mounting_{lang}.png')
    print("saved", lang)


for lang in ('ar', 'hi'):
    build(lang)
