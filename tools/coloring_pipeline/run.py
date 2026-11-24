#!/usr/bin/env python3
"""Animosaic Colors content pipeline. Run from tools/coloring_pipeline/.

  python run.py status
  python run.py anchor home_fox_cocoa -n 4      # style anchor candidates (no style reference)
  python run.py lineart [--ids ...] [--limit N] # generate + process + auto-check line art
  python run.py review lineart                  # HTML page to look through line art
  python run.py accept lineart ID...            # or: reject lineart ID... --reason "..."
  python run.py colored [--ids ...] [--limit N] # colored versions for accepted line art + build
  python run.py review final
  python run.py accept final ID...              # or: reject final ID... [--lineart]
  python run.py recheck / build [--ids ...]     # re-run processing after changing thresholds
  python run.py export                          # assets, CDN folder, manifest
"""
import argparse
import json
import shutil
import sys

import numpy as np
from PIL import Image

from cpipe import config, state
from cpipe import lineart as la
from cpipe.scenes import load_scenes


def _select(scenes, ids):
    if not ids:
        return scenes
    known = {s.id for s in scenes}
    unknown = [i for i in ids if i not in known]
    if unknown:
        sys.exit(f'unknown ids: {unknown}')
    return [s for s in scenes if s.id in ids]


def anchor_width():
    """median line width of the style anchor, cached by file modification time"""
    if not config.STYLE_ANCHOR.exists():
        return None
    cache = config.WORK / 'anchor_width.json'
    mtime = config.STYLE_ANCHOR.stat().st_mtime
    if cache.exists():
        c = json.loads(cache.read_text())
        if c.get('mtime') == mtime:
            return c['width']
    w = la.process(config.STYLE_ANCHOR)['metrics']['line_width']
    config.WORK.mkdir(parents=True, exist_ok=True)
    cache.write_text(json.dumps(dict(mtime=mtime, width=w)))
    return w


