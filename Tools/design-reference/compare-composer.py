#!/usr/bin/env python3
"""Side-by-side M3b reference captures and native composer snapshots."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw, ImageFont
import html
import json

root = Path(__file__).resolve().parents[2]
output = root / '.build/design-compare'
output.mkdir(parents=True, exist_ok=True)
snapshots = root / 'Packages/OpencodeKit/Tests/ComposerSnapshots/__Snapshots__/ComposerSnapshots'
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
manifest = []
mapping = {'context': 'context', 'commands': 'commands', 'shell': 'shell', 'queue': 'queue',
           'typing': 'typing', 'model-picker': 'model-picker', 'variant-picker': 'variant-picker',
           'agent-picker': 'agent-picker', 'new-session': 'new-session', 'idle': 'idle'}
for native in sorted(snapshots.glob('*.png')):
    name = native.stem.split('.', 1)[-1]
    parts = name.split('-')
    mode = 'dark' if '-dark-' in name else 'light'
    width = 820 if '-820-' in name else 393
    state = next((key for key in mapping if key in name), 'idle')
    reference = root / '.build/design-reference' / f'composer-{mapping[state]}-{mode}-{width}x{1180 if width == 820 else 852}.png'
    if name.startswith('sent-prompt'):
        reference = root / '.build/design-reference' / f'timeline-{mode}-{width}x{1180 if width == 820 else 852}.png'
    left = ImageOps.exif_transpose(Image.open(reference)).convert('RGB')
    right = ImageOps.exif_transpose(Image.open(native)).convert('RGB')
    left = left.resize((width, round(left.height * width / left.width)), Image.Resampling.LANCZOS)
    right = right.resize((width, round(right.height * width / right.width)), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (2 * width + 24, max(left.height, right.height) + 50), '#eeeeee')
    draw = ImageDraw.Draw(canvas)
    draw.text((12, 14), 'Official OpenCode web', font=font, fill='#161616')
    draw.text((width + 24, 14), 'Native iOS composer', font=font, fill='#161616')
    canvas.paste(left, (0, 50)); canvas.paste(right, (width + 24, 50))
    file = 'm3b-' + name + '.png'; canvas.save(output / file)
    manifest.append(dict(file=file, native=str(native.relative_to(root)), reference=str(reference.relative_to(root))))
if not manifest:
    raise SystemExit('No composer snapshots found; record and verify ComposerSnapshots first.')
(output / 'm3b-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(output / 'm3b.html').write_text('<!doctype html><meta charset="utf-8"><title>M3b comparisons</title>'
    '<style>body{font:14px system-ui;margin:24px;background:#fafafa}img{max-width:100%;height:auto}section{margin:32px 0}</style>'
    '<h1>M3b composer and pickers</h1><p>Native controls use 44-point touch targets. Accessibility snapshots use the largest Dynamic Type.</p>'
    + ''.join(f'<section><h2>{html.escape(item["file"])}</h2><a href="{item["file"]}"><img loading="lazy" src="{item["file"]}"></a></section>' for item in manifest))
print(f'Wrote {len(manifest)} comparisons to {output}/m3b.html')
