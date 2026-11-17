"""Pipeline state: which step each scene is at. Folders are the source of truth,
state.json only counts attempts and keeps reject reasons."""
import json
from . import config

STEPS = {
    'raw_lineart': 'raw/lineart/{id}.png',
    'lineart': 'lineart/{id}.npz',            # processed + auto-checked
    'lineart_ok': 'accepted/lineart/{id}',    # marker file after manual accept
    'raw_colored': 'raw/colored/{id}.png',
    'build': 'build/{id}/regions.json',
    'final_ok': 'accepted/final/{id}',
}


def path(step, sid):
    return config.WORK / STEPS[step].format(id=sid)


def has(step, sid):
    return path(step, sid).exists()


def _file():
    return config.WORK / 'state.json'


def load():
    f = _file()
    return json.loads(f.read_text(encoding='utf-8')) if f.exists() else {}


def save(st):
    config.WORK.mkdir(parents=True, exist_ok=True)
    _file().write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding='utf-8')


def bump(sid, kind, reason):
    st = load()
    e = st.setdefault(sid, {})
    e[f'{kind}_attempts'] = e.get(f'{kind}_attempts', 0) + 1
    e.setdefault('rejects', []).append({'step': kind, 'reason': reason})
    save(st)
    return e[f'{kind}_attempts']


def attempts(sid, kind):
    return load().get(sid, {}).get(f'{kind}_attempts', 0)


def mark(step, sid):
    p = path(step, sid)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.touch()


def remove(step, sid):
    p = path(step, sid)
    if p.is_dir():
        import shutil
        shutil.rmtree(p)
    elif p.exists():
        p.unlink()
