"""Split a region that a gap in the line art merged, along the color edge of the colored version.

Works on a built picture (work/build/<id>/) in place. Existing region ids and the palette stay as
they are, so saved works keep their colors; the new parts get new ids after the last one.
The new line follows the boundary between the two main colors of the region and has the width
of the picture's lines. A rebuild (`run.py build`) starts from the line art again and drops it.
"""
import json
import cv2
import numpy as np
from PIL import Image
from .build import _hex_from_lab8, _preview
from .lineart import region_geometry

MIN_PART_SHARE = 0.03   # color patches smaller than this share of the region are not split off
MIN_PART_PX = 300       # parts the new line cuts off that are smaller than this join a neighbour


def _lab(rgb):
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)


def _two_colors(lab, mask, line_width):
    """label 1 where the pixel belongs to the less common of the two main colors.
    Clustered on the region's inner pixels only: the colored version's own outlines sit a few
    pixels off the line art and would otherwise make 'dark' one of the two colors."""
    from scipy.ndimage import distance_transform_edt
    core = cv2.erode(mask.astype(np.uint8), np.ones((int(line_width) | 1,) * 2, np.uint8)) > 0
    core &= lab[..., 0] > 90
    if core.sum() < 2:
        return None
    px = lab[core].astype(np.float32)
    crit = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5)
    cv2.setRNGSeed(1)
    _, lbl, _ = cv2.kmeans(px, 2, None, crit, 3, cv2.KMEANS_PP_CENTERS)
    lbl = lbl.ravel()
    minor = int(np.argmin(np.bincount(lbl, minlength=2)))
    out = np.zeros(mask.shape, np.float32); out[core] = (lbl == minor)
    _, (iy, ix) = distance_transform_edt(~core, return_indices=True)
    return np.where(mask, out[iy, ix], 0).astype(np.float32)


def local_line_width(ink, near):
    """median width of the lines around the regions, so the new line matches its neighbours"""
    from skimage.morphology import skeletonize
    zone = cv2.dilate(near.astype(np.uint8), np.ones((41, 41), np.uint8)) > 0
    dt = cv2.distanceTransform(ink.astype(np.uint8), cv2.DIST_L2, 5)
    sk = skeletonize(ink & zone)
    return float(np.median(dt[sk]) * 2) if sk.any() else 9.0


