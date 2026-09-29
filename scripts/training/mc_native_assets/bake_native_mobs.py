#!/usr/bin/env python3
"""Offline Bedrock sample -> orthographic PNG frames. Runtime has no Python/3D dependency.
Sources pinned by sources.json; originals subject to Minecraft EULA, not an open license.
Only a deliberately small, strict subset of Molang is evaluated. Unknown queries fail.
Enderman legacy humanoid bind coordinates are normalized before pose sampling (see README).
"""
import argparse, copy, json, math, re, hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
W, H = 160, 224

def load_json(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    text = re.sub(r'//[^\n]*', '', text)
    return json.loads(re.sub(r',\s*([}\]])', r'\1', text))

def molang(source, env):
    if isinstance(source, (int, float)): return float(source)
    tokens = re.findall(r'\d+(?:\.\d*)?(?:e[+-]?\d+)?|[a-z_][\w.]*|\|\||&&|==|!=|>=|<=|[^\s]', source.lower())
    index = 0
    precedence = {'||':1, '&&':2, '==':3, '!=':3, '>':4, '<':4, '>=':4, '<=':4, '+':5, '-':5, '*':6, '/':6}
    funcs = {'math.cos':lambda x:math.cos(math.radians(x)), 'math.sin':lambda x:math.sin(math.radians(x)), 'math.pow':pow, 'math.sqrt':math.sqrt, 'math.clamp':lambda x,a,b:min(max(x,a),b), 'query.is_item_equipped':lambda slot:float(slot == 0)}
    def expr(level=0):
        nonlocal index
        token=tokens[index]; index+=1
        if token in ('-', '+', '!'):
            value=expr(7); value=-value if token=='-' else float(not value) if token=='!' else value
        elif token=='(':
            value=expr(); assert tokens[index]==')'; index+=1
        elif re.match(r'^\d', token): value=float(token)
        elif index<len(tokens) and tokens[index]=='(':
            index+=1; args=[expr()]
            while tokens[index]==',': index+=1; args.append(expr())
            assert tokens[index]==')'; index+=1
            value=funcs[token](*args)
        else: value=env[token]
        while index<len(tokens) and tokens[index] in precedence and precedence[tokens[index]]>=level:
            op=tokens[index]; index+=1; other=expr(precedence[op]+1)
            if op=='+': value+=other
            elif op=='-': value-=other
            elif op=='*': value*=other
            elif op=='/': value/=other
            elif op=='||': value=float(bool(value or other))
            elif op=='&&': value=float(bool(value and other))
            elif op=='==': value=float(value==other)
            elif op=='!=': value=float(value!=other)
            elif op=='>': value=float(value>other)
            elif op=='<': value=float(value<other)
            elif op=='>=': value=float(value>=other)
            elif op=='<=': value=float(value<=other)
        if level==0 and index<len(tokens) and tokens[index]=='?':
            index+=1; yes=expr(); assert tokens[index]==':'; index+=1; no=expr(); value=yes if value else no
        return value
    value=expr(); assert index==len(tokens), (source,tokens[index:]); return float(value)

def rotation(angles):
    # Bedrock authored angles -> Y-up model-space (X/Z signs reflected).
    x,y,z=np.radians(np.asarray(angles)*[-1,1,-1]); cx,sx,cy,sy,cz,sz=math.cos(x),math.sin(x),math.cos(y),math.sin(y),math.cos(z),math.sin(z)
    return np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])@np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])

