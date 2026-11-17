"""Line art -> line mask, region map and metrics (no colors yet)."""
import cv2
import numpy as np
from PIL import Image
from . import config


def load_4x3(path, mode='RGB'):
    """center-crop to 4:3 and resize to W x H with Lanczos"""
    im = Image.open(path).convert(mode)
    w, h = im.size
    if w * 3 > h * 4:
        nw = h * 4 // 3; im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    elif w * 3 < h * 4:
        nh = w * 3 // 4; im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
    src = np.array(im)
    return src, cv2.resize(src, (config.W, config.H), interpolation=cv2.INTER_LANCZOS4)


def gray_share(gray):
    """share of mid-gray pixels that are not the anti-aliased edge of a line"""
    dark = (gray < 100).astype(np.uint8)
    near = cv2.dilate(dark, np.ones((5, 5), np.uint8)) > 0
    mid = (gray > 60) & (gray < 200) & ~near
    return float(mid.mean())


def _absorb_small(reg, ink, min_px):
    n = reg.max() + 1
    area = np.bincount(reg.ravel(), minlength=n)
    for r in np.nonzero((area > 0) & (area < min_px))[0]:
        if r == 0:
            continue
        ys, xs = np.nonzero(reg == r)
        y0, y1, x0, x1 = max(ys.min() - 10, 0), ys.max() + 11, max(xs.min() - 10, 0), xs.max() + 11
        sub = reg[y0:y1, x0:x1]
        m = (sub == r).astype(np.uint8)
        ring = (cv2.dilate(m, np.ones((15, 15), np.uint8)) > 0) & (sub != r) & (sub > 0)
        if ring.any():
            sub[m > 0] = np.bincount(sub[ring]).argmax()
        else:
            sub[m > 0] = 0
            ink[y0:y1, x0:x1][m > 0] = True
    u, inv = np.unique(reg, return_inverse=True)
    inv = inv.reshape(reg.shape)
    return inv if u[0] == 0 else inv + 1


def region_geometry(reg):
    """per region: area, bbox, label point (deepest pixel), inscribed radius. index = region id"""
    n = reg.max() + 1
    dt = cv2.distanceTransform(np.pad((reg > 0).astype(np.uint8), 1), cv2.DIST_L2, 5)[1:-1, 1:-1]
    flat_r, flat_d = reg.ravel(), dt.ravel()
    order = np.argsort(flat_d, kind='stable')
    best = np.zeros(n, np.int64); best[flat_r[order]] = order          # last write = max distance
    radius = np.zeros(n); np.maximum.at(radius, flat_r, flat_d)
    area = np.bincount(flat_r, minlength=n)
    geo = {}
    ys, xs = np.divmod(np.arange(reg.size), reg.shape[1])
    for name, arr, fn in (('x0', xs, np.minimum), ('y0', ys, np.minimum)):
        a = np.full(n, 1 << 30); fn.at(a, flat_r, arr); geo[name] = a
    for name, arr in (('x1', xs), ('y1', ys)):
        a = np.full(n, -1); np.maximum.at(a, flat_r, arr); geo[name] = a
    by, bx = np.divmod(best, reg.shape[1])
    return dict(area=area, radius=radius, label_x=bx, label_y=by, **geo)


def line_width(ink):
    from skimage.morphology import skeletonize
    if not ink.any():
        return 0.0
    dt = cv2.distanceTransform(ink.astype(np.uint8), cv2.DIST_L2, 5)
    sk = skeletonize(ink)
    return float(np.median(dt[sk]) * 2) if sk.any() else 0.0


def process(path):
    src, up = load_4x3(path, 'L')
    ink = up < config.BIN_THRESHOLD
    n, cc, st, _ = cv2.connectedComponentsWithStats(ink.astype(np.uint8), connectivity=8)
    keep = st[:, cv2.CC_STAT_AREA] >= config.SPECK_PX; keep[0] = False
    ink = keep[cc]
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (config.CLOSE_PX,) * 2)
    ink = cv2.morphologyEx(ink.astype(np.uint8), cv2.MORPH_CLOSE, k) > 0
    n, cc, st, _ = cv2.connectedComponentsWithStats((~ink).astype(np.uint8), connectivity=4)
    holes = st[:, cv2.CC_STAT_AREA] < config.HOLE_TO_INK_PX; holes[0] = False
    ink |= holes[cc] & (cc > 0)
    _, reg = cv2.connectedComponents((~ink).astype(np.uint8), connectivity=4)
    reg = _absorb_small(reg.astype(np.int32), ink, config.MIN_REGION_PX)
    # anti-aliased line alpha: solid inside the line, soft one-pixel edge outside
    soft = cv2.GaussianBlur(ink.astype(np.float32), (0, 0), 0.8)
    alpha = np.maximum(ink * 255, (soft * 255).astype(np.uint8)).astype(np.uint8)
    geo = region_geometry(reg)
    nreg = int(reg.max())
    border = np.unique(np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]]))
    border = border[border > 0]
    bg = int(border[np.argmax(geo['area'][border])]) if len(border) else 0
    areas = geo['area'][1:].astype(float) / reg.size
    others = [a for i, a in enumerate(areas, start=1) if i != bg]
    metrics = dict(regions=nreg, background=bg,
                   gray_share=round(gray_share(src), 5),
                   largest_share=round(max(others) if others else 0.0, 4),
                   line_width=round(line_width(ink), 2),
                   radii=[round(float(r), 1) for r in geo['radius'][1:]])
    return dict(ink=ink, regions=reg.astype(np.uint16), alpha=alpha, metrics=metrics)


def check(metrics, level, anchor_width=None):
    """automatic QA. returns list of human-readable failures (empty = passed)"""
    q = config.QA[level]
    fails = []
    lo, hi = q['regions']
    if not lo <= metrics['regions'] <= hi:
        fails.append(f"областей {metrics['regions']}, нужно {lo}-{hi}")
    if metrics['gray_share'] > config.QA_GRAY_SHARE_MAX:
        fails.append(f"серого {metrics['gray_share']:.2%}: тени или штриховка")
    if metrics['largest_share'] > config.QA_LARGEST_SHARE_MAX:
        fails.append(f"область на {metrics['largest_share']:.0%} кадра: вероятно, разрыв в линии")
    radii = np.array(metrics['radii'])
    ok = float((radii >= q['min_radius_px']).mean()) if len(radii) else 0.0
    if ok < q['min_radius_share']:
        fails.append(f"крупных областей {ok:.0%}, нужно от {q['min_radius_share']:.0%} "
                     f"(радиус от {q['min_radius_px']} px)")
    if anchor_width:
        dev = abs(metrics['line_width'] - anchor_width) / anchor_width
        if dev > config.QA_LINE_WIDTH_TOL:
            fails.append(f"толщина линий {metrics['line_width']:.1f} px, у эталона {anchor_width:.1f}")
    return fails


def save(path, res):
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, ink=np.packbits(res['ink']), regions=res['regions'], alpha=res['alpha'])


def load(path):
    d = np.load(path)
    ink = np.unpackbits(d['ink'])[:config.W * config.H].reshape(config.H, config.W).astype(bool)
    return dict(ink=ink, regions=d['regions'].astype(np.int32), alpha=d['alpha'])