def split(out_dir, region_ids, line_width=None):
    reg_img = np.array(Image.open(out_dir / 'regions.png').convert('RGB')).astype(np.int32)
    reg = reg_img[..., 0] * 256 + reg_img[..., 1]
    lines = np.array(Image.open(out_dir / 'lines.png'))
    colored = np.array(Image.open(out_dir / 'colored.webp').convert('RGB'))
    meta = json.loads((out_dir / 'regions.json').read_text(encoding='utf-8'))
    lab = _lab(cv2.medianBlur(colored, 7))
    pal_lab = _lab(np.array([[[int(h[i:i + 2], 16) for i in (1, 3, 5)] for h in meta['palette']]], np.uint8))[0]
    pal_lab = pal_lab.astype(np.float32)
    ink = lines[..., 3] > 127
    if line_width is None:
        line_width = local_line_width(ink, np.isin(reg, region_ids))
    report = []
    added = np.zeros_like(ink)
    split_ids = set()
    for rid in region_ids:
        m = reg == rid
        if not m.any():
            raise ValueError(f'region {rid} not found')
        minor = _two_colors(lab, m, line_width)
        if minor is None:
            report.append(f'{rid}: too thin or dark, nothing to split'); continue
        # smooth the color edge so the new line is a clean curve; strips thinner than a few line
        # widths (a rim of color along an existing line) are not split off, they would double it
        side = (cv2.GaussianBlur(minor, (0, 0), 4) > 0.5) & m
        disk = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (int(line_width * 2) | 1,) * 2)
        side = cv2.morphologyEx(side.astype(np.uint8), cv2.MORPH_OPEN, disk) > 0
        side = m & ~(cv2.morphologyEx((m & ~side).astype(np.uint8), cv2.MORPH_OPEN, disk) > 0)
        for part in (side, m & ~side):
            n, cc, st, _ = cv2.connectedComponentsWithStats(part.astype(np.uint8), connectivity=4)
            for k in range(1, n):
                if st[k, cv2.CC_STAT_AREA] < MIN_PART_SHARE * m.sum():
                    side ^= cc == k
        edge = m & (cv2.dilate(side.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0) & ~side
        if not edge.any():
            report.append(f'{rid}: one color, nothing to split'); continue
        dist = cv2.distanceTransform((~edge).astype(np.uint8), cv2.DIST_L2, 5)
        new_ink = m & (dist <= line_width / 2)
        ink |= new_ink
        added |= new_ink
        reg[new_ink] = 0
        n, cc = cv2.connectedComponents((m & ~new_ink).astype(np.uint8), connectivity=4)
        # crumbs left between the new and the old line join the neighbouring part
        for k in range(1, n):
            crumb = cc == k
            if 0 < crumb.sum() < MIN_PART_PX:
                # reach across the new line too: a crumb can be shut in between it and an old one
                reach = int(line_width) + 4 | 1
                ring = (cv2.dilate(crumb.astype(np.uint8), np.ones((reach, reach), np.uint8)) > 0) & (cc > 0) & ~crumb
                if ring.any():
                    cc[crumb] = np.bincount(cc[ring]).argmax()
                else:
                    cc[crumb] = 0; reg[crumb] = 0; ink |= crumb; added |= crumb
        parts = sorted((k for k in range(1, n) if (cc == k).any()), key=lambda k: -(cc == k).sum())
        # the largest part of the region's current color keeps the id
        old = next(r for r in meta['regions'] if r['id'] == rid)
        old_lab = _lab(np.array([[[int(old['color'][i:i + 2], 16) for i in (1, 3, 5)]]], np.uint8))[0, 0]
        old_lab = old_lab.astype(np.float32)
        meds = {k: np.median(lab[cc == k], axis=0) for k in parts}
        near = [k for k in parts if float(((meds[k] - old_lab) ** 2).sum()) < 20 ** 2]
        keep = near[0] if near else min(parts, key=lambda k: float(((meds[k] - old_lab) ** 2).sum()))
        new_ids = []
        for k in parts:
            if k == keep:
                continue
            nid = int(reg.max()) + 1
            reg[cc == k] = nid
            new_ids.append(nid)
        split_ids.add(rid)
        report.append(f'{rid}: split into {rid} + {new_ids}, line {line_width:.1f} px')
    # region geometry and colors for every touched id
    geo = region_geometry(reg)
    by_id = {r['id']: r for r in meta['regions']}
    for rid in range(1, int(reg.max()) + 1):
        if rid in by_id and rid not in split_ids:
            continue
        m = reg == rid
        er = cv2.erode(m.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        med = np.median(lab[er if er.any() else m], axis=0).astype(np.float32)
        palette = int(np.argmin(((pal_lab - med) ** 2).sum(1)))
        r = by_id.setdefault(rid, dict(id=rid, palette=palette))
        # a kept id keeps its palette index, so saved numbers-mode colors stay correct
        r.update(color=_hex_from_lab8(med), area=int(geo['area'][rid]),
                 bbox=[int(geo['x0'][rid]), int(geo['y0'][rid]), int(geo['x1'][rid] - geo['x0'][rid] + 1),
                       int(geo['y1'][rid] - geo['y0'][rid] + 1)],
                 label=[int(geo['label_x'][rid]), int(geo['label_y'][rid])],
                 label_radius=round(float(geo['radius'][rid]), 1))
    meta['regions'] = [by_id[k] for k in sorted(by_id)]
    # same encoding as build(): solid line plus a soft one-pixel edge
    soft = cv2.GaussianBlur(added.astype(np.float32), (0, 0), 0.8)
    alpha = np.maximum(added * 255, (soft * 255).astype(np.uint8)).astype(np.uint8)
    lines[..., 3] = np.maximum(lines[..., 3], alpha)
    Image.fromarray(lines, 'RGBA').save(out_dir / 'lines.png', optimize=True)
    enc = np.zeros(reg.shape + (3,), np.uint8)
    enc[..., 0] = (reg >> 8).astype(np.uint8); enc[..., 1] = (reg & 255).astype(np.uint8)
    Image.fromarray(enc, 'RGB').save(out_dir / 'regions.png', optimize=True)
    (out_dir / 'regions.json').write_text(json.dumps(meta, ensure_ascii=False, separators=(',', ':')),
                                          encoding='utf-8')
    _preview(out_dir / 'preview.jpg', lines[..., 3], reg, meta['regions'], meta['palette'], colored)
    return report
