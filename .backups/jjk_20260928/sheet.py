import sys,glob,base64,io
from PIL import Image
f=sys.argv[1]; w=int(sys.argv[2]) if len(sys.argv)>2 else 960
im=Image.open(f).convert('RGB'); im=im.resize((w,int(im.height*w/im.width)))
b=io.BytesIO(); im.save(b,'JPEG',quality=60); print('B64:'+base64.b64encode(b.getvalue()).decode())
