# Пайплайн картинок раскраски

Сцена из `scenes.csv` → контур (Gemini) → автопроверка → ручная проверка → цветная версия (Gemini) → данные для приложения → ручная проверка → экспорт в assets, на CDN и в манифест. Подробно про стиль и пороги — в `docs/PLAN.md`, раздел «Пайплайн генерации картинок».

## Установка

```
cd tools/coloring_pipeline
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
export GEMINI_API_KEY=...                       # ключ Gemini API
export CP_CHARACTERS=/путь/к/картинкам/animosaic   # файлы <character_id>.webp из Animosaic
```

При первой сборке rembg скачает модель `isnet-general-use` (около 180 МБ).

Необязательные переменные: `CP_GEMINI_MODEL` (модель, по умолчанию `gemini-nano-banana-2.1`), `CP_GEMINI_IMAGE_SIZE` (например `2K`; по умолчанию 1K — его хватает, см. PLAN.md), `CP_WORK`, `CP_DIST`, `CP_APP_ASSETS`, `CP_STYLE_ANCHOR`, `CP_SCENES`, `CP_CATEGORIES`. Перед запуском сверьте id моделей с актуальной документацией Gemini API.

## Порядок работы

```
python run.py anchor home_fox_cocoa -n 4   # 1. варианты эталона стиля -> work/anchor/
#    лучший скопировать в docs/coloring_refs/style_anchor.png
python run.py lineart --limit 10           # 2. контуры с автопроверкой
python run.py review lineart               # 3. открыть work/review_lineart.html
python run.py accept lineart ID ID ...     #    или: python run.py reject lineart ID --reason "..."
python run.py colored                      # 4. цветные версии и сборка данных
python run.py review final                 # 5. открыть work/review_final.html
python run.py accept final ID ID ...       #    или: reject final ID [--lineart] [--reason "..."]
python run.py export                       # 6. assets/coloring/free, assets/thumbs, dist/, manifest.json
python run.py status                       # где что находится
```

Страница проверки собирает команду `accept` или `reject` по отмеченным карточкам — её остаётся скопировать в терминал.

- Брак автопроверки сразу удаляется и при следующем запуске генерируется заново; копия лежит в `work/rejected/`. Флаг `--keep-failed` оставляет такие картинки на ручную проверку (удобно на пробной партии).
- После трёх неудач сцена пропускается: поменяйте текст сцены в `scenes.csv` и выполните `python run.py reset ID`.
- Если разрыв в контуре слил две области разного цвета (снег и хвоя), а цветная версия их различает: `python run.py split ID REGION ...` делит область по границе цветов и рисует там линию толщиной как у соседних. Номера остальных областей и палитра не меняются, поэтому сохранённые работы не ломаются; новые части получают номера после последнего. Затем `export` и `upload.py`. `build` пересобирает картинку из контура, и деление придётся повторить.
- После правки порогов в `cpipe/config.py` не нужно генерировать заново: `python run.py recheck` перепроверит контуры, `python run.py build` пересоберёт данные.
- `dist/` загружается командой `python upload.py` (сначала `--dry-run`) в бакет R2 пазлов под префикс `colors/`: `<category>/<id>.zip`, превью, последним `manifest.json`. Корень бакета (манифест и картинки пазлов) не трогается. Ключи `R2_*` — в `.env`. Адреса в манифесте относительные; приложение собирается с `CDN_BASE_URL=https://cdn.animosaic.app/colors`. К адресу архива добавляется `?v=<начало sha256>`: имя архива при исправлении картинки не меняется, а узлы CDN хранят его сутки, и без этого приложение получило бы старый архив и не прошло бы проверку sha256.

## Что лежит где

| Путь | Что это |
| --- | --- |
| `scenes.csv` | Сцены: id, категория, персонажи (id из Animosaic через `\|`), сцена на английском, названия uk/en/ru, уровень `simple`/`medium`, free, порядок |
| `categories.csv` | Категории и их названия |
| `prompts/` | Шаблоны промптов: эталон, контур, цветная версия, уточнение уровня |
| `cpipe/config.py` | Пути и пороги автопроверки (стартовые, калибруются на пробной партии) |
| `cpipe/gemini.py` | Запросы к Gemini API |
| `cpipe/lineart.py` | Контур → линии, карта областей, метрики, автопроверка контура |
| `cpipe/build.py` | Совмещение с цветной версией, цвета областей, палитра, проверки персонажа, файлы для приложения |
| `cpipe/review.py`, `cpipe/export.py` | Страницы проверки и экспорт |
| `cpipe/split.py` | Деление области, слитой разрывом линии, по цветной версии |
| `work/` | Сгенерированное и промежуточное (не в git) |
| `dist/` | Файлы для CDN (не в git) |

`scenes.csv` сейчас содержит 10 сцен пробной партии. Id персонажей (`canines_fox`, `farm_pig`, ...) должны совпадать с именами файлов картинок Animosaic — сверьте их с `animals.csv` Animosaic.
