"""Accepted pictures -> app assets (free), CDN folder (paid) and manifest.json."""
import hashlib
import json
import shutil
import zipfile
from . import config, state
from .scenes import load_categories

LAYERS = ('lines.png', 'regions.png', 'colored.webp', 'regions.json')


def _sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def export(scenes):
    free_dir = config.APP_ASSETS / 'coloring' / 'free'
    thumbs = config.APP_ASSETS / 'thumbs'
    if free_dir.exists():
        shutil.rmtree(free_dir)  # rebuilt from scratch: the folder holds only pipeline output
    free_dir.mkdir(parents=True); thumbs.mkdir(parents=True, exist_ok=True)
    cats = {c['id']: dict(c, pictures=[]) for c in load_categories()}
    free_bytes = 0
    done = [s for s in scenes if state.has('final_ok', s.id)]
    for s in sorted(done, key=lambda s: (s.category, s.order)):
        if s.category not in cats:
            raise ValueError(f'{s.id}: category {s.category!r} is missing in categories.csv')
        src = config.WORK / 'build' / s.id
        entry = dict(id=s.id, title=s.title, characters=s.characters, level=s.level, free=s.free)
        if s.free:
            dst = free_dir / s.id; dst.mkdir()
            for f in LAYERS:
                shutil.copy2(src / f, dst / f)
            shutil.copy2(src / 'thumb.webp', thumbs / f'{s.id}.webp')
            free_bytes += sum((dst / f).stat().st_size for f in LAYERS) + (thumbs / f'{s.id}.webp').stat().st_size
            entry.update(asset=f'coloring/free/{s.id}/', thumb=f'thumbs/{s.id}.webp')
        else:
            cdir = config.DIST / s.category; cdir.mkdir(parents=True, exist_ok=True)
            z = cdir / f'{s.id}.zip'
            with zipfile.ZipFile(z, 'w', zipfile.ZIP_STORED) as zf:  # PNG/WebP are already compressed
                for f in LAYERS:
                    zf.write(src / f, f)
            shutil.copy2(src / 'thumb.webp', cdir / f'{s.id}_thumb.webp')
            shutil.copy2(src / 'thumb_locked.webp', cdir / f'{s.id}_thumb_locked.webp')
            # relative to the app's CDN_BASE_URL (resolveCdnUrl), so moving the CDN needs no re-export
            base = f'{s.category}/{s.id}'
            sha = _sha256(z)
            # the zip keeps its name when a picture is fixed, and the CDN edge caches it for a day;
            # the checksum in the query gives a changed zip a new cache key, else the app would
            # get the old zip, fail the sha256 check and not open the picture
            entry.update(url=f'{base}.zip?v={sha[:8]}', thumbUrl=f'{base}_thumb.webp',
                         thumbLockedUrl=f'{base}_thumb_locked.webp', sha256=sha)
        cats[s.category]['pictures'].append(entry)
    mpath = config.APP_ASSETS / 'manifest.json'
    old = json.loads(mpath.read_text(encoding='utf-8')) if mpath.exists() else {}
    manifest = dict(version=old.get('version', 0) + 1, minAppVersion=old.get('minAppVersion', '1.0.0'),
                    categories=[dict(id=c['id'], title=c['title'], pictures=c['pictures'])
                                for c in sorted(cats.values(), key=lambda c: c['order'])])
    text = json.dumps(manifest, ensure_ascii=False, indent=1)
    mpath.write_text(text, encoding='utf-8')
    config.DIST.mkdir(parents=True, exist_ok=True)
    (config.DIST / 'manifest.json').write_text(text, encoding='utf-8')
    _update_pubspec(sorted(s.id for s in done if s.free))
    return dict(pictures=len(done), free=sum(s.free for s in done), free_mb=round(free_bytes / 2 ** 20, 1),
                manifest_version=manifest['version'], not_ready=[s.id for s in scenes if s not in done])


PUBSPEC_BEGIN = '    # coloring-assets:begin (written by tools/coloring_pipeline export)'
PUBSPEC_END = '    # coloring-assets:end'


def _update_pubspec(free_ids):
    """Flutter does not include subfolders of an asset folder, so every picture folder is listed."""
    path = config.APP_ASSETS.parent / 'pubspec.yaml'
    if not path.exists():
        return
    lines = [PUBSPEC_BEGIN, '    - assets/thumbs/'] + [f'    - assets/coloring/free/{i}/' for i in free_ids] + [PUBSPEC_END]
    text = path.read_text(encoding='utf-8')
    if PUBSPEC_BEGIN in text:
        head, rest = text.split(PUBSPEC_BEGIN, 1)
        tail = rest.split(PUBSPEC_END, 1)[1]
        text = head + '\n'.join(lines) + tail
    else:
        anchor = '    - assets/manifest.json\n'
        if anchor not in text:
            raise ValueError('pubspec.yaml: "- assets/manifest.json" not found under flutter: assets:')
        text = text.replace(anchor, anchor + '\n'.join(lines) + '\n', 1)
    path.write_text(text, encoding='utf-8')