def _save_lineart(s, res, fails):
    base = config.WORK / 'lineart' / s.id
    la.save(base.with_suffix('.npz'), res)
    base.with_suffix('.json').write_text(json.dumps(dict(metrics=res['metrics'], fails=fails), ensure_ascii=False),
                                         encoding='utf-8')
    # clean line art: input for the colored version and the review page
    clean = np.where(res['ink'], 0, 255).astype(np.uint8)
    Image.fromarray(clean).save(base.with_suffix('.png'), optimize=True)
    Image.fromarray(clean).resize((config.W // 2, config.H // 2), Image.LANCZOS).save(base.with_suffix('.jpg'), quality=85)


def _reject_lineart(s, reason, keep_copy=True):
    raw = state.path('raw_lineart', s.id)
    if keep_copy and raw.exists():
        n = state.attempts(s.id, 'lineart') + 1
        dst = config.WORK / 'rejected' / 'lineart' / f'{s.id}_{n}.png'
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(raw), dst)
    for ext in ('.npz', '.json', '.png', '.jpg'):
        p = config.WORK / 'lineart' / f'{s.id}{ext}'
        if p.exists():
            p.unlink()
    state.remove('raw_lineart', s.id)
    return state.bump(s.id, 'lineart', reason)


def process_lineart(s, aw):
    res = la.process(state.path('raw_lineart', s.id))
    fails = la.check(res['metrics'], s.level, aw)
    return res, fails


def cmd_lineart(a, scenes, generate=True):
    from cpipe import gemini
    aw = anchor_width()
    if aw is None and generate:
        sys.exit(f'style anchor {config.STYLE_ANCHOR} not found: run "python run.py anchor" first')
    todo = [s for s in _select(scenes, a.ids) if not state.has('lineart_ok', s.id)
            and (not state.has('lineart', s.id) or not generate)]
    done = 0
    for s in todo:
        if a.limit and done >= a.limit:
            break
        if state.attempts(s.id, 'lineart') >= config.MAX_ATTEMPTS:
            print(f'{s.id}: {config.MAX_ATTEMPTS} неудачи подряд, поменяйте сцену в scenes.csv и сбросьте: '
                  f'python run.py reset {s.id}')
            continue
        raw = state.path('raw_lineart', s.id)
        if not raw.exists():
            if not generate:
                continue
            imgs, prompt = gemini.lineart_request(s)
            print(f'{s.id}: генерация контура...', flush=True)
            try:
                gemini.generate(imgs, prompt, raw)
            except Exception as e:  # noqa: BLE001
                print(f'{s.id}: ошибка генерации: {e}')
                continue
            done += 1
        res, fails = process_lineart(s, aw)
        if fails and not a.keep_failed:
            n = _reject_lineart(s, '; '.join(fails))
            print(f'{s.id}: брак автопроверки (попытка {n}): {"; ".join(fails)}')
        else:
            _save_lineart(s, res, fails)
            print(f"{s.id}: ок, областей {res['metrics']['regions']}" + (f' (с замечаниями: {"; ".join(fails)})' if fails else ''))


def cmd_colored(a, scenes, generate=True):
    from cpipe import gemini
    from cpipe.build import build
    todo = [s for s in _select(scenes, a.ids) if state.has('lineart_ok', s.id) and not state.has('final_ok', s.id)
            and (not state.has('build', s.id) or not generate)]
    done = 0
    for s in todo:
        if a.limit and done >= a.limit:
            break
        if state.attempts(s.id, 'colored') >= config.MAX_ATTEMPTS:
            print(f'{s.id}: {config.MAX_ATTEMPTS} неудачные цветные версии, проверьте контур или промпт')
            continue
        raw = state.path('raw_colored', s.id)
        if not raw.exists():
            if not generate:
                continue
            imgs, prompt = gemini.colored_request(s, config.WORK / 'lineart' / f'{s.id}.png')
            print(f'{s.id}: генерация цветной версии...', flush=True)
            try:
                gemini.generate(imgs, prompt, raw)
            except Exception as e:  # noqa: BLE001
                print(f'{s.id}: ошибка генерации: {e}')
                continue
            done += 1
        data = la.load(config.WORK / 'lineart' / f'{s.id}.npz')
        meta = json.loads((config.WORK / 'lineart' / f'{s.id}.json').read_text(encoding='utf-8'))
        data['background'] = meta['metrics']['background']
        qa = build(s, data, raw, config.WORK / 'build' / s.id)
        if qa['fails'] and not a.keep_failed:
            dst = config.WORK / 'rejected' / 'colored' / f'{s.id}_{state.attempts(s.id, "colored") + 1}.png'
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(raw), dst)
            state.remove('build', s.id); shutil.rmtree(config.WORK / 'build' / s.id, ignore_errors=True)
            n = state.bump(s.id, 'colored', '; '.join(qa['fails']))
            print(f'{s.id}: брак автопроверки (попытка {n}): {"; ".join(qa["fails"])}')
        else:
            print(f"{s.id}: собрано, областей {qa['regions']}, палитра {qa['palette']}, совмещение {qa['align']:.0%}")


def cmd_accept(a, scenes):
    for s in _select(scenes, a.ids):
        if a.step == 'lineart':
            if not state.has('lineart', s.id):
                print(f'{s.id}: нет обработанного контура'); continue
            state.mark('lineart_ok', s.id)
        else:
            if not state.has('build', s.id):
                print(f'{s.id}: не собрана'); continue
            state.mark('final_ok', s.id)
        print(f'{s.id}: принято')


def cmd_reject(a, scenes):
    reason = a.reason or 'ручной брак'
    for s in _select(scenes, a.ids):
        if a.step == 'lineart' or a.lineart:
            state.remove('lineart_ok', s.id); state.remove('final_ok', s.id)
            state.remove('raw_colored', s.id); shutil.rmtree(config.WORK / 'build' / s.id, ignore_errors=True)
            n = _reject_lineart(s, reason)
            print(f'{s.id}: контур в браке (попытка {n}), будет сгенерирован заново')
        else:
            state.remove('final_ok', s.id)
            raw = state.path('raw_colored', s.id)
            if raw.exists():
                dst = config.WORK / 'rejected' / 'colored' / f'{s.id}_{state.attempts(s.id, "colored") + 1}.png'
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.move(str(raw), dst)
            shutil.rmtree(config.WORK / 'build' / s.id, ignore_errors=True)
            n = state.bump(s.id, 'colored', reason)
            print(f'{s.id}: цветная версия в браке (попытка {n}), будет сгенерирована заново')


def cmd_reset(a, scenes):
    st = state.load()
    for s in _select(scenes, a.ids):
        st.pop(s.id, None)
        print(f'{s.id}: счётчики попыток сброшены')
    state.save(st)


