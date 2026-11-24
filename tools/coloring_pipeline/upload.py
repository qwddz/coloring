"""Uploads dist/ to the Cloudflare R2 bucket shared with Animosaic puzzles, under a prefix.

Keys in ../../.env or the environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID,
R2_SECRET_ACCESS_KEY, R2_BUCKET (same as puzzles/tools/image_pipeline/upload.py).
Everything goes under `<prefix>/` (default `colors/`), so the puzzles' root
manifest.json, pictures/ and thumbs/ are never touched. The app is built with
CDN_BASE_URL=https://cdn.animosaic.app/colors and resolves the manifest's
relative urls against it.

Every url/thumbUrl/thumbLockedUrl in dist/manifest.json must exist in dist/,
otherwise nothing is uploaded. Objects whose ETag (MD5) already matches are
skipped; manifest.json goes last.

    python upload.py --dry-run
    python upload.py
"""

import argparse
import hashlib
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DIST = ROOT / 'dist'
KEYS = ('R2_ACCOUNT_ID', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_BUCKET')
# zip and thumb names do not change when a picture is rebuilt, so no `immutable`
FILE_CACHE = 'public, max-age=86400'
MANIFEST_CACHE = 'public, max-age=300'
TYPES = {'.zip': 'application/zip', '.webp': 'image/webp', '.json': 'application/json'}


def load_env():
    env = ROOT.parent.parent / '.env'
    if env.exists():
        for line in env.read_text(encoding='utf-8').splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k, v = line.split('=', 1)
                os.environ.setdefault(k.strip(), v.strip())


def endpoint_url(account):
    """Bare account id, or the bucket's full S3 API address (EU buckets)."""
    if '://' not in account:
        return f'https://{account}.r2.cloudflarestorage.com'
    from urllib.parse import urlsplit
    parts = urlsplit(account)
    return f'{parts.scheme}://{parts.netloc}'


def manifest_refs(manifest):
    # `?v=<sha>` only busts the CDN cache; the object name is the path before it
    return {p[k].split('?', 1)[0] for c in manifest.get('categories', []) for p in c.get('pictures', [])
            for k in ('url', 'thumbUrl', 'thumbLockedUrl') if isinstance(p.get(k), str) and '://' not in p[k]}


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--dry-run', action='store_true', help='list what would be uploaded, change nothing')
    parser.add_argument('--prefix', default='colors', help='folder in the bucket (default: colors)')
    args = parser.parse_args()
    prefix = args.prefix.strip('/')
    if not prefix:
        raise SystemExit('an empty prefix would overwrite the puzzles manifest; refusing')

    load_env()
    missing = [k for k in KEYS if not os.environ.get(k)]
    if missing and not args.dry_run:
        raise SystemExit(f'missing in .env or environment: {", ".join(missing)}')
    manifest_path = DIST / 'manifest.json'
    if not manifest_path.exists():
        raise SystemExit('dist/manifest.json not found, run `python run.py export` first')

    files = sorted(p for p in DIST.rglob('*') if p.is_file() and p.name != 'manifest.json' and not p.name.startswith('.'))
    local = {p.relative_to(DIST).as_posix() for p in files}
    absent = sorted(manifest_refs(json.loads(manifest_path.read_text(encoding='utf-8'))) - local)
    if absent:
        for r in absent:
            print(f'missing: {r}')
        raise SystemExit(f'{len(absent)} file(s) in dist/manifest.json are not in dist/; nothing uploaded')

    client = None
    if missing:
        print(f'no credentials ({", ".join(missing)}): no network checks, listing all files')
    else:
        import boto3
        from botocore.config import Config
        client = boto3.client(
            's3', endpoint_url=endpoint_url(os.environ['R2_ACCOUNT_ID']),
            aws_access_key_id=os.environ['R2_ACCESS_KEY_ID'],
            aws_secret_access_key=os.environ['R2_SECRET_ACCESS_KEY'],
            region_name='auto', config=Config(retries={'max_attempts': 5, 'mode': 'standard'}))
    bucket = os.environ.get('R2_BUCKET')

    def remote_etag(key):
        from botocore.exceptions import ClientError
        try:
            return client.head_object(Bucket=bucket, Key=key)['ETag'].strip('"')
        except ClientError as e:
            if e.response['Error']['Code'] in ('404', 'NoSuchKey', 'NotFound'):
                return None
            raise

    uploaded = skipped = 0
    for f in files:
        key = f'{prefix}/{f.relative_to(DIST).as_posix()}'
        if client is not None and remote_etag(key) == md5(f):
            skipped += 1
            continue
        uploaded += 1
        if args.dry_run:
            print(f'would upload {key} ({f.stat().st_size} bytes)')
            continue
        client.upload_file(str(f), bucket, key, ExtraArgs={
            'ContentType': TYPES.get(f.suffix, 'application/octet-stream'), 'CacheControl': FILE_CACHE})
        print(f'uploaded {key}')

    key = f'{prefix}/manifest.json'
    if args.dry_run:
        print(f'would upload {key}')
    else:
        client.upload_file(str(manifest_path), bucket, key,
                           ExtraArgs={'ContentType': 'application/json', 'CacheControl': MANIFEST_CACHE})
        print(f'uploaded {key}')
    verb = 'would be' if args.dry_run else 'were'
    print(f'{uploaded} files {verb} uploaded, {skipped} skipped')


if __name__ == '__main__':
    main()
