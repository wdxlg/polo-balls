import os,glob,base64,io,re
from PIL import Image,ImageDraw
O='Images/characters/动漫/咒术回战/vfx/'
meta=dict((m[0],(int(m[1]),int(m[2]),int(m[3]))) for m in re.findall(r'"(\w+)":\[(\d+),(\d+),(\d+)\]',open('scripts/characters/动漫/咒术回战/jjk_vfx_atlas.gd',encoding='utf8').read()))
print('SINGLES',' '.join(sorted(os.path.basename(f)[:-4] for f in glob.glob(O+'k_*.png'))))
cell=110; names=sorted(meta); out=Image.new('RGB',(cell*6,cell*len(names)//2+cell),(30,34,40)); d=ImageDraw.Draw(out)
for i,n in enumerate(names):
    c,r,f=meta[n]; im=Image.open(O+n+'.png').convert('RGBA'); w=im.width//c; h=im.height//r
    for j,fr in enumerate((f//5,f//2,f*4//5)):
        cr=im.crop(((fr%c)*w,(fr//c)*h,(fr%c+1)*w,(fr//c+1)*h)); cr.thumbnail((cell,cell))
        x=((i%2)*3+j)*cell; y=(i//2)*cell; out.paste(cr,(x,y),cr)
    d.text(((i%2)*3*cell+2,(i//2)*cell+2),n,fill=(255,255,0))
b=io.BytesIO(); out.save(b,'JPEG',quality=50); print('B64:'+base64.b64encode(b.getvalue()).decode())