def cmd_anchor(a, scenes):
    from cpipe import gemini
    s = _select(scenes, [a.scene_id])[0]
    imgs, prompt = gemini.lineart_request(s, with_anchor=False)
    out = config.WORK / 'anchor'
    for k in range(1, a.n + 1):
        p = out / f'{s.id}_{k}.png'
        print(f'вариант {k}...', flush=True)
        gemini.generate(imgs, prompt, p)
        m = la.process(p)['metrics']
        print(f"  {p}: областей {m['regions']}, серого {m['gray_share']:.2%}, линия {m['line_width']:.1f} px")
    print(f'Выберите лучший вариант и скопируйте его в {config.STYLE_ANCHOR}')


def cmd_split(a, scenes):
    from cpipe.split import split
    s = _select(scenes, [a.scene_id])[0]
    out = config.WORK / 'build' / s.id
    if not (out / 'regions.json').exists():
        sys.exit(f'{s.id}: не собрана')
    for line in split(out, a.regions):
        print(f'{s.id}: {line}')
    print(f'Проверьте {out / "preview.jpg"} и выполните python run.py export')


def cmd_status(a, scenes):
    rows = {'ожидает генерации контура': [], 'контур на проверке': [], 'ожидает цветной версии': [],
            'готова к финальной проверке': [], 'принята': [], 'нужно поменять сцену': []}
    for s in scenes:
        if state.has('final_ok', s.id): k = 'принята'
        elif state.has('build', s.id): k = 'готова к финальной проверке'
        elif state.has('lineart_ok', s.id): k = 'ожидает цветной версии'
        elif state.has('lineart', s.id): k = 'контур на проверке'
        elif max(state.attempts(s.id, 'lineart'), state.attempts(s.id, 'colored')) >= config.MAX_ATTEMPTS:
            k = 'нужно поменять сцену'
        else: k = 'ожидает генерации контура'
        rows[k].append(s.id)
    for k, v in rows.items():
        print(f'{k}: {len(v)}' + (f"  ({', '.join(v[:8])}{' ...' if len(v) > 8 else ''})" if v else ''))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('status')
    p = sub.add_parser('anchor'); p.add_argument('scene_id'); p.add_argument('-n', type=int, default=4)
    for name in ('lineart', 'colored', 'recheck', 'build'):
        p = sub.add_parser(name); p.add_argument('--ids', nargs='*'); p.add_argument('--limit', type=int)
        p.add_argument('--keep-failed', action='store_true', help='keep pictures that failed auto-QA for review')
    p = sub.add_parser('review'); p.add_argument('step', choices=['lineart', 'final'])
    p = sub.add_parser('accept'); p.add_argument('step', choices=['lineart', 'final']); p.add_argument('ids', nargs='+')
    p = sub.add_parser('reject'); p.add_argument('step', choices=['lineart', 'final']); p.add_argument('ids', nargs='+')
    p.add_argument('--reason'); p.add_argument('--lineart', action='store_true', help='final: redo the line art too')
    p = sub.add_parser('reset'); p.add_argument('ids', nargs='+')
    p = sub.add_parser('split', help='split regions merged by a gap in the line art along the colored edge')
    p.add_argument('scene_id'); p.add_argument('regions', nargs='+', type=int)
    sub.add_parser('export')
    a = ap.parse_args()
    scenes = load_scenes()
    if a.cmd == 'lineart': cmd_lineart(a, scenes)
    elif a.cmd == 'recheck': cmd_lineart(a, scenes, generate=False)
    elif a.cmd == 'colored': cmd_colored(a, scenes)
    elif a.cmd == 'build': cmd_colored(a, scenes, generate=False)
    elif a.cmd == 'review':
        from cpipe.review import write
        out, n = write(a.step, scenes)
        print(f'{n} карточек: {out}')
    elif a.cmd == 'accept': cmd_accept(a, scenes)
    elif a.cmd == 'reject': cmd_reject(a, scenes)
    elif a.cmd == 'reset': cmd_reset(a, scenes)
    elif a.cmd == 'anchor': cmd_anchor(a, scenes)
    elif a.cmd == 'status': cmd_status(a, scenes)
    elif a.cmd == 'split': cmd_split(a, scenes)
    elif a.cmd == 'export':
        from cpipe.export import export
        r = export(scenes)
        print(f"экспортировано {r['pictures']} (бесплатных {r['free']}, {r['free_mb']} МБ в assets), "
              f"манифест v{r['manifest_version']}; не готовы: {len(r['not_ready'])}")


if __name__ == '__main__':
    main()
