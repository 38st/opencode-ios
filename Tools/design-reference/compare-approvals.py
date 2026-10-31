#!/usr/bin/env python3
"""Compare the native approvals with the captured official OpenCode UI."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import html
import json

root = Path(__file__).resolve().parents[2]
output = root / '.build/design-compare'
output.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 12)
manifest = []

def compare(native, reference, name, width, note):
    left = ImageOps.exif_transpose(Image.open(reference)).convert('RGB')
    right = ImageOps.exif_transpose(Image.open(native)).convert('RGB')
    left = left.resize((width, round(left.height * width / left.width)), Image.Resampling.LANCZOS)
    right = right.resize((width, round(right.height * width / right.width)), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (width * 2 + 24, max(left.height, right.height) + 78), '#eeeeee')
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 10), 'Official OpenCode web', font=font, fill='#161616')
    draw.text((width + 24, 10), 'Native iOS · ' + name, font=font, fill='#161616')
    draw.text((12, 38), note, font=small, fill='#5c5c5c')
    canvas.paste(left, (0, 78)); canvas.paste(right, (width + 24, 78))
    file = 'approvals-' + name + '.png'
    canvas.save(output / file)
    manifest.append(dict(file=file, native=str(native.relative_to(root)), reference=str(reference.relative_to(root)), note=note))

for name in ['permission-dock', 'permission-sheet', 'permission-reject', 'question-sheet', 'question-review']:
    source = name.split('-')[0]
    compare(root / '.build/screenshots' / (name + '.png'),
            root / '.build/design-reference' / (source + '-light-393x852.png'), name, 393,
            'Native review, device authentication and rejection note extend the official request dock.')

snapshots = root / 'Packages/OpencodeKit/Tests/ApprovalSnapshots/__Snapshots__/ApprovalSnapshots'
for native in sorted(snapshots.glob('*.png')):
    name = native.stem.removeprefix('capture-_-name.')
    source = name.split('-')[0]
    if source not in ['permission', 'question']:
        continue
    mode, width = name.split('-')[-2:]
    height = 852 if width == '393' else 1180
    compare(native, root / '.build/design-reference' / f'{source}-{mode}-{width}x{height}.png', name, int(width),
            'Native content at largest Dynamic Type; reference at standard text size. Full content is scrollable.')

(output / 'approvals-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'approvals.html').write_text('<!doctype html><meta charset="utf-8"><title>Approval comparisons</title>'
    '<style>body{font:14px system-ui;margin:24px;background:#fafafa}img{max-width:100%;height:auto}section{margin:32px 0}</style>'
    '<h1>Permissions and questions</h1>' + ''.join(
        f'<section><h2>{html.escape(item["file"])}</h2><p>{html.escape(item["note"])}</p><a href="{item["file"]}"><img loading="lazy" src="{item["file"]}"></a></section>' for item in manifest))
print(f'Wrote {len(manifest)} comparisons to {output}/approvals.html')
