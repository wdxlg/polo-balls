import sys,base64,io
from PIL import Image
fs=sys.argv[1:]
W,H=480,360
out=Image.new('RGB',(W*2,H*2))
for i,f in enumerate(fs[:4]):
    im=Image.open(f).convert('RGB').resize((W,H)); out.paste(im,((i%2)*W,(i//2)*H))
b=io.BytesIO(); out.save(b,'JPEG',quality=42); print('B64:'+base64.b64encode(b.getvalue()).decode())
