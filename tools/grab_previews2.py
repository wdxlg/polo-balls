import base64, textwrap
from PIL import Image
from pathlib import Path
root=Path(r'E:\godot\polo-balls\tests')
for i in range(4):
    im=Image.open(root/f'wither_skeleton_preview_{i}.png').convert('RGB')
    im=im.resize((400,300))
    out=root/f'pv2_{i}.jpg'
    im.save(out,quality=62)
    b64=base64.b64encode(out.read_bytes()).decode()
    (root/f'pv2_{i}.b64').write_text('\n'.join(textwrap.wrap(b64,76)))
print('saved wrapped')
