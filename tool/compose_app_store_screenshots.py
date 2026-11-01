#!/usr/bin/env python3
"""App Store screenshots (1320 x 2868, iPhone 6.9"): headline + app excerpt.

Input: build/app-store/raw/*.png + rects.json from
tool/capture_app_store_marketing_test.dart. Output: build/app-store/marketing/.
Needs Pillow; fonts: Roboto from the Flutter SDK (HEIZUNG_SCREENSHOT_FONT_DIR).
"""
import json
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
RAW = 'build/app-store/raw'
OUT = 'build/app-store/marketing'
FONTS = os.environ.get('HEIZUNG_SCREENSHOT_FONT_DIR',
                       os.path.expanduser('~/development/flutter/bin/cache/artifacts/material_fonts'))
ORANGE = (255, 167, 38)
TEXT = (236, 236, 240)
MUTED = (176, 176, 186)

# (file, headline line 1, headline line 2 (orange), subline, source, crop box or
#  (rect name, top offset, height or None)[, corner radius of the excerpt])
SLIDES = [
    ('01_heizkurve', 'Heizkurve verstehen.', 'Und gezielt anpassen.',
     'Basis-Wärme, Kurve und Richtwert für dein Haus auf einen Blick.', 'home', ('curve', 0, 2440)),
    ('02_kurve_anpassen', 'Jeden Punkt einstellen.', 'Mit exakter Vorschau.',
     'Flacher, steiler oder einzeln – geprüft und vom Regler zurückgelesen.', 'curve_editor', (124, 392, 1196, 2428), 84),
    ('03_zeitprogramm', 'Warm, wenn du da bist.', 'Sparsam, wenn nicht.',
     'Das Zeitprogramm als Zeitleiste – mit Vorlagen und Spar-Schätzung.', 'home', ('schedule', 0, None)),
    ('04_anlage_live', 'Deine Anlage live.', 'Pumpen, Ventile, Fühler.',
     'Ist- und Sollwerte direkt aus dem Danfoss ECL.', 'live', (0, 120, 1320, 2150)),
    ('05_urlaub', 'Urlaub planen.', 'Heizkosten sparen.',
     'Absenkung im Regler – und was eine Woche je Monat spart.', 'holiday', (0, 690, 1320, 3110)),
]


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, f'Roboto-{weight}.ttf'), size)


def background():
    img = Image.new('RGB', (W, H))
    top, bottom = (22, 22, 27), (44, 31, 20)
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        draw.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def wrap(draw, text, fnt, width):
    lines, line = [], ''
    for word in text.split():
        trial = f'{line} {word}'.strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(RAW, 'rects.json')) as f:
        rects = json.load(f)
    for name, h1, h2, sub, source, box, *radius in SLIDES:
        src = Image.open(os.path.join(RAW, f'{source}.png')).convert('RGB')
        if isinstance(box[0], str):  # (rect name, top offset, height or None)
            l, t, r, b = rects[source][box[0]]
            top = t + box[1]
            crop = src.crop((l, top, r, b if box[2] is None else top + box[2]))
        else:
            crop = src.crop(box)

        img = background()
        draw = ImageDraw.Draw(img)
        y = 150
        for text, color in [(h1, TEXT), (h2, ORANGE)]:
            fnt = font('Black', 104)
            draw.text(((W - draw.textlength(text, font=fnt)) / 2, y), text, font=fnt, fill=color)
            y += 128
        y += 24
        fnt = font('Regular', 46)
        for line in wrap(draw, sub, fnt, W - 200):
            draw.text(((W - draw.textlength(line, font=fnt)) / 2, y), line, font=fnt, fill=MUTED)
            y += 62
        y += 56

        # App excerpt: as wide as possible, scaled down if too tall.
        max_w, max_h = W - 120, H - y - 90
        scale = min(max_w / crop.width, max_h / crop.height)
        shot = crop.resize((round(crop.width * scale), round(crop.height * scale)), Image.LANCZOS)
        x = (W - shot.width) // 2
        radius = round((radius[0] if radius else 44) * scale)
        shadow = Image.new('L', (W, H), 0)
        ImageDraw.Draw(shadow).rounded_rectangle([x, y + 18, x + shot.width, y + shot.height + 18], radius, fill=150)
        img.paste((0, 0, 0), mask=shadow.filter(ImageFilter.GaussianBlur(30)))
        mask = Image.new('L', shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius, fill=255)
        img.paste(shot, (x, y), mask)
        draw.rounded_rectangle([x, y, x + shot.width - 1, y + shot.height - 1], radius, outline=(70, 70, 82), width=3)
        img.save(os.path.join(OUT, f'{name}.png'))
        print(f'{OUT}/{name}.png')


if __name__ == '__main__':
    main()
