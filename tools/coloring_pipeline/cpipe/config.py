"""Paths and thresholds. Thresholds are starting values: calibrate them on the pilot batch."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # tools/coloring_pipeline
PROJECT = ROOT.parent.parent                             # Flutter project root
WORK = Path(os.environ.get('CP_WORK', ROOT / 'work'))    # generated and intermediate files (git-ignored)
DIST = Path(os.environ.get('CP_DIST', ROOT / 'dist'))    # files to upload to the CDN (git-ignored)

SCENES_CSV = Path(os.environ.get('CP_SCENES', ROOT / 'scenes.csv'))
CATEGORIES_CSV = Path(os.environ.get('CP_CATEGORIES', ROOT / 'categories.csv'))
PROMPTS = ROOT / 'prompts'
STYLE_ANCHOR = Path(os.environ.get('CP_STYLE_ANCHOR', PROJECT / 'docs' / 'coloring_refs' / 'style_anchor.png'))
# folder with Animosaic puzzle images named <character_id>.webp / .png / .jpg
CHARACTER_IMAGES = Path(os.environ.get('CP_CHARACTERS', ROOT / 'characters'))
APP_ASSETS = Path(os.environ.get('CP_APP_ASSETS', PROJECT / 'assets'))
CDN_BASE_URL = os.environ.get('CP_CDN_BASE_URL', 'https://cdn.example.com/coloring')

# Gemini. Check model ids in the current Gemini API docs before running.
GEMINI_MODEL = os.environ.get('CP_GEMINI_MODEL', 'gemini-nano-banana-2.1')
GEMINI_IMAGE_SIZE = os.environ.get('CP_GEMINI_IMAGE_SIZE')  # e.g. "2K" if the model supports it; unset = default

W, H = 2048, 1536
MAX_ATTEMPTS = 3            # after this many rejects of one scene: change its text in scenes.csv

# line art processing
BIN_THRESHOLD = 128         # gray below this is line
SPECK_PX = 40               # ink specks smaller than this are removed
CLOSE_PX = 5                # closing kernel for small gaps in lines
HOLE_TO_INK_PX = 40         # white areas smaller than this become line
MIN_REGION_PX = 150         # smaller areas join the neighbor they touch most

# automatic QA, per level
QA = {
    'simple': dict(regions=(40, 180), min_radius_px=20, min_radius_share=0.25, palette=10),
    'medium': dict(regions=(80, 180), min_radius_px=15, min_radius_share=0.25, palette=12),
}
QA_GRAY_SHARE_MAX = 0.005   # gray pixels away from lines = shading or hatching
QA_LARGEST_SHARE_MAX = 0.25 # any region except the background bigger than this = leak through a gap
QA_LINE_WIDTH_TOL = 0.35    # median line width within +-35% of the style anchor
QA_ALIGN_MIN = 0.85         # share of line-art lines found again in the colored version
QA_CHARACTER_SHARE = (0.08, 0.70)
QA_BG_ON_CHARACTER_MAX = 0.03  # share of the character mask covered by the background region

# colors
DARK_PREFILL_L = 20         # small regions darker than this (Lab L, 0-100) are drawn black in lines.png
DARK_PREFILL_MAX_SHARE = 0.005
CHARACTER_PALETTE_WEIGHT = 6.0
THUMB = (400, 300)
