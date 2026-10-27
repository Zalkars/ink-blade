import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BASE_DIR = r"d:\DS\Work\Projects\InkBlade"
OUT_DIR = os.path.join(BASE_DIR, "InkBladeAndroid", "docs", "rustore")
os.makedirs(OUT_DIR, exist_ok=True)

# Image paths
P_TITLE = os.path.join(BASE_DIR, "InkBladeAndroid", "builds", "screenshot_title8.png")
P_INGAME = os.path.join(BASE_DIR, "InkBladeAndroid", "builds", "screenshot_ingame.png")
P_PAUSED = os.path.join(BASE_DIR, "InkBladeAndroid", "builds", "screenshot_paused_key.png")
P_SLASH = os.path.join(BASE_DIR, "InkBladeAndroid", "docs", "screenshots", "04-slash.png")
P_HIT = os.path.join(BASE_DIR, "InkBladeAndroid", "docs", "screenshots", "05-hit.png")
P_DEATH = os.path.join(BASE_DIR, "InkBladeAndroid", "docs", "screenshots", "10-death.png")
P_ICON = os.path.join(BASE_DIR, "variant2_v3_knight.png")

# Palette
C_PAPER = (239, 228, 204)       # #efe4cc
C_PAPER_LIGHT = (247, 239, 221) # #f7efdd
C_PAPER_DARK = (216, 198, 159)  # #d8c69f
C_INK = (23, 19, 15)            # #17130f
C_INK_SOFT = (74, 60, 46)       # #4a3c2e
C_RED = (156, 33, 41)           # #9c2129 (cinnabar)
C_RED_BRIGHT = (201, 53, 58)    # #c9353a
C_RED_DARK = (101, 20, 25)      # #651419
C_GOLD = (184, 146, 63)         # #b8923f
C_CREAM = (246, 237, 218)       # #f6edda
C_WHITE = (255, 255, 255)

FONT_TITLE = r"C:\Windows\Fonts\georgiab.ttf"
FONT_SANS_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_SANS_REG = r"C:\Windows\Fonts\segoeui.ttf"

def draw_diamond(draw, cx, cy, r=7, color=C_RED):
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    draw.polygon(pts, fill=color)

def draw_solid_brush_underline(draw, x_center, y, width, max_th=7, color=C_RED):
    """Draws a continuous solid calligraphic red ink brush underline without any gaps."""
    steps = int(width)
    x_start = x_center - width / 2
    for i in range(steps + 1):
        t = i / steps
        px = x_start + t * width
        wobble = math.sin(t * math.pi * 2.8) * 1.5 + math.sin(t * math.pi * 5.5) * 0.6
        py = y + wobble
        th = (math.sin(t * math.pi) ** 0.5) * max_th
        if th > 0.4:
            draw.ellipse([px - th/2, py - th/2, px + th/2, py + th/2], fill=color)

def draw_corner_brackets(draw, x, y, w, h, size=28, width=3, color=C_INK):
    draw.line([(x, y), (x + size, y)], fill=color, width=width)
    draw.line([(x, y), (x, y + size)], fill=color, width=width)
    draw.line([(x + w, y), (x + w - size, y)], fill=color, width=width)
    draw.line([(x + w, y), (x + w, y + size)], fill=color, width=width)
    draw.line([(x, y + h), (x + size, y + h)], fill=color, width=width)
    draw.line([(x, y + h), (x, y + h - size)], fill=color, width=width)
    draw.line([(x + w, y + h), (x + w - size, y + h)], fill=color, width=width)
    draw.line([(x + w, y + h), (x + w, y + h - size)], fill=color, width=width)

def draw_pill(draw, x_center, y_center, text, font, bg=C_RED, fg=C_CREAM, border=None, pad_x=22, pad_y=7):
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    w = tw + pad_x * 2
    h = th + pad_y * 2
    x0 = int(x_center - w / 2)
    y0 = int(y_center - h / 2)
    x1 = int(x0 + w)
    y1 = int(y0 + h)
    radius = int(h / 2)
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=bg, outline=border, width=2 if border else 0)
    draw.text((x_center - tw/2 - bbox[0], y0 + pad_y - bbox[1]), text, fill=fg, font=font)
    return w, h

