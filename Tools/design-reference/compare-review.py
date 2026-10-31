#!/usr/bin/env python3
"""Side-by-side review reference captures and native review snapshots."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
import html
import json

root = Path(__file__).resolve().parents[2]
output = root / '.build/design-compare'
output.mkdir(parents=True, exist_ok=True)
snapshots = root / 'Packages/OpencodeKit/Tests/ReviewSnapshots/__Snapshots__/ReviewSnapshots'
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
manifest = []
mapping = {'changes-working': 'working', 'changes-branch': 'branch', 'changes-last-turn': 'last-turn',
           'changes-no-git': 'no-git', 'changes-empty': 'empty', 'changes-filter': 'filter',
           'comment-edit': 'comment-editor', 'comment-empty': 'comment-editor', 'comment-composer': 'comment-composer',
           'comment-sent': 'comment-sent', 'files-tree': 'files-tree', 'files-find-in-file': 'file-view', 'files-find': 'files-tree', 'files-source': 'file-view',
           'context-expanded': 'all-lines', 'tool-diff': 'unified'}
for native in sorted(snapshots.glob('*.png')):
    name = native.stem.split('.', 1)[-1]
    mode = 'dark' if '-dark-' in name else 'light'
    width = 820 if '-820-' in name else 393
    state = next((value for key, value in mapping.items() if name.startswith(key)), 'working')
    if name.startswith('turn-'):
        state = 'turn-card'
    elif name.startswith('comment-') and state == 'working':
        state = 'comment-sent' if name.startswith(('comment-only', 'comment-show-more')) else 'comment-composer'
    elif name.startswith('files-') and state == 'working':
        state = 'file-view'
    if name.startswith('diff-'):
        state = 'split' if '-split-' in name else 'unified'
    if width == 393 and state in ['split', 'unified', 'all-lines', 'filter']:
        state = 'last-turn'
    reference = root / '.build/design-reference' / f'review-{state}-{mode}-{width}x{1180 if width == 820 else 852}.png'
    left = ImageOps.exif_transpose(Image.open(reference)).convert('RGB')
    right = ImageOps.exif_transpose(Image.open(native)).convert('RGB')
    left = left.resize((width, round(left.height * width / left.width)), Image.Resampling.LANCZOS)
    right = right.resize((width, round(right.height * width / right.width)), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (2 * width + 24, max(left.height, right.height) + 50), '#eeeeee')
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 14), 'Official OpenCode web', font=font, fill='#161616')
    draw.text((width + 24, 14), 'Native iOS review', font=font, fill='#161616')
    canvas.paste(left, (0, 50)); canvas.paste(right, (width + 24, 50))
    file = 'review-' + name + '.png'; canvas.save(output / file)
    manifest.append(dict(file=file, native=str(native.relative_to(root)), reference=str(reference.relative_to(root))))
if not manifest:
    raise SystemExit('No review snapshots found; record and verify ReviewSnapshots first.')
(output / 'review-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'review.html').write_text('<!doctype html><meta charset="utf-8"><title>Review comparisons</title>'
    '<style>body{font:14px system-ui;margin:24px;background:#fafafa}img{max-width:100%;height:auto}section{margin:32px 0}</style>'
    '<h1>Review and files</h1><p>Official full-screen flows are paired with native component states. Extra native states use their corresponding reference flow, not an exact content match. Native controls use 44-point touch targets. Accessibility snapshots use the largest Dynamic Type.</p>'
    + ''.join(f'<section><h2>{html.escape(item["file"])}</h2><a href="{item["file"]}"><img loading="lazy" src="{item["file"]}"></a></section>' for item in manifest))
print(f'Wrote {len(manifest)} comparisons to {output}/review.html')
