"""Static HTML review pages. Accepting and rejecting is done with run.py commands
that the page assembles for you (works from file://, no server)."""
import html
import json
import os
from . import config, state

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>{title}</title><style>
body{{font:14px system-ui,sans-serif;margin:16px;background:#f4f1ea;color:#222}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(520px,1fr));gap:14px}}
.card{{background:#fff;border-radius:10px;padding:10px;box-shadow:0 1px 3px #0002}}
.card img{{width:100%;border-radius:6px;cursor:zoom-in}} .fail{{color:#b3261e}} .note{{color:#6b5e00}}
.meta{{color:#555;margin:4px 0}} .legend{{background:#fff;border-radius:10px;padding:10px 14px;margin:0 0 14px;line-height:1.6}} label{{font-weight:600}} #bar{{position:sticky;top:0;background:#f4f1ea;padding:8px 0}}
code{{display:block;background:#222;color:#eee;padding:8px;border-radius:6px;white-space:pre-wrap;margin-top:6px}}
</style></head><body><div id="bar"><h2>{title}</h2>
<button onclick="gen('accept')">Команда: принять отмеченные</button>
<button onclick="gen('reject')">Команда: забраковать отмеченные</button>
<input id="reason" placeholder="причина брака" size="40"><code id="cmd">отметьте картинки</code></div>
{legend}<div class="grid">{cards}</div><script>
function gen(a){{const ids=[...document.querySelectorAll('input.pick:checked')].map(e=>e.value);
const r=document.getElementById('reason').value.replace(/"/g,"'");
document.getElementById('cmd').textContent=ids.length?`python run.py ${{a}} {step} ${{ids.join(' ')}}`+(a=='reject'&&r?` --reason "${{r}}"`:''):'отметьте картинки';}}
</script></body></html>"""


LEGEND = {
    'final': ('<div class="legend"><b>Как читать лист:</b> '
              '<b>1</b> — контур, как он будет в приложении; '
              '<b>2</b> — номера областей (режим «по номерам»); '
              '<b>3</b> — заливка «правильными» цветами из палитры картинки, так выглядит идеально раскрашенная работа; '
              '<b>4</b> — цветная версия от Gemini, из неё взяты цвета; внизу — палитра картинки. '
              'Главное — сравнить 3 и 4: если на 3 область не того цвета, «правильный» цвет определился неверно.</div>'),
}


def _card(sid, img, scene, lines, fails, notes):
    fs = ''.join(f'<div class="fail">✗ {html.escape(f)}</div>' for f in fails)
    ns = ''.join(f'<div class="note">• {html.escape(n)}</div>' for n in notes)
    return (f'<div class="card"><label><input type="checkbox" class="pick" value="{sid}"> {sid}</label>'
            f'<div class="meta">{html.escape(scene.level)} · {html.escape(scene.scene)}</div>'
            f'<a href="{img}" target="_blank"><img src="{img}" loading="lazy"></a>'
            f'<div class="meta">{html.escape(lines)}</div>{fs}{ns}</div>')


def write(step, scenes):
    out = config.WORK / f'review_{step}.html'
    cards = []
    for s in scenes:
        if step == 'lineart':
            if not state.has('lineart', s.id) or state.has('lineart_ok', s.id):
                continue
            m = json.loads((config.WORK / 'lineart' / f'{s.id}.json').read_text(encoding='utf-8'))
            img = os.path.relpath(config.WORK / 'lineart' / f'{s.id}.jpg', out.parent)
            line = (f"областей {m['metrics']['regions']} · серого {m['metrics']['gray_share']:.2%} · "
                    f"линия {m['metrics']['line_width']:.1f} px · попыток {state.attempts(s.id, 'lineart')}")
            cards.append(_card(s.id, img, s, line, m.get('fails', []), []))
        else:
            if not state.has('build', s.id) or state.has('final_ok', s.id):
                continue
            q = json.loads((config.WORK / 'build' / s.id / 'qa.json').read_text(encoding='utf-8'))
            img = os.path.relpath(config.WORK / 'build' / s.id / 'preview.jpg', out.parent)
            line = f"областей {q['regions']} · палитра {q['palette']} · совмещение {q['align']:.0%}"
            cards.append(_card(s.id, img, s, line, q['fails'], q['notes']))
    title = 'Проверка контуров' if step == 'lineart' else 'Проверка готовых раскрасок'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(PAGE.format(title=title, step=step, legend=LEGEND.get(step, ''),
                               cards=''.join(cards) or '<p>Нечего проверять.</p>'),
                   encoding='utf-8')
    return out, len(cards)
