import os
from PIL import Image
root='sources/jjk/vfx'
for k in sorted(os.listdir(root)):
    d=os.path.join(root,k)
    if not os.path.isdir(d): continue
    pngs=[]
    for dp,dn,fn in os.walk(d):
        for f in fn:
            if f.lower().endswith('.png') and '__MACOSX' not in dp and not f.startswith('._'): pngs.append(os.path.join(dp,f))
    print('##',k,len(pngs))
    # group by directory
    dirs={}
    for p in pngs: dirs.setdefault(os.path.dirname(p),[]).append(p)
    for dd,ps in sorted(dirs.items())[:14]:
        s=Image.open(ps[0]).size
        print('  ',os.path.relpath(dd,d),len(ps),'e.g.',os.path.basename(ps[0]),s, ' | ', ', '.join(sorted(os.path.basename(x) for x in ps)[:6]))
