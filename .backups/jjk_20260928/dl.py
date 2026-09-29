import urllib.request,os,zipfile,json
UA={'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124 Safari/537.36'}
B='https://opengameart.org/sites/default/files/'
items={
 'hit1':('hit-animation-frame-by-frame','hit%20-%20yellow.png'),
 'hit2':('hit-animation-2-frame-by-frame','Hit-Yellow.png'),
 'expl1':('2d-explosion-animations-frame-by-frame','Free%20-%202D%20Explosion%20Animations.zip'),
 'expl2':('2d-explosion-animations-2-frame-by-frame','free%20explosion%20animations%202.zip'),
 'lightning':('lightning-animation','lightning_1.zip'),
 'particlefx1':('animated-particle-effects-1','para_CC0_particlefx-1.zip'),
 'beams':('lasers-and-beams','beams.png'),
 'bluering':('animated-blue-ring-explosion','Blue%20Ring%20Explosion.zip'),
 'fire':('fire-fx-burning-fire-animation','FIRE.zip'),
 'kenney_particle':('particle-pack-80-sprites','kenney_particlePack.zip'),
 'kenney_smoke':('smoke-particle-assets','smokeParticleAssets.zip'),
 'slash_hires':('high-resolution-slash-effects','High%20res%20slashes_1.zip'),
 'slash_coll':('slash-effect-collection','Slash%20Effect%20Collection.zip'),
}
root='sources/jjk/vfx'
os.makedirs(root,exist_ok=True)
src={}
for k,(page,f) in items.items():
    d=os.path.join(root,k); os.makedirs(d,exist_ok=True)
    name=urllib.parse.unquote(f) if hasattr(urllib,'parse') else f
    import urllib.parse; name=urllib.parse.unquote(f)
    out=os.path.join(d,name)
    if not os.path.exists(out):
        import subprocess
        for attempt in range(6):
            r=subprocess.run(['curl.exe','-sSL','--ssl-no-revoke','--retry','5','-C','-','-A',UA['User-Agent'],'-o',out,B+f])
            if r.returncode==0: break
    if out.endswith('.zip'):
        with zipfile.ZipFile(out) as z: z.extractall(d)
    src[k]={'page':'https://opengameart.org/content/'+page,'file':B+f,'license':'CC0'}
    print(k,os.path.getsize(out))
json.dump(src,open(os.path.join(root,'SOURCES.json'),'w'),indent=1)
