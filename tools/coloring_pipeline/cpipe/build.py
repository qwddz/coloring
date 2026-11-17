"""Accepted line art + colored version -> data files for the app and a QA preview."""
import json
import cv2
import numpy as np
from PIL import Image, ImageFilter
from . import config
from .lineart import load_4x3, region_geometry


def _recall(ink, dark):
    near = cv2.dilate(dark.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) > 0
    return float((ink & near).sum() / max(ink.sum(), 1))


def _line_response(rgb):
    """thin dark structures of a colored picture (its outlines), comparable with line art"""
    g = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    return cv2.morphologyEx(g, cv2.MORPH_BLACKHAT, k).astype(np.float32)


def _estimate(ink, colored, s=4):
    """scale (searched) + translation (phase correlation) that maps the colored version onto the line art.
    Each candidate is scored by how many line-art lines it puts back on the colored outlines."""
    W, H = config.W, config.H
    small = lambda m: cv2.GaussianBlur(cv2.resize(m, (W // s, H // s), interpolation=cv2.INTER_AREA), (0, 0), 1.5)
    tpl, lines = small(ink.astype(np.float32)), _line_response(colored)
    ink_s = cv2.resize(ink.astype(np.uint8), (W // s, H // s), interpolation=cv2.INTER_NEAREST) > 0
    dark_s = cv2.resize((cv2.cvtColor(colored, cv2.COLOR_RGB2GRAY) < 90).astype(np.uint8), (W // s, H // s),
                        interpolation=cv2.INTER_NEAREST)
    win = cv2.createHanningWindow((W // s, H // s), cv2.CV_32F)

    def candidate(sc):
        m = cv2.getRotationMatrix2D((W / 2, H / 2), 0, 1 / sc)
        (dx, dy), _ = cv2.phaseCorrelate(tpl, small(cv2.warpAffine(lines, m, (W, H))), win)
        m[:, 2] -= (dx * s, dy * s)
        ms = m.copy(); ms[:, 2] /= s
        d = cv2.warpAffine(dark_s, ms, (W // s, H // s), flags=cv2.INTER_NEAREST) > 0
        near = cv2.dilate(d.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
        return float((ink_s & near).sum() / max(ink_s.sum(), 1)), sc, m
    best = max((candidate(sc) for sc in np.arange(0.92, 1.0801, 0.01)), key=lambda c: c[0])
    best = max((candidate(sc) for sc in np.arange(best[1] - 0.008, best[1] + 0.0081, 0.002)), key=lambda c: c[0])
    return best[2]


def align(ink, colored):
    """share of line-art lines found in the colored version; fixes a shift or small scale change if low"""
    dark = cv2.cvtColor(colored, cv2.COLOR_RGB2GRAY) < 90
    rec = _recall(ink, dark)
    if rec >= config.QA_ALIGN_MIN:
        return colored, rec, False
    m = _estimate(ink, colored)
    fixed = cv2.warpAffine(colored, m, (config.W, config.H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    rec2 = _recall(ink, cv2.cvtColor(fixed, cv2.COLOR_RGB2GRAY) < 90)
    return (fixed, rec2, True) if rec2 > rec else (colored, rec, False)


def character_mask(colored):
    try:
        from rembg import remove, new_session
    except ImportError:
        return None
    m = np.array(remove(Image.fromarray(colored), session=new_session('isnet-general-use'), only_mask=True)) > 128
    n, cc, st, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8), connectivity=8)
    if n > 1:  # drop specks (bubbles, stray leaves)
        big = st[1:, cv2.CC_STAT_AREA].max()
        m = np.isin(cc, [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] > 0.03 * big])
    return m


def _lab_real(lab8):
    return np.array([lab8[0] * 100 / 255, lab8[1] - 128, lab8[2] - 128], np.float32)


def _hex_from_lab8(lab8):
    rgb = cv2.cvtColor(np.uint8([[np.clip(lab8, 0, 255)]]), cv2.COLOR_LAB2RGB)[0, 0]
    return '#%02x%02x%02x' % tuple(int(c) for c in rgb)


def _palette(colors_lab8, weights, k):
    X = np.array([_lab_real(c) for c in colors_lab8], np.float32)
    k = max(1, min(k, len(np.unique(X.round(0), axis=0))))
    rep = np.repeat(X, np.maximum(1, (weights / weights.sum() * 4000).astype(int)), axis=0)
    _, _, cent = cv2.kmeans(rep, k, None, (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_MAX_ITER, 50, 0.5),
                            4, cv2.KMEANS_PP_CENTERS)
    cent = cent[np.argsort(-cent[:, 0])]  # light to dark
    assign = [int(((cent - x) ** 2).sum(1).argmin()) for x in X]
    to8 = lambda c: np.array([c[0] * 2.55, c[1] + 128, c[2] + 128])
    return [_hex_from_lab8(to8(c)) for c in cent], assign


def build(scene, la, colored_path, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    ink, reg, alpha = la['ink'].copy(), la['regions'].copy(), la['alpha'].copy()
    _, colored = load_4x3(colored_path, 'RGB')
    colored, rec, warped = align(ink, colored)
    lab = cv2.cvtColor(colored, cv2.COLOR_RGB2LAB)
    fails, notes = [], []
    if rec < config.QA_ALIGN_MIN:
        fails.append(f'цветная версия не совпадает с контуром ({rec:.0%} линий на месте)')
    if warped:
        notes.append('цветная версия выровнена аффинным преобразованием')

    # colors of regions: median of the eroded region (robust to small shifts and to the outline)
    n = int(reg.max())
    geo = region_geometry(reg)
    col = np.zeros((n + 1, 3), np.float32)
    for r in range(1, n + 1):
        x0, y0, x1, y1 = geo['x0'][r], geo['y0'][r], geo['x1'][r] + 1, geo['y1'][r] + 1
        m = (reg[y0:y1, x0:x1] == r).astype(np.uint8)
        er = cv2.erode(m, np.ones((5, 5), np.uint8))
        px = lab[y0:y1, x0:x1][(er if er.any() else m) > 0]
        col[r] = np.median(px, axis=0)

    # small almost-black regions (pupils, nose tips) become part of the line layer
    dark = [r for r in range(1, n + 1) if col[r][0] * 100 / 255 < config.DARK_PREFILL_L
            and geo['area'][r] < config.DARK_PREFILL_MAX_SHARE * reg.size]
    if dark:
        dm = np.isin(reg, dark)
        alpha[dm] = 255; reg[dm] = 0
    keep = np.array([r for r in range(1, n + 1) if r not in set(dark)])
    remap = np.zeros(n + 1, np.int32); remap[keep] = np.arange(1, len(keep) + 1)
    reg = remap[reg]; col = col[np.concatenate([[0], keep])]
    n = len(keep)
    geo = region_geometry(reg)

    # character mask: QA and palette weights
    mask = character_mask(colored)
    bg = int(remap[la.get('background', 0)]) if la.get('background', 0) else 0
    weights = geo['area'][1:].astype(np.float32)
    if mask is not None:
        share = float(mask.mean())
        lo, hi = config.QA_CHARACTER_SHARE
        if not lo <= share <= hi:
            fails.append(f'персонаж занимает {share:.0%} кадра, нужно {lo:.0%}-{hi:.0%}')
        if bg:
            over = float((mask & (reg == bg)).sum() / max(mask.sum(), 1))
            if over > config.QA_BG_ON_CHARACTER_MAX:
                fails.append(f'фон затекает в персонажа ({over:.0%} маски): разрыв в контуре персонажа')
        inside = np.bincount(reg.ravel(), weights=mask.ravel().astype(np.float64), minlength=n + 1)[1:]
        weights = weights * np.where(inside > 0.5 * geo['area'][1:], config.CHARACTER_PALETTE_WEIGHT, 1.0)
    else:
        notes.append('rembg не установлен: проверки персонажа пропущены')
    palette, assign = _palette(col[1:], weights, config.QA[scene.level]['palette'])

    # files for the app
    rgba = np.zeros((config.H, config.W, 4), np.uint8); rgba[..., :3] = 20; rgba[..., 3] = alpha
    Image.fromarray(rgba, 'RGBA').save(out_dir / 'lines.png', optimize=True)
    enc = np.zeros((config.H, config.W, 3), np.uint8)
    enc[..., 0] = (reg >> 8).astype(np.uint8); enc[..., 1] = (reg & 255).astype(np.uint8)
    Image.fromarray(enc, 'RGB').save(out_dir / 'regions.png', optimize=True)
    cimg = Image.fromarray(colored)
    cimg.save(out_dir / 'colored.webp', quality=90, method=6)
    thumb = cimg.resize(config.THUMB, Image.LANCZOS)
    thumb.save(out_dir / 'thumb.webp', quality=85)
    thumb.filter(ImageFilter.GaussianBlur(8)).save(out_dir / 'thumb_locked.webp', quality=80)
    regions = [dict(id=r, palette=assign[r - 1], color=_hex_from_lab8(col[r]), area=int(geo['area'][r]),
                    bbox=[int(geo['x0'][r]), int(geo['y0'][r]), int(geo['x1'][r] - geo['x0'][r] + 1),
                          int(geo['y1'][r] - geo['y0'][r] + 1)],
                    label=[int(geo['label_x'][r]), int(geo['label_y'][r])],
                    label_radius=round(float(geo['radius'][r]), 1)) for r in range(1, n + 1)]
    (out_dir / 'regions.json').write_text(json.dumps(
        dict(width=config.W, height=config.H, level=scene.level, background=bg or None,
             palette=palette, regions=regions), ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    _preview(out_dir / 'preview.jpg', alpha, reg, regions, palette, colored)
    qa = dict(align=round(rec, 3), regions=n, prefilled_dark=len(dark), palette=len(palette),
              fails=fails, notes=notes)
    (out_dir / 'qa.json').write_text(json.dumps(qa, ensure_ascii=False, indent=1), encoding='utf-8')
    return qa


def _preview(path, alpha, reg, regions, palette, colored):
    """QA sheet: lines | numbers / filled with palette | colored version, palette strip"""
    a = alpha[..., None].astype(np.float32) / 255
    page = (255 * (1 - a) + 20 * a).astype(np.uint8).repeat(3, 2)
    num = page.copy()
    for r in regions:
        if r['label_radius'] < 9:
            continue
        s = min(1.4, r['label_radius'] / 22); t = str(r['palette'] + 1)
        (tw, th), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, s, 2)
        cv2.putText(num, t, (r['label'][0] - tw // 2, r['label'][1] + th // 2), cv2.FONT_HERSHEY_SIMPLEX, s, (90, 90, 90), 2)
    rgb = lambda h: [int(h[i:i + 2], 16) for i in (1, 3, 5)]
    lut = np.full((len(regions) + 1, 3), 255, np.uint8)
    for r in regions:
        lut[r['id']] = rgb(palette[r['palette']])
    filled = (lut[reg] * (1 - a) + 20 * a).astype(np.uint8)
    half = lambda x: cv2.resize(x, (config.W // 2, config.H // 2), interpolation=cv2.INTER_AREA)
    sheet = np.vstack([np.hstack([half(page), half(num)]), np.hstack([half(filled), half(colored)])])
    for (x, y), tag in zip(((0, 0), (config.W // 2, 0), (0, config.H // 2), (config.W // 2, config.H // 2)),
                           ('1 contour', '2 numbers', '3 palette fill', '4 colored')):
        cv2.rectangle(sheet, (x, y), (x + 300, y + 52), (255, 255, 255), -1)
        cv2.rectangle(sheet, (x, y), (x + 300, y + 52), (60, 60, 60), 2)
        cv2.putText(sheet, tag, (x + 12, y + 37), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (30, 30, 30), 2)
    sw = np.full((70, sheet.shape[1], 3), 255, np.uint8)
    step = sheet.shape[1] // max(len(palette), 1)
    for i, h in enumerate(palette):
        x = 10 + i * step
        cv2.rectangle(sw, (x, 10), (x + 70, 60), rgb(h), -1)
        cv2.putText(sw, str(i + 1), (x + 78, 48), cv2.FONT_HERSHEY_SIMPLEX, 1, (40, 40, 40), 2)
    Image.fromarray(np.vstack([sheet, sw])).save(path, quality=85)