class Baker:
    def __init__(self, source):
        self.source=source; self.animations={}; self.models={}; self.skins={}
        for name in ('humanoid','enderman','evoker','vex','shulker'):
            self.animations.update(load_json(source/f'animations/{name}.animation.json')['animations'])
        for name in ('enderman','evoker','vex','shulker'):
            model=load_json(source/f'models/entity/{name}.geo.json')
            geo=model['minecraft:geometry'][0] if 'minecraft:geometry' in model else next(v for k,v in model.items() if k.startswith('geometry.'))
            self.models[name]=copy.deepcopy(geo['bones'])
        # The legacy enderman sample mixes the humanoid head bind (Y=24) with
        # authored long-limb cubes (shoulder Y=38). Normalize the neutral skeleton;
        # do not apply the engine-specific humanoid base_pose a second time.
        bones=self.models['enderman']
        for bone in bones:
            if bone['name']=='head':
                bone['pivot'][1]+=14
                for cube in bone.get('cubes',[]): cube['origin'][1]+=14
            if bone['name']=='hat':
                # Keep jaw's authored bind; it still inherits head motion at runtime.
                pass
        for name, path in {'enderman':'enderman/enderman.tga','evoker':'illager/evoker.png','vex':'vex/vex.png','vex_charge':'vex/vex_charging.png','shulker':'shulker/shulker_undyed.png'}.items():
            self.skins[name]=np.array(Image.open(source/'textures/entity'/path).convert('RGBA'))
        # Enderman TGA alpha encodes emissivity (eyes alpha=3), not cutout opacity.
        self.skins['enderman'][:,:,3]=255
        self.sword=np.array(Image.open(source/'textures/items/iron_sword.png').convert('RGBA'))
        yaw,pitch=np.radians([30,12])
        self.right=np.array([math.cos(yaw),0,math.sin(yaw)]) # unflipped artwork faces left, like ball.dir_left
        self.camera=np.array([math.sin(yaw)*math.cos(pitch),math.sin(pitch),-math.cos(yaw)*math.cos(pitch)])
        self.up=np.cross(self.right,self.camera)
        self.view=np.array([self.right,-self.up,self.camera])
        self.scale={'enderman':3.35,'evoker':4.55,'vex':6.6,'shulker':4.0}
        self.foot={'enderman':199,'evoker':199,'vex':170,'shulker':199}

    def pose(self, role, state, t, peek=0):
        walk=state in ('walk','angry_walk')
        env={'this':0, 'query.life_time':t, 'query.anim_time':t*360/38.17,
             'variable.tcos0':math.cos(t*math.tau)*28.65 if walk else 0,
             'variable.attack_time':min(t/.5,1), 'variable.empty_handed':0,
             'variable.is_brandishing_spear':0,'variable.is_holding_spyglass':0}
        poses={b['name'].lower():{'position':np.zeros(3),'rotation':np.array(b.get('rotation',[0,0,0]),dtype=float),'scale':np.ones(3)} for b in self.models[role]}
        names=[]
        if role=='enderman':
            names=['humanoid.move']
            if state.endswith('attack'): names+=['humanoid.attack.rotations']
            names+=['humanoid.bob','enderman.arms_legs']
            if state.startswith('angry'): names+=['enderman.scary_face']
        elif role=='evoker':
            # Bedrock controller states are exclusive: celebration does NOT add
            # its arm rotations on top of casting (-135 + -135 caused folded arms).
            if state == 'celebrate':
                names=['humanoid.celebrating']
                poses['arms']['scale']=np.zeros(3) # hide the folded-arm mesh only
            else:
                names=['evoker.casting' if state == 'cast' else 'evoker.general']
                if walk: names+=['evoker.move']
        elif role=='vex':
            # Controller order is charge then idle: the +/-32.34 offsets in charge
            # explicitly compensate for the following idle track.
            names=(['vex.charge'] if state=='charge' else [])+['vex.idle']
        else:
            for k in ('upfacing','northfacing','southfacing','westfacing','eastfacing','xoffset','yoffset','zoffset','xprerotation','zprerotation'): env['variable.shulker.'+k]=0
            env.update({'variable.shulker.peekamount':peek,'variable.shulker.lidpositionfactor':180*(.5+peek),'variable.shulker.lidrotationfactor':-1+math.sin(math.radians(180*(.5+peek)))})
            names=['shulker.facing','shulker.move']
        for name in names:
            for bone, channels in self.animations['animation.'+name]['bones'].items():
                if bone.lower() not in poses: continue
                p=poses[bone.lower()]
                for channel, values in channels.items():
                    if channel not in p: continue
                    if isinstance(values,dict):
                        keys=sorted((float(k),v) for k,v in values.items()); local=t%keys[-1][0]
                        for (a,va),(b,vb) in zip(keys,keys[1:]):
                            if a<=local<=b:
                                values=np.array(va)+(np.array(vb)-va)*(local-a)/(b-a); break
                    if isinstance(values,(float,int,str)): values=[values]*3
                    for i,v in enumerate(values):
                        env['this']=p[channel][i]; value=molang(v,env)
                        if channel=='scale': p[channel][i]=value
                        else: p[channel][i]+=value
        return poses

    def render(self, role, state, t, peek=0):
        bones=self.models[role]; pose=self.pose(role,state,t,peek); world={}; by_name={b['name'].lower():b for b in bones}
        def transform(name):
            name=name.lower()
            if name in world: return world[name]
            b=by_name[name]; p=pose[name]; pivot=np.array(b['pivot'],dtype=float)
            m=np.eye(4); m[:3,:3]=rotation(p['rotation'])@np.diag(p['scale']); m[:3,3]=pivot+p['position']-m[:3,:3]@pivot
            if b.get('parent'): m=transform(b['parent'])@m
            world[name]=m; return m
        self.rgba=np.zeros((H,W,4),np.uint8); self.depth=np.full((H,W),-1e10)
        skin=self.skins['vex_charge' if role=='vex' and state=='charge' else role]
        for bone in bones:
            if bone.get('neverRender'): continue
            if np.min(pose[bone['name'].lower()]['scale'])<.001: continue
            m=transform(bone['name'])
            for cube in bone.get('cubes',[]): self.cube(cube,m,skin,role,bone.get('mirror',False))
        if role=='vex':
            # Flat native item texture, attached to the official rightItem bone.
            # Held-item projection is a 2D-bake adapter, not an exported engine mesh.
            m=transform('rightitem'); x,y,z=by_name['rightitem']['pivot']; size=6.5
            pts=np.array([[x-size/2,y+1,z-1.25],[x+size/2,y+1,z-1.25],[x+size/2,y+1-size,z-1.25],[x-size/2,y+1-size,z-1.25]])
            self.quad(pts,m,np.array([[0,16],[16,16],[16,0],[0,0]]),self.sword,role,1.0)
        return Image.fromarray(self.rgba)

    def cube(self,cube,m,skin,role,mirror):
        x,y,z=cube['origin']; dx,dy,dz=cube['size']; f=cube.get('inflate',0)
        lo=np.array([x-f,y-f,z-f]); hi=np.array([x+dx+f,y+dy+f,z+dz+f])
        verts=np.array([[lo[0],lo[1],lo[2]],[hi[0],lo[1],lo[2]],[hi[0],hi[1],lo[2]],[lo[0],hi[1],lo[2]], [lo[0],lo[1],hi[2]],[hi[0],lo[1],hi[2]],[hi[0],hi[1],hi[2]],[lo[0],hi[1],hi[2]]])
        u,v=cube['uv']; mirror=cube.get('mirror',mirror)
        faces=[([3,2,1,0],(u+dz,v+dz,dx,dy),[0,0,-1]),([6,7,4,5],(u+2*dz+dx,v+dz,dx,dy),[0,0,1]),([7,3,0,4],(u,v+dz,dz,dy),[-1,0,0]),([2,6,5,1],(u+dz+dx,v+dz,dz,dy),[1,0,0]),([7,6,2,3],(u+dz,v,dx,dz),[0,1,0]),([0,1,5,4],(u+dz+dx,v,dx,dz),[0,-1,0])]
        for ids,(a,b,c,d),normal in faces:
            if c==0 or d==0: continue
            n=m[:3,:3]@normal; norm=np.linalg.norm(n)
            if norm<1e-8: continue
            n=n/norm
            if np.dot(n,self.camera)<-.001 and dz!=0: continue
            uv=np.array([[a,b],[a+c,b],[a+c,b+d],[a,b+d]],float)
            if mirror: uv=uv[[1,0,3,2]]
            lighting=.76+.24*max(0,float(np.dot(n,np.array([-.35,.8,-.48]))))
            self.quad(verts[ids],m,uv,skin,role,lighting)

    def quad(self,points,m,uv,skin,role,lighting):
        p=points@m[:3,:3].T+m[:3,3]; p=p@self.view.T
        p[:,:2]*=self.scale[role]; p[:,0]+=W/2; p[:,1]+=self.foot[role]
        for ids in ([0,1,2],[0,2,3]):
            v=p[ids]; tex=uv[ids]; x0=max(0,int(math.floor(v[:,0].min()))); x1=min(W,int(math.ceil(v[:,0].max()))); y0=max(0,int(math.floor(v[:,1].min()))); y1=min(H,int(math.ceil(v[:,1].max())))
            if x1<=x0 or y1<=y0: continue
            xx,yy=np.meshgrid(np.arange(x0,x1)+.5,np.arange(y0,y1)+.5)
            det=(v[1,1]-v[2,1])*(v[0,0]-v[2,0])+(v[2,0]-v[1,0])*(v[0,1]-v[2,1])
            if abs(det)<1e-8: continue
            a=((v[1,1]-v[2,1])*(xx-v[2,0])+(v[2,0]-v[1,0])*(yy-v[2,1]))/det
            b=((v[2,1]-v[0,1])*(xx-v[2,0])+(v[0,0]-v[2,0])*(yy-v[2,1]))/det; c=1-a-b
            depth=a*v[0,2]+b*v[1,2]+c*v[2,2]
            u=a*tex[0,0]+b*tex[1,0]+c*tex[2,0]; vv=a*tex[0,1]+b*tex[1,1]+c*tex[2,1]
            rgba=skin[np.clip(vv.astype(int),0,skin.shape[0]-1),np.clip(u.astype(int),0,skin.shape[1]-1)].copy()
            rgba[:,:,:3]=(rgba[:,:,:3].astype(float)*lighting).astype(np.uint8)
            mask=(a>=-1e-6)&(b>=-1e-6)&(c>=-1e-6)&(depth>=self.depth[y0:y1,x0:x1]-1e-6)&(rgba[:,:,3]>10)
            self.rgba[y0:y1,x0:x1][mask]=rgba[mask]; self.depth[y0:y1,x0:x1][mask]=depth[mask]

