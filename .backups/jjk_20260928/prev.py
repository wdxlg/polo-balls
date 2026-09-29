import os,sys,glob,base64,io
from PIL import Image,ImageDraw
R='sources/jjk/vfx/'
def tile(paths,cols,cell,labels=None,bg=(40,40,50)):
    rows=(len(paths)+cols-1)//cols
    out=Image.new('RGB',(cols*cell,rows*cell),bg)
    d=ImageDraw.Draw(out)
    for i,p in enumerate(paths):
        im=p if isinstance(p,Image.Image) else Image.open(p).convert('RGBA')
        im.thumbnail((cell,cell))
        out.paste(im,((i%cols)*cell,(i//cols)*cell),im)
        if labels: d.text(((i%cols)*cell+2,(i//cols)*cell+2),labels[i],fill=(255,255,0))
    return out
which=sys.argv[1]
if which=='a':
    ims=[];labs=[]
    for f in sorted(glob.glob(R+'expl1/*/Half Sized/*.png'))+sorted(glob.glob(R+'expl2/*/Half Sized/*.png')):
        im=Image.open(f).convert('RGBA'); w=im.width//8
        ims.append(im.crop((3*w,2*w,4*w,3*w))); labs.append('ex'+os.path.basename(f)[:10])
    for f in [R+'hit1/hit - yellow.png',R+'hit2/Hit-Yellow.png']:
        im=Image.open(f).convert('RGBA'); w=im.width//8
        for fr in (2,5): ims.append(im.crop((fr*w,0,(fr+1)*w,w))); labs.append('hit'+str(fr))
    for f in sorted(glob.glob(R+'particlefx1/*.png')):
        im=Image.open(f).convert('RGBA'); w=im.width//8
        ims.append(im.crop((2*w,2*w,3*w,3*w))); labs.append(os.path.basename(f)[-6:-4])
    for i in (0,4,8): ims.append(R+'lightning/lightning/%d.png'%i); labs.append('lt%d'%i)
    ims.append(R+'bluering/Blue Ring Explosion8.png'); labs.append('ring')
    ims.append(R+'beams/beams.png'); labs.append('beams')
    out=tile(ims,8,120,labs)
else:
    fs=sorted(glob.glob(R+'kenney_particle/PNG/*.png'))
    out=tile(fs,10,96,[os.path.basename(f)[:-4] for f in fs],bg=(20,20,30))
b=io.BytesIO(); out.convert('RGB').save(b,'JPEG',quality=55); print('B64:'+base64.b64encode(b.getvalue()).decode())
