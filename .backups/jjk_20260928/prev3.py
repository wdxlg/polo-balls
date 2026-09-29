import glob,os,base64,io
from PIL import Image,ImageDraw
O='Images/characters/动漫/咒术回战/vfx/'
names=['k_spark03','k_spark04','k_spark05','k_spark06','k_spark07','k_star01','k_star04','k_star06','k_star08','k_symbol01','k_symbol02','k_trace01','k_trace02','k_trace04','k_trace06','k_trace07','k_twirl01','k_twirl02','k_twirl03','k_window01','k_muzzle02','k_flame05','k_slash04','k_light03']
cell=120; out=Image.new('RGB',(cell*8,cell*3),(10,10,20)); d=ImageDraw.Draw(out)
for i,n in enumerate(names):
    im=Image.open(O+n+'.png').convert('RGBA'); im.thumbnail((cell,cell))
    x=(i%8)*cell; y=(i//8)*cell; out.paste(im,(x,y),im); d.text((x+2,y+2),n,fill=(255,255,0))
b=io.BytesIO(); out.save(b,'JPEG',quality=60); print('B64:'+base64.b64encode(b.getvalue()).decode())