CLIPS={
 'enderman':{'idle':(48,360/103.2,True),'walk':(24,1.0,True),'angry_idle':(48,360/103.2,True),'angry_walk':(24,1.0,True),'attack':(16,.5,False),'angry_attack':(16,.5,False)},
 'evoker':{'idle':(1,1.0,True),'walk':(24,1.0,True),'cast':(16,360/763.4,True),'celebrate':(16,360/800,True)},
 'vex':{'fly':(48,2.0,True),'charge':(48,2.0,True)},
 'shulker':{'closed':(1,1.0,True),'open':(24,.5,False),'hold':(48,360/114.6,True),'close':(24,.5,False)}}

def bake(output):
    b=Baker(ROOT/'resource_pack'); output.mkdir(parents=True,exist_ok=True); manifest={'size':[W,H],'source_commit':(ROOT/'commit.txt').read_text().strip(),'roles':{}}
    preview=[]
    for role,clips in CLIPS.items():
        files=[]; anims=[]; roledata={'clips':{},'foot_y':b.foot[role]}; dedup={}
        for state,(count,duration,loop) in clips.items():
            ids=[]; frames=[]
            for i in range(count):
                fraction=i/(count-1) if not loop and count>1 else i/count
                peek=fraction if state=='open' else 1-fraction if state=='close' else float(state=='hold')
                image=b.render(role,state,fraction*duration,peek); digest=hashlib.sha256(image.tobytes()).hexdigest()
                if digest not in dedup:
                    file=f'{role}_{len(files):03}.png'; image.save(output/file,optimize=True); files.append(file); dedup[digest]=len(files)
                ids.append(dedup[digest]); frames.append(image)
            if state in ('walk','cast','fly','charge','open','angry_walk'): preview.append((role+' / '+state,frames))
            roledata['clips'][state]={'count':count,'duration':duration,'loop':loop,'unique':len(set(ids))}
            anims.append('{"frames": ['+', '.join('{"duration": 1.0, "texture": ExtResource("'+str(j)+'")}' for j in ids)+'], "loop": '+str(loop).lower()+', "name": &"'+state+'", "speed": '+str(count/duration)+'}')
        neutral='closed' if role=='shulker' else 'fly' if role=='vex' else 'idle'
        bbox=b.render(role,neutral,0).getbbox(); roledata['neutral_bounds']=list(bbox); roledata['textures']=len(files); manifest['roles'][role]=roledata
        resource='[gd_resource type="SpriteFrames" format=3]\n\n'+'\n'.join('[ext_resource type="Texture2D" path="res://Images/characters/我的世界/native_frames/'+file+'" id="'+str(i+1)+'"]' for i,file in enumerate(files))+'\n\n[resource]\nanimations = ['+',\n'.join(anims)+']\n'
        (output/f'{role}.tres').write_text(resource,encoding='utf-8'); print(role,roledata,flush=True)
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    contact=Image.new('RGB',(W*5,len(preview)*(H+24)),(37,43,53)); d=ImageDraw.Draw(contact)
    for row,(label,frames) in enumerate(preview):
        d.text((10,row*(H+24)+5),label,fill='white')
        for col in range(5): contact.paste(frames[int(col*(len(frames)-1)/4)],(col*W,row*(H+24)+24),frames[int(col*(len(frames)-1)/4)])
    contact.save(ROOT/'contact.png')
    gif=[]
    for i in range(96):
        im=Image.new('RGB',(W*4,H+30),(37,43,53)); d=ImageDraw.Draw(im)
        for j,(role,state) in enumerate([('enderman','angry_walk'),('evoker','cast'),('vex','charge'),('shulker','open')]):
            t=i/24; peek=(1-math.cos(t*math.pi))/2 if role=='shulker' else 0
            pic=b.render(role,state,t,peek); im.paste(pic,(j*W,25),pic); d.text((j*W+20,8),role,fill='white')
        gif.append(im)
    gif[0].save(ROOT/'native_preview.gif',save_all=True,append_images=gif[1:],duration=42,loop=0,disposal=2)

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=Path,default=ROOT/'frames'); args=parser.parse_args(); bake(args.output)
