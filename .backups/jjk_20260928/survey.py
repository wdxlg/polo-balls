import glob,re,statistics,os
from PIL import Image
print('bilibili',Image.open('Images/bilibili.png').size)
print('subaru',Image.open('Images/characters/动漫/菜月昴/昴.png').size)
s=open('scenes/ball.tscn',encoding='utf8').read()
i=s.find('[node name="Image"'); print(s[i:i+400])
i=s.find('[node name="CollisionShape2D"'); print(s[i:i+300])
for m in re.finditer(r'\[sub_resource type="CircleShape2D".*?\n(.*?)\n\n',s,re.S): print(m.group(0)[:200])
hp=[];dm=[];sizes=[]
for f in glob.glob('scenes/characters/**/*.tscn',recursive=True):
    t=open(f,encoding='utf8',errors='ignore').read()
    if '咒术回战' in t: continue
    a=re.search(r'^Max_health = ([\d.]+)',t,re.M); b=re.search(r'^Damage = ([\d.]+)',t,re.M)
    if a: hp.append(float(a.group(1)))
    if b: dm.append(float(b.group(1)))
    m=re.search(r'texture = ExtResource\("([^"]+)"\)',t[t.find('[node name="Image"'):] if '[node name="Image"' in t else '')
    if m:
        rid=m.group(1); r=re.search(r'path="res://([^"]+)" id="%s"'%re.escape(rid),t)
        if r and os.path.exists(r.group(1)) and r.group(1).endswith('.png'):
            try:
                w,h=Image.open(r.group(1)).size
                sc=re.search(r'\[node name="Image".*?\n(?:[^\[]*?)scale = Vector2\(([\d.]+)',t,re.S)
                sizes.append((w*(float(sc.group(1)) if sc else 1.0),f))
            except Exception as e: pass
print('n',len(hp),'hp median',statistics.median(hp),'q',statistics.quantiles(hp,n=10))
print('dmg median',statistics.median(dm),'q',statistics.quantiles(dm,n=10),'max',max(dm))
ws=sorted(x[0] for x in sizes); print('img eff width n',len(ws),'median',statistics.median(ws),'q',statistics.quantiles(ws,n=10))