def draw_badge_with_diamonds(draw, x_center, y_center, text, font, bg=C_RED, fg=C_CREAM, pad_x=24, pad_y=6):
    bbox = font.getbbox(text)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    
    diamond_space = 22
    total_tw = tw + diamond_space * 2
    w = total_tw + pad_x * 2
    h = th + pad_y * 2
    x0 = int(x_center - w / 2)
    y0 = int(y_center - h / 2)
    x1 = int(x0 + w)
    y1 = int(y0 + h)
    radius = int(h / 2)
    draw.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=bg)
    
    # Left diamond
    draw_diamond(draw, x_center - tw/2 - 13, y_center, r=4.5, color=C_CREAM)
    # Text
    draw.text((x_center - tw/2 - bbox[0], y0 + pad_y - bbox[1]), text, fill=fg, font=font)
    # Right diamond
    draw_diamond(draw, x_center + tw/2 + 13, y_center, r=4.5, color=C_CREAM)

def draw_feature_chips(draw, x_center, y, chips, font, bg=C_CREAM, fg=C_INK, border=C_INK_SOFT):
    total_w = 0
    chip_widths = []
    gap = 18
    for chip in chips:
        bbox = font.getbbox(chip)
        w = (bbox[2] - bbox[0]) + 34
        chip_widths.append(w)
        total_w += w
    total_w += gap * (len(chips) - 1)
    
    cur_x = x_center - total_w / 2
    for chip, w in zip(chips, chip_widths):
        draw_pill(draw, cur_x + w/2, y, chip, font, bg=bg, fg=fg, border=border, pad_x=17, pad_y=7)
        cur_x += w + gap

def draw_ink_seal(card, x, y, size=78, char="Ч"):
    seal = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(seal)
    sdraw.rounded_rectangle([2, 2, size - 2, size - 2], radius=14, fill=C_RED, outline=C_RED_DARK, width=3)
    sdraw.rectangle([8, 8, size - 8, size - 8], fill=None, outline=C_CREAM, width=2)
    
    f_seal = ImageFont.truetype(FONT_TITLE, int(size * 0.54))
    bbox = f_seal.getbbox(char)
    cw = bbox[2] - bbox[0]
    ch = bbox[3] - bbox[1]
    sdraw.text(((size - cw)/2 - bbox[0], (size - ch)/2 - bbox[1] - 2), char, fill=C_CREAM, font=f_seal)
    
    card.alpha_composite(seal, (x, y))

def draw_vignette(card, W=2400, H=1080):
    draw = ImageDraw.Draw(card)
    pad = 28
    draw.rectangle([pad, pad, W - pad, H - pad], outline=(74, 60, 46, 85), width=2)
    draw.rectangle([pad + 6, pad + 6, W - pad - 6, H - pad - 6], outline=(74, 60, 46, 35), width=1)
    draw_corner_brackets(draw, pad, pad, W - pad*2, H - pad*2, size=36, width=3, color=C_INK)

