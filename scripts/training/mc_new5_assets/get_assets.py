from pathlib import Path
import requests,json,hashlib,concurrent.futures
B=Path(__file__).parent;SHA='736072450c26a7c67f07b1661f29d9a5ebaa14b1'
paths=['models/entity/'+n+'.geo.json' for n in ['slime','slime_armor','guardian','ghast','fishing_hook','fireball']]+['animations/guardian.animation.json','animations/ghast.animation.json']+['textures/entity/slime/slime.png','textures/entity/guardian.png','textures/entity/fishhook.png','textures/entity/guardian_beam.png','textures/entity/ghast/ghast.png','textures/entity/ghast/ghast_shooting.png']+['textures/items/'+n+'.png' for n in ['fishing_rod_uncast','fishing_rod_cast','iron_sword','fireball']]+['textures/blocks/'+n+'.png' for n in ['piston_side','piston_top_sticky','piston_inner','piston_bottom','end_rod']]
def get(p):
 u=f'https://raw.githubusercontent.com/Mojang/bedrock-samples/{SHA}/resource_pack/{p}';r=requests.get(u,timeout=30);r.raise_for_status();q=B/'resource_pack'/p;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(r.content);return {'path':p,'url':u,'sha256':hashlib.sha256(r.content).hexdigest()}
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as ex: rows=list(ex.map(get,paths))
(B/'sources.json').write_text(json.dumps({'repository':'Mojang/bedrock-samples','commit':SHA,'license':'Minecraft EULA; Mojang retains copyright. Not permissive open-source assets.','files':rows},indent=2))
print('DOWNLOADED',len(rows))
