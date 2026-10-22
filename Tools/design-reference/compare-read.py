#!/usr/bin/env python3
"""Compare M2b native captures with the existing official-app reference captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import html, json
root = Path(__file__).resolve().parents[2]
output = root/'.build/design-compare'
output.mkdir(parents=True, exist_ok=True)
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 12)
pairs = [
    ('inbox', 'session-list-light-393x852', 393, 'Home with native cross-server triage and unread markers'),
    ('session-list', 'session-list-light-393x852', 393, 'Project picker, search, letter avatars and sessions by day'),
    ('transcript-tools', 'timeline-light-393x852', 393, 'Native header, tool details and disabled prompt dock'),
    ('ipad-split', 'timeline-light-1180x820', 1180, 'Expanded Home sidebar; empty M4 review panel collapsed'),
    ('ipad-portrait', 'timeline-light-820x1180', 820, 'Portrait timeline with collapsible Home and review'),
]
manifest = []
for native_name, reference_name, width, note in pairs:
    native_file = root/'.build/screenshots'/f'{native_name}.png'
    if native_name == 'session-list' and not native_file.exists(): native_file = root/'.build/screenshots/inbox.png'
    reference_file = root/'.build/design-reference'/f'{reference_name}.png'
    left = ImageOps.exif_transpose(Image.open(reference_file)).convert('RGB')
    right = ImageOps.exif_transpose(Image.open(native_file)).convert('RGB')
    right = right.resize((width, round(right.height * width / right.width)), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (width * 2 + 24, max(left.height, right.height) + 78), '#eeeeee')
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 10), 'Official OpenCode web', fill='#161616', font=font)
    draw.text((width + 24, 10), 'Native iOS · ' + native_name, fill='#161616', font=font)
    draw.text((12, 38), note, fill='#5c5c5c', font=small)
    canvas.paste(left, (0, 78)); canvas.paste(right, (width + 24, 78))
    name = f'm2b-{native_name}.png'; canvas.save(output/name)
    manifest.append(dict(file=name, native=str(native_file.relative_to(root)), reference=str(reference_file.relative_to(root)), note=note))
(output/'m2b-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
(output/'m2b.html').write_text('<!doctype html><meta charset="utf-8"><title>M2b comparisons</title><style>body{font:14px system-ui;margin:24px;background:#fafafa}img{max-width:100%;height:auto}section{margin:32px 0}</style><h1>M2b read screens</h1>'+''.join(f'<section><h2>{html.escape(item["note"])}</h2><img src="{item["file"]}"></section>' for item in manifest))
print(f'Wrote {len(manifest)} comparisons to {output}/m2b.html')