def draw_parchment_header_panel(card, badge_text, title_text, subtitle_text, W=2400, H=1080, panel_h=205, is_dark=False):
    draw = ImageDraw.Draw(card)
    panel_w = 1750
    px0 = int((W - panel_w) / 2)
    py0 = 36
    px1 = px0 + panel_w
    py1 = py0 + panel_h
    
    # Shadow under header scroll
    shadow = Image.new("RGBA", (panel_w + 30, panel_h + 30), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle([10, 10, panel_w + 20, panel_h + 20], radius=20, fill=(23, 19, 15, 120 if is_dark else 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    card.alpha_composite(shadow, (px0 - 5, py0 - 5))
    
    # Scroll Panel Background
    p_draw = ImageDraw.Draw(card)
    bg_fill = (26, 20, 16, 240) if is_dark else (246, 237, 218, 245)
    border_color = C_RED_DARK if is_dark else C_INK
    p_draw.rounded_rectangle([px0, py0, px1, py1], radius=16, fill=bg_fill, outline=border_color, width=3)
    p_draw.rounded_rectangle([px0 + 5, py0 + 5, px1 - 5, py1 - 5], radius=12, fill=None, outline=(156, 33, 41, 100), width=1)
    draw_corner_brackets(p_draw, px0 + 8, py0 + 8, panel_w - 16, panel_h - 16, size=24, width=2, color=C_RED if is_dark else C_INK_SOFT)
    
    # Fonts
    f_badge = ImageFont.truetype(FONT_SANS_BOLD, 20)
    f_title = ImageFont.truetype(FONT_TITLE, 48)
    f_sub = ImageFont.truetype(FONT_SANS_BOLD, 24)
    
    # Badge
    draw_badge_with_diamonds(p_draw, W / 2, py0 + 32, badge_text, f_badge, bg=C_RED, fg=C_CREAM, pad_x=22, pad_y=5)
    
    # Title
    bbox_t = f_title.getbbox(title_text)
    tw = bbox_t[2] - bbox_t[0]
    th = bbox_t[3] - bbox_t[1]
    title_y = py0 + 64
    
    title_fg = C_CREAM if is_dark else C_INK
    p_draw.text((W/2 - tw/2 - bbox_t[0], title_y - bbox_t[1]), title_text, fill=title_fg, font=f_title)
    
    # Solid Brush Underline
    underline_y = title_y + th + 14
    draw_solid_brush_underline(p_draw, W / 2, underline_y, width=tw * 0.95, max_th=6, color=C_RED_BRIGHT if is_dark else C_RED)
    
    # Subtitle
    sub_y = underline_y + 12
    bbox_s = f_sub.getbbox(subtitle_text)
    sw = bbox_s[2] - bbox_s[0]
    sub_fg = (216, 198, 159) if is_dark else C_INK_SOFT
    p_draw.text((W/2 - sw/2 - bbox_s[0], sub_y - bbox_s[1]), subtitle_text, fill=sub_fg, font=f_sub)


# ==========================================
# CARD 1: Style & Atmosphere
# ==========================================
def make_card_1(W=2400, H=1080):
    print("Generating Card 1: Title & Atmosphere...")
    bg = Image.open(P_TITLE).convert("RGBA")
    if bg.size != (W, H):
        bg = bg.resize((W, H), Image.Resampling.LANCZOS)
    
    # Bottom vignette for chips
    bot_grad = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bdraw = ImageDraw.Draw(bot_grad)
    for y in range(H - 120, H):
        t = (y - (H - 120)) / 120
        bdraw.line([(0, y), (W, y)], fill=(23, 19, 15, int(180 * t)))
    bg.alpha_composite(bot_grad)
    
    # Styled Header Panel
    draw_parchment_header_panel(
        bg,
        badge_text="ОТКРЫТЫЙ ПРОТОТИП · v0.1 · ТЕСТОВАЯ ЗАЛА",
        title_text="АТМОСФЕРА ЖИВОЙ ТУШИ И ПЕРГАМЕНТА",
        subtitle_text="Хардкорный экшн-рогалик в духе традиционной восточной гравюры",
        W=W, H=H, panel_h=195, is_dark=False
    )
    
    # Floating App Icon Emblem on the left
    icon = Image.open(P_ICON).convert("RGBA")
    icon_size = 220
    icon = icon.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    
    shadow = Image.new("RGBA", (icon_size + 40, icon_size + 40), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle([15, 15, icon_size + 25, icon_size + 25], radius=50, fill=(23, 19, 15, 130))
    shadow = shadow.filter(ImageFilter.GaussianBlur(12))
    
    icon_x = 90
    icon_y = H - icon_size - 90
    bg.alpha_composite(shadow, (icon_x - 10, icon_y - 10))
    bg.alpha_composite(icon, (icon_x, icon_y))
    
    idraw = ImageDraw.Draw(bg)
    idraw.rounded_rectangle([icon_x, icon_y, icon_x + icon_size, icon_y + icon_size], radius=48, outline=C_INK, width=3)
    
    # Feature Chips at bottom right
    f_chips = ImageFont.truetype(FONT_SANS_BOLD, 22)
    chips = ["РУЧНАЯ РИСОВКА", "ПРОЦЕДУРНАЯ БУМАГА", "СУМИ-Э И ХАРДКОР", "СИНТЕЗ ЗВУКА"]
    draw_feature_chips(idraw, W/2 + 200, H - 65, chips, f_chips, bg=C_CREAM, fg=C_INK, border=C_INK_SOFT)
    
    draw_ink_seal(bg, W - 140, 48, size=78, char="Ч")
    draw_vignette(bg, W, H)
    return bg


# ==========================================
# CARD 2: Fast & Precise Combat (Zoomed combat focus)
# ==========================================
def make_card_2(W=2400, H=1080):
    print("Generating Card 2: Combat & Action...")
    card = Image.new("RGBA", (W, H), C_PAPER)
    
    slash_orig = Image.open(P_SLASH).convert("RGBA")
    # Crop combat focus: knight, red slash arc, dummy, damage text, enemies, sentinel laser
    # slash_orig is 1280x720. Let's crop x: 120 to 1160, y: 220 to 625 (no keyboard bar)
    combat_crop = slash_orig.crop((120, 220, 1160, 625))
    
    # Also crop HUD health masks & soul sphere
    hud_crop = slash_orig.crop((30, 25, 230, 150))
    
    frame_w = 2100
    frame_h = 720
    frame_x = int((W - frame_w) / 2)
    frame_y = 245
    
    combat_resized = combat_crop.resize((frame_w, frame_h), Image.Resampling.LANCZOS)
    
    # Drop shadow under combat frame
    shadow = Image.new("RGBA", (frame_w + 50, frame_h + 50), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rectangle([20, 20, frame_w + 30, frame_h + 30], fill=(23, 19, 15, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    card.alpha_composite(shadow, (frame_x - 15, frame_y - 10))
    
    card.alpha_composite(combat_resized, (frame_x, frame_y))
    
    # Overlay HUD in upper left of the frame
    hud_w, hud_h = int(hud_crop.width * 1.3), int(hud_crop.height * 1.3)
    hud_resized = hud_crop.resize((hud_w, hud_h), Image.Resampling.LANCZOS)
    card.alpha_composite(hud_resized, (frame_x + 30, frame_y + 25))
    
    cdraw = ImageDraw.Draw(card)
    cdraw.rectangle([frame_x, frame_y, frame_x + frame_w, frame_y + frame_h], outline=C_INK, width=4)
    draw_corner_brackets(cdraw, frame_x + 8, frame_y + 8, frame_w - 16, frame_h - 16, size=28, width=2, color=C_RED)
    
    # Callout badge for slash & damage
    f_badge_mini = ImageFont.truetype(FONT_SANS_BOLD, 19)
    draw_pill(cdraw, frame_x + frame_w - 220, frame_y + 50, "РАССЕКАЮЩИЙ УДАР · КРИТ", f_badge_mini, bg=C_RED, fg=C_CREAM, pad_x=16, pad_y=5)
    
    # Styled Header Panel
    draw_parchment_header_panel(
        card,
        badge_text="БОЕВАЯ СИСТЕМА И РЕФЛЕКСЫ",
        title_text="БЫСТРЫЙ И БЕСКОМПРОМИССНЫЙ БОЙ",
        subtitle_text="Молниеносный клинок, воздушный отскок pogo и рывок сквозь опасность",
        W=W, H=H, panel_h=195, is_dark=False
    )
    
    # Bottom chips
    f_chips = ImageFont.truetype(FONT_SANS_BOLD, 22)
    chips = ["РАССЕКАЮЩИЙ ВЗМАХ", "ОТСКОК ОТ ВРАГА (POGO)", "НЕУЯЗВИМЫЙ РЫВОК", "СЕРИИ УДАРОВ"]
    draw_feature_chips(cdraw, W/2, H - 55, chips, f_chips, bg=C_CREAM, fg=C_INK, border=C_INK_SOFT)
    
    draw_ink_seal(card, W - 140, 48, size=78, char="К")
    draw_vignette(card, W, H)
    return card


# ==========================================
# CARD 3: Touch Controls & Mobile UX
# ==========================================
def make_card_3(W=2400, H=1080):
    print("Generating Card 3: Touch Controls...")
    bg = Image.open(P_INGAME).convert("RGBA")
    if bg.size != (W, H):
        bg = bg.resize((W, H), Image.Resampling.LANCZOS)
    
    # Styled Header Panel
    draw_parchment_header_panel(
        bg,
        badge_text="СОЗДАНО ДЛЯ СМАРТФОНОВ",
        title_text="ТОЧНОЕ СЕНСОРНОЕ УПРАВЛЕНИЕ",
        subtitle_text="Плавающий стик, мультитач и отзывчивые кнопки без задержек",
        W=W, H=H, panel_h=195, is_dark=False
    )
    
    draw = ImageDraw.Draw(bg)
    
    # Callout highlights over controls
    f_callout = ImageFont.truetype(FONT_SANS_BOLD, 20)
    # Left joystick callout
    draw_pill(draw, 290, H - 380, "АНАЛОГОВЫЙ СТИК", f_callout, bg=C_INK, fg=C_CREAM, border=C_RED, pad_x=16, pad_y=6)
    draw.line([(290, H - 355), (290, H - 290)], fill=C_RED, width=3)
    draw.ellipse([286, H - 290, 294, H - 282], fill=C_RED)
    
    # Right action buttons callout
    draw_pill(draw, W - 290, H - 380, "КНОПКИ ДЕЙСТВИЙ A / X / B / Y", f_callout, bg=C_INK, fg=C_CREAM, border=C_RED, pad_x=16, pad_y=6)
    draw.line([(W - 290, H - 355), (W - 290, H - 290)], fill=C_RED, width=3)
    draw.ellipse([W - 294, H - 290, W - 286, H - 282], fill=C_RED)
    
    # Semi-transparent pill backing for bottom chips to avoid colliding with in-game bottom bar
    chips_bar = Image.new("RGBA", (1400, 60), (0, 0, 0, 0))
    cb_draw = ImageDraw.Draw(chips_bar)
    cb_draw.rounded_rectangle([0, 0, 1400, 60], radius=30, fill=(23, 19, 15, 170), outline=C_RED, width=2)
    bg.alpha_composite(chips_bar, (int((W - 1400) / 2), H - 90))
    
    # Feature Chips at bottom
    b_draw = ImageDraw.Draw(bg)
    f_chips = ImageFont.truetype(FONT_SANS_BOLD, 20)
    chips = ["100% SENSOR LANDSCAPE", "ПЛАВАЮЩИЙ СТИК", "ПОДДЕРЖКА ГЕЙМПАДОВ", "ТАКТИЛЬНАЯ ВИБРАЦИЯ"]
    draw_feature_chips(b_draw, W/2, H - 60, chips, f_chips, bg=C_CREAM, fg=C_INK, border=C_INK_SOFT)
    
    draw_ink_seal(bg, W - 140, 48, size=78, char="Ч")
    draw_vignette(bg, W, H)
    return bg


# ==========================================
# CARD 4: Soul & Rebirth Roguelike Loop
# ==========================================
def make_card_4(W=2400, H=1080):
    print("Generating Card 4: Soul & Roguelike Rebirth...")
    death_img = Image.open(P_DEATH).convert("RGBA")
    if death_img.size != (W, H):
        card = death_img.resize((W, H), Image.Resampling.LANCZOS)
    else:
        card = death_img.copy()
    
    # Dark Header Panel
    draw_parchment_header_panel(
        card,
        badge_text="ФИЛОСОФИЯ ЧЕРНИЛ И ВОЗРОЖДЕНИЯ",
        title_text="КАЖДАЯ СМЕРТЬ — ЕЩЁ ОДИН МАЗОК",
        subtitle_text="Копи чернильную душу для исцеления, учись на ошибках и возвращайся сильнее",
        W=W, H=H, panel_h=195, is_dark=True
    )
    
    draw = ImageDraw.Draw(card)
    
    # Bottom feature chips
    f_chips = ImageFont.truetype(FONT_SANS_BOLD, 22)
    chips = ["МАСКИ ЗДОРОВЬЯ", "ИСЦЕЛЕНИЕ ЗА ДУШУ", "ЧАСОВОЙ И СНАРЯДЫ", "МГНОВЕННЫЙ РЕСТАРТ"]
    draw_feature_chips(draw, W/2, H - 55, chips, f_chips, bg=(35, 28, 22), fg=C_CREAM, border=C_RED)
    
    draw_ink_seal(card, W - 140, 48, size=78, char="Ч")
    draw_vignette(card, W, H)
    return card

# Generate all 4 cards
c1 = make_card_1(2400, 1080)
c2 = make_card_2(2400, 1080)
c3 = make_card_3(2400, 1080)
c4 = make_card_4(2400, 1080)

# Save 2400x1080
c1.save(os.path.join(OUT_DIR, "card1_title_atmosphere_2400x1080.png"), optimize=True)
c2.save(os.path.join(OUT_DIR, "card2_combat_action_2400x1080.png"), optimize=True)
c3.save(os.path.join(OUT_DIR, "card3_touch_controls_2400x1080.png"), optimize=True)
c4.save(os.path.join(OUT_DIR, "card4_soul_rebirth_2400x1080.png"), optimize=True)

# Also save 1920x1080 (standard Full HD)
c1.resize((1920, 1080), Image.Resampling.LANCZOS).save(os.path.join(OUT_DIR, "card1_title_atmosphere_1920x1080.png"), optimize=True)
c2.resize((1920, 1080), Image.Resampling.LANCZOS).save(os.path.join(OUT_DIR, "card2_combat_action_1920x1080.png"), optimize=True)
c3.resize((1920, 1080), Image.Resampling.LANCZOS).save(os.path.join(OUT_DIR, "card3_touch_controls_1920x1080.png"), optimize=True)
c4.resize((1920, 1080), Image.Resampling.LANCZOS).save(os.path.join(OUT_DIR, "card4_soul_rebirth_1920x1080.png"), optimize=True)

print("All 4 cards perfected and exported in both 2400x1080 and 1920x1080!")
