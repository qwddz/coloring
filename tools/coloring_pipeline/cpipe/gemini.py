"""Gemini API calls. The API key comes from GEMINI_API_KEY (or GOOGLE_API_KEY)."""
import io
import time
from pathlib import Path
from PIL import Image
from . import config

EXTS = ('.webp', '.png', '.jpg', '.jpeg')


def _client():
    from google import genai
    return genai.Client()  # reads GEMINI_API_KEY / GOOGLE_API_KEY from the environment


def character_image(cid):
    for e in EXTS:
        p = config.CHARACTER_IMAGES / f'{cid}{e}'
        if p.exists():
            return p
    raise FileNotFoundError(f'character reference {cid}.* not found in {config.CHARACTER_IMAGES} '
                            f'(set CP_CHARACTERS to the folder with Animosaic images)')


def _refs_text(n, first_index=1):
    if n == 1:
        return f'Image {first_index} is the character reference.'
    idx = ', '.join(str(first_index + i) for i in range(n - 1)) + f' and {first_index + n - 1}'
    return f'Images {idx} are the character references.'


def _template(name, **kw):
    return (config.PROMPTS / name).read_text(encoding='utf-8').format(**kw).strip()


def level_clause(level):
    return (config.PROMPTS / f'level_{level}.txt').read_text(encoding='utf-8').strip()


def lineart_request(scene, with_anchor=True):
    """returns (images, prompt) in the order the prompt refers to them"""
    imgs = [character_image(c) for c in scene.characters]
    if with_anchor:
        if not config.STYLE_ANCHOR.exists():
            raise FileNotFoundError(f'style anchor {config.STYLE_ANCHOR} not found: create it first (run.py anchor)')
        prompt = _template('lineart.txt', character_refs=_refs_text(len(imgs)), style_index=len(imgs) + 1,
                           scene=scene.scene, level_clause=level_clause(scene.level))
        imgs.append(config.STYLE_ANCHOR)
    else:
        prompt = _template('anchor.txt', character_refs=_refs_text(len(imgs)),
                           scene=scene.scene, level_clause=level_clause(scene.level))
    return imgs, prompt


def colored_request(scene, lineart_png):
    refs = [character_image(c) for c in scene.characters]
    prompt = _template('colored.txt', character_refs_colored=_refs_text(len(refs), first_index=2))
    return [Path(lineart_png)] + refs, prompt


def generate(images, prompt, out_path, retries=4):
    """one image from Gemini, saved as PNG. Retries rate limits and server errors."""
    from google.genai import types
    image_cfg = dict(aspect_ratio='4:3')
    if config.GEMINI_IMAGE_SIZE:
        image_cfg['image_size'] = config.GEMINI_IMAGE_SIZE
    contents = [Image.open(p) for p in images] + [prompt]
    cfg = types.GenerateContentConfig(response_modalities=['IMAGE'], image_config=types.ImageConfig(**image_cfg))
    client = _client()
    for attempt in range(retries + 1):
        try:
            resp = client.models.generate_content(model=config.GEMINI_MODEL, contents=contents, config=cfg)
            break
        except Exception as e:  # noqa: BLE001 - SDK raises several error types
            code = getattr(e, 'code', None) or getattr(e, 'status_code', None)
            if attempt < retries and (code in (429, 500, 502, 503, 504) or 'RESOURCE_EXHAUSTED' in str(e)):
                time.sleep(10 * 2 ** attempt)
                continue
            raise
    for cand in resp.candidates or []:
        for part in (cand.content.parts if cand.content else []) or []:
            if getattr(part, 'inline_data', None) and part.inline_data.data:
                out_path = Path(out_path)
                out_path.parent.mkdir(parents=True, exist_ok=True)
                Image.open(io.BytesIO(part.inline_data.data)).convert('RGB').save(out_path)
                return out_path
    text = ' '.join(getattr(p, 'text', '') or '' for c in resp.candidates or [] for p in (c.content.parts if c.content else []) or [])
    reason = resp.candidates[0].finish_reason if resp.candidates else getattr(resp, 'prompt_feedback', None)
    raise RuntimeError(f'no image in response (reason: {reason}) {text[:200]}')
