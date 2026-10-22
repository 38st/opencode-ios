from pathlib import Path
import re,json
import argparse
parser = argparse.ArgumentParser(description='Read-only import from an OpenCode source checkout; never executes it.')
parser.add_argument('source', type=Path)
parser.add_argument('--resolved', type=Path, help='Directory containing computed-tokens-light/dark.json from the served UI')
args=parser.parse_args()
r=args.source; ui=r/'packages/ui/src'
root=Path('Packages/OpencodeKit/Sources/OCDesign'); assets=root/'Resources/Colors.xcassets'; assets.mkdir(exist_ok=True)
(assets/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
theme=json.loads((ui/'theme/themes/oc-2.json').read_text()); primitives=dict(re.findall(r'--([\w-]+):\s*(#[\da-fA-F]+);',(ui/'styles/tokens/colors.css').read_text()))
# The default preset explicitly overrides every V2 semantic colour in the CSS.
css=(ui/'styles/tokens/theme.css').read_text(); old=(ui/'styles/theme.css').read_text()
aliases={'background':'v2-background-bg-base','backgroundDeep':'v2-background-bg-deep', **{'layer'+str(i):f'v2-background-bg-layer-0{i}' for i in range(1,5)}, 'surface':'v2-background-bg-button-neutral','contrast':'v2-background-bg-contrast','text':'v2-text-text-base','textMuted':'v2-text-text-muted','textFaint':'v2-text-text-faint','textInverse':'v2-text-text-inverse','textContrast':'v2-text-text-contrast','accent':'v2-text-text-accent','accentBackground':'v2-background-bg-accent','icon':'v2-icon-icon-base','iconMuted':'v2-icon-icon-muted','border':'v2-border-border-base','borderMuted':'v2-border-border-muted','borderStrong':'v2-border-border-strong','focus':'v2-border-border-focus','hover':'v2-overlay-simple-overlay-hover','pressed':'v2-overlay-simple-overlay-pressed','scrim':'v2-overlay-simple-overlay-scrim'}
for state in ['success','warning','danger','info']:
 aliases[state]='v2-state-fg-'+state;aliases[state+'Background']='v2-state-bg-'+state;aliases[state+'Border']='v2-state-border-'+state
aliases['toggleThumb'] = 'v2-grey-200'
for name in ['comment','keyword','string','primitive','property','type','constant','critical','diff-add','diff-delete','diff-unknown','info','object','operator','punctuation','regexp','success','variable','warning']:
 aliases['syntax'+''.join(x.title() for x in name.split('-'))]='syntax-'+name
for name in ['add','delete']:
 for level in ['base','weak','strong']:
  aliases['diff'+('Add' if name=='add' else 'Remove')+('' if level=='base' else level.title())]='surface-diff-'+name+'-'+level
values={}
for mode in ['light','dark']:
 section=css.split('[data-color-scheme="'+mode+'"] {')[-1].split('\n  }')[0]
 oldSection=old.split('@media (prefers-color-scheme: dark)')[0 if mode=='light' else 1]
 pool={**primitives,**dict(re.findall(r'--([\w-]+):\s*([^;]+);',oldSection)),**dict(re.findall(r'--([\w-]+):\s*([^;]+);',section)),**theme[mode]['overrides'],**theme[mode]['v2Overrides']}
 if args.resolved:
  pool.update(json.loads((args.resolved/f'computed-tokens-{mode}.json').read_text()))
 def resolve(key):
  value=pool[key].strip()
  if value.startswith('var('): return resolve(re.match(r'var\(--([\w-]+)',value)[1])
  if value.startswith('#'):
   v=value[1:]
   if len(v) in [3,4]:v=''.join(c+c for c in v)
   v=v+'ff' if len(v)==6 else v
   return [int(v[i:i+2],16)/255 for i in range(0,8,2)]
  if value.startswith('rgba('):
   parts=[float(x.strip()) for x in value[5:-1].split(',')];return [x/255 for x in parts[:3]]+[parts[3]]
  raise ValueError((key,value))
 values[mode]={name:resolve(key) for name,key in aliases.items()}
for name in aliases:
 dest=assets/('oc2-'+name+'.colorset');dest.mkdir(exist_ok=True)
 colors=[]
 for mode in ['light','dark']:
  v=values[mode][name];item={'idiom':'universal','color':{'color-space':'srgb','components':dict(zip(['red','green','blue','alpha'],[f'{x:.8f}' for x in v]))}}
  if mode=='dark':item['appearances']=[{'appearance':'luminosity','value':'dark'}]
  colors.append(item)
 (dest/'Contents.json').write_text(json.dumps({'colors':colors,'info':{'author':'xcode','version':1}},indent=2)+'\n')
s='''// Sources: packages/ui/src/theme/themes/oc-2.json, styles/tokens/{colors,theme}.css,
// theme/resolve.ts and styles/theme.css (diff/syntax surfaces). Preserve the default preset's explicit overrides.
import SwiftUI

public enum OCTheme: String, Sendable {
    case openCode = "oc2"
    public func color(_ name: String) -> Color { Color(rawValue + "-" + name, bundle: .module) }
}

public enum OCColor {
'''
for name,key in aliases.items():s+=f'    /// `{key}`\n    public static let {name} = OCTheme.openCode.color("{name}")\n'
s+='}\n';(root/'Colors.swift').write_text(s)
print('Imported',len(aliases),'semantic pairs', {m:values[m]['background'] for m in values})
