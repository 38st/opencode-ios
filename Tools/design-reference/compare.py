#!/usr/bin/env python3
"""Pair real web captures with real native baselines at equal logical viewport sizes."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html,json

root = Path(__file__).resolve().parents[2]
reference = root/'.build/design-reference'
native = root/'Packages/OpencodeKit/Tests/FeatureServersTests/__Snapshots__/DesignScreenTests'
out = root/'.build/design-compare'
out.mkdir(parents=True, exist_ok=True)
pairs = {
    'onboarding': ('connect-pairing', 'Connection entry: platform-specific copy'),
    'server-list': ('session-list', 'Home: project picker, search and sessions by day; native triage sections'),
    'server-management': ('settings-server', 'Settings: server management'),
    'add-server': ('connect-pairing', 'Pairing form'),
    'add-server-password': ('connect-password', 'Password form'),
    're-pair': ('connect-pairing', 'Credential recovery: native re-pair / web connection form'),
    'update': ('settings-server', 'Native upgrade instructions / upstream server settings style'),
    'server-detail': ('settings-server', 'Server settings'),
    'diagnostics': ('settings', 'Native-only diagnostics / upstream settings style'),
    'local-network': ('connect-password', 'Native-only network permission explanation / connection entry'),
}
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 16)
small = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 12)
manifest=[]
for screen,(source,note) in pairs.items():
    for mode in ['light','dark']:
        for width,height in [(393,852),(820,1180),(1180,820)]:
            left=reference/f'{source}-{mode}-{width}x{height}.png'
            right=native/f'screens.{screen}-{mode}-{width}x{height}.png'
            if not left.exists() or not right.exists(): raise SystemExit(f'Missing capture: {left} or {right}')
            image=Image.new('RGB',(width*2+24,height+78),'#eeeeee');draw=ImageDraw.Draw(image)
            draw.text((12,10),f'OpenCode web · {mode} · {width}×{height}',font=font,fill='#161616')
            draw.text((width+24,10),f'Native iOS · {screen}',font=font,fill='#161616')
            draw.text((12,36),note,font=small,fill='#5c5c5c')
            for file,x in [(left,0),(right,width+24)]:
                img=Image.open(file).convert('RGB')
                if img.width*height != img.height*width: raise SystemExit(f'Aspect mismatch: {file} {img.size}')
                image.paste(img.resize((width,height),Image.Resampling.LANCZOS),(x,78))
            name=f'{screen}-{mode}-{width}x{height}.png';image.save(out/name)
            manifest.append({'file':name,'native':str(right.relative_to(root)),'reference':str(left.relative_to(root)),'note':note})
# Explicit shell comparisons in both iPad orientations.
for mode in ['light','dark']:
    for width,height in [(1180,820),(820,1180)]:
        left=Image.open(reference/f'review-{mode}-{width}x{height}.png').convert('RGB')
        right=Image.open(native/f'screens.server-list-{mode}-{width}x{height}.png').convert('RGB').resize((width,height),Image.Resampling.LANCZOS)
        image=Image.new('RGB',(width*2+24,height+78),'#eeeeee');draw=ImageDraw.Draw(image)
        draw.text((12,10),f'OpenCode desktop layout · {width}×{height}',font=font,fill='#161616')
        draw.text((width+24,10),f'Native iPad shell · {width}×{height}',font=font,fill='#161616')
        draw.text((12,36),'Project tabs, timeline slot, disabled prompt dock and review panel. Home sidebar collapses.',font=small,fill='#5c5c5c')
        image.paste(left,(0,78));image.paste(right,(width+24,78))
        name=f'ipad-shell-{mode}' + ('' if width==1180 else '-portrait') + '.png';image.save(out/name)
        manifest.append({'file':name,'note':'Shell composition only'})
for mode in ['light','dark']:
    image=Image.new('RGB',(2384,898),'#eeeeee');draw=ImageDraw.Draw(image)
    draw.text((12,10),'OpenCode Home · 1180×820',font=font,fill='#161616')
    draw.text((1204,10),'Native iPad · expanded Home sidebar',font=font,fill='#161616')
    draw.text((12,36),'Home project picker, search and session hierarchy alongside the native workspace.',font=small,fill='#5c5c5c')
    image.paste(Image.open(reference/f'sidebar-{mode}-1180x820.png').convert('RGB'),(0,78))
    image.paste(Image.open(native/f'screens.workspace-home-{mode}-1180x820.png').convert('RGB').resize((1180,820),Image.Resampling.LANCZOS),(1204,78))
    name=f'ipad-home-sidebar-{mode}.png';image.save(out/name)
    manifest.append({'file':name,'note':'Expanded Home sidebar; session content is a placeholder'})
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(out/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Design comparisons</title><style>body{font:14px system-ui;background:#fafafa;margin:24px;color:#161616}img{max-width:100%;height:auto;border:1px solid #ddd}section{margin:32px 0}nav a{margin-right:16px}</style><h1>Visual comparisons</h1><p>Official web capture on the left; native snapshot on the right. Viewport dimensions match. Labels identify screens without a direct web counterpart.</p>'+''.join(f'<section><h2>{html.escape(x["file"])}</h2><p>{html.escape(x["note"])}</p><a href="{x["file"]}"><img loading="lazy" src="{x["file"]}"></a></section>' for x in manifest))
print(f'Wrote {len(manifest)} comparisons: {out}/index.html')
