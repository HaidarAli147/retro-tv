"""Proper text shaping (Arabic joining, Devanagari conjuncts/matras) via
HarfBuzz + FreeType, since this Pillow build has no raqm support."""
import re
import uharfbuzz as hb
import freetype
from PIL import Image

_ARABIC_RE = re.compile(r'[؀-ۿݐ-ݿ\s]+')


def _split_bidi_runs(text):
    """Split into (is_arabic, chunk) runs. Whitespace is grouped with
    whichever script run it's adjacent to via the regex above; any leftover
    plain-space-only runs default to the Latin/number (LTR) side."""
    runs = []
    pos = 0
    for m in re.finditer(r'[؀-ۿݐ-ݿ]+[؀-ۿݐ-ݿ\s]*', text):
        if m.start() > pos:
            runs.append((False, text[pos:m.start()]))
        runs.append((True, m.group().rstrip()))
        trailing = m.group()[len(m.group().rstrip()):]
        pos = m.end() - len(trailing)
    if pos < len(text):
        runs.append((False, text[pos:]))
    return [(a, c) for a, c in runs if c]

_face_cache = {}
_hbfont_cache = {}


def _load(font_path, face_index=0):
    key = (font_path, face_index)
    if key not in _face_cache:
        ft_face = freetype.Face(font_path, index=face_index)
        with open(font_path, "rb") as f:
            data = f.read()
        blob = hb.Blob(data)
        hb_face = hb.Face(blob, index=face_index)
        hb_font = hb.Font(hb_face)
        _face_cache[key] = ft_face
        _hbfont_cache[key] = hb_font
    return _face_cache[key], _hbfont_cache[key]


def shape_line(text, font_path, size_px, face_index=0, rtl=False, script=None, language=None):
    """Returns (glyphs, total_width, ascent, descent) where glyphs is a list
    of (glyph_id, x, y) pen positions (top-left origin, y grows down) ready
    to blit at that size."""
    ft_face, hb_font = _load(font_path, face_index)
    ft_face.set_char_size(size_px * 64)
    hb_font.scale = (size_px * 64, size_px * 64)

    buf = hb.Buffer()
    buf.add_str(text)
    if rtl:
        buf.direction = "rtl"
    else:
        buf.direction = "ltr"
    if script:
        buf.script = script
    if language:
        buf.language = language
    if not script:
        buf.guess_segment_properties()

    hb.shape(hb_font, buf)

    x, y = 0, 0
    glyphs = []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        gx = x + pos.x_offset / 64
        gy = y - pos.y_offset / 64
        glyphs.append((info.codepoint, gx, gy))
        x += pos.x_advance / 64
        y += pos.y_advance / 64

    ascent = ft_face.size.ascender / 64
    descent = -ft_face.size.descender / 64
    return glyphs, x, ascent, descent, ft_face


def _blit_run(canvas_img, glyphs, ft_face, x0, baseline_y, color):
    for codepoint, gx, gy in glyphs:
        ft_face.load_glyph(codepoint, freetype.FT_LOAD_RENDER)
        bitmap = ft_face.glyph.bitmap
        if bitmap.width == 0 or bitmap.rows == 0:
            continue
        buf = bytes(bitmap.buffer)
        glyph_img = Image.frombuffer("L", (bitmap.width, bitmap.rows), buf, "raw", "L", 0, 1)
        px = int(x0 + gx + ft_face.glyph.bitmap_left)
        py = int(baseline_y + gy - ft_face.glyph.bitmap_top)
        solid = Image.new("RGB", glyph_img.size, color)
        canvas_img.paste(solid, (px, py), glyph_img)


def draw_shaped(canvas_img, text, xy, font_path, size_px, color, face_index=0,
                 rtl=False, script=None, language=None, align="left"):
    """Draws `text` onto a PIL RGB canvas at xy=(x,y) (y = baseline top,
    i.e. same convention as ImageDraw.text with default anchor). Returns
    the rendered width in px."""
    glyphs, total_w, ascent, descent, ft_face = shape_line(
        text, font_path, size_px, face_index, rtl, script, language)

    x0, y0 = xy
    if align == "right":
        x0 -= total_w
    elif align == "center":
        x0 -= total_w / 2

    baseline_y = y0 + ascent
    _blit_run(canvas_img, glyphs, ft_face, x0, baseline_y, color)
    return total_w, ascent + descent


def draw_bidi_line(canvas_img, text, xy, ar_font, ar_face_index, latin_font, size_px,
                    color, align="right"):
    """For a predominantly-RTL (Arabic) line that may contain embedded
    Latin/number substrings (e.g. 'M3 x 12mm'). Splits into script runs,
    shapes each in its own direction, and lays the runs out left-to-right
    in correct bidi visual order (logical runs reversed, each run's own
    internal glyph order left untouched)."""
    runs = _split_bidi_runs(text)
    shaped = []
    total_w = 0
    max_ascent = 0
    max_descent = 0
    for is_ar, chunk in runs:
        if is_ar:
            glyphs, w, asc, desc, face = shape_line(chunk, ar_font, size_px, ar_face_index,
                                                      rtl=True, script="Arab", language="ar")
        else:
            glyphs, w, asc, desc, face = shape_line(chunk, latin_font, size_px, 0,
                                                      rtl=False)
        shaped.append((glyphs, w, face))
        total_w += w
        max_ascent = max(max_ascent, asc)
        max_descent = max(max_descent, desc)

    x0, y0 = xy
    if align == "right":
        x0 -= total_w
    elif align == "center":
        x0 -= total_w / 2

    baseline_y = y0 + max_ascent
    cursor = x0
    for glyphs, w, face in reversed(shaped):
        _blit_run(canvas_img, glyphs, face, cursor, baseline_y, color)
        cursor += w

    return total_w, max_ascent + max_descent
