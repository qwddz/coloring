import csv
from dataclasses import dataclass
from . import config


@dataclass
class Scene:
    id: str
    category: str
    characters: list
    scene: str
    title: dict
    level: str
    free: bool
    order: int


def load_scenes():
    out = []
    with open(config.SCENES_CSV, newline='', encoding='utf-8') as f:
        for r in csv.DictReader(f):
            if not r['id'].strip() or r['id'].startswith('#'):
                continue
            level = r['level'].strip()
            if level not in config.QA:
                raise ValueError(f"{r['id']}: level must be simple or medium, got {level!r}")
            out.append(Scene(
                id=r['id'].strip(), category=r['category'].strip(),
                characters=[c.strip() for c in r['characters'].split('|') if c.strip()],
                scene=r['scene'].strip(),
                title={k: r[f'title_{k}'].strip() for k in ('uk', 'en', 'ru')},
                level=level, free=r['free'].strip().lower() in ('1', 'true', 'yes'),
                order=int(r['order'])))
    ids = [s.id for s in out]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    if dup:
        raise ValueError(f'duplicate ids in scenes.csv: {dup}')
    return out


def load_categories():
    with open(config.CATEGORIES_CSV, newline='', encoding='utf-8') as f:
        rows = [r for r in csv.DictReader(f) if r['id'].strip()]
    return sorted(({'id': r['id'].strip(), 'order': int(r['order']),
                    'title': {k: r[f'title_{k}'].strip() for k in ('uk', 'en', 'ru')}} for r in rows),
                  key=lambda c: c['order'])
