from pathlib import Path
import re,json,shutil
from fontTools.ttLib import TTFont
import argparse
parser = argparse.ArgumentParser(description='Read-only import from an OpenCode source checkout; never executes it.')
parser.add_argument('source', type=Path)
r=parser.parse_args().source
out=Path('Packages/OpencodeKit/Sources/OCDesign/Resources'); out.mkdir(parents=True,exist_ok=True)
fonts=out/'Fonts';fonts.mkdir(exist_ok=True)
licenses=out/'Licenses';licenses.mkdir(exist_ok=True)
shutil.copyfile(r/'packages/ui/src/assets/fonts/Inter.ttf',fonts/'Inter.ttf')
f=TTFont(r/'packages/ui/src/assets/fonts/JetBrainsMonoNerdFontMono-Regular.woff2');f.flavor=None;f.save(fonts/'JetBrainsMonoNerdFontMono-Regular.ttf')
license=(r/'packages/app/src/settings/about/notices/fonts/OFL-1.1.txt').read_text()
for name,year,project in [('Inter',2016,'https://github.com/rsms/inter'),('JetBrainsMono',2020,'https://github.com/JetBrains/JetBrainsMono')]:
 (licenses/(name+'-OFL.txt')).write_text(f'Copyright {year} The {"JetBrains Mono" if name=="JetBrainsMono" else name} Project Authors ({project})\n\n'+license)
shutil.copyfile(r/'packages/ui/LICENSE',licenses/'opencode-MIT.txt')
# Extract literal artwork only; never execute or build the reference clone.
icons={}
s=(r/'packages/ui/src/icons/icon/additional-icons.ts').read_text()
small=set(re.findall(r'name === "([^"]+)"',s))
for name,body in re.findall(r'^  ([\w-]+|"[^"]+"): `([^`]+)`',s,re.M):
 name=name.strip('"');icons[name]=('0 0 16 16' if name in small else '0 0 20 20',body)
s=(r/'packages/ui/src/icons/catalog.ts').read_text()
for name,box,body in re.findall(r'^  ([\w-]+|"[^"]+"): \{\s*viewBox: "([^"]+)",\s*body: `([^`]+)`',s,re.M): icons[name.strip('"')]=(box,body)
# The catalog has no up chevron; Find's Previous match uses chevron-down mirrored vertically.
icons.setdefault('chevron-up',('0 0 16 16','<path d="M5 9.5L8 6.5L11 9.5" stroke="currentColor"/>'))
assets=out/'Icons.xcassets'; assets.mkdir(exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
for name,(box,body) in icons.items():
 dest=assets/(name+'.imageset');dest.mkdir(exist_ok=True)
 (dest/(name+'.svg')).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{box}" width="{box.split()[2]}" height="{box.split()[3]}" fill="none">'+body.replace('currentColor','#000000')+'</svg>\n')
 (dest/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.svg','idiom':'universal'}],'info':{'author':'xcode','version':1},'properties':{'preserves-vector-representation':True,'template-rendering-intent':'template'}},indent=2)+'\n')
print('Imported',len(icons),'icons')

