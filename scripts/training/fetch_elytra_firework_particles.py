import urllib.request,pathlib,hashlib,json
base=pathlib.Path(__file__).resolve().parents[2]/"Images/characters/我的世界/elytra_mace"
base.mkdir(parents=True,exist_ok=True)
url="https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.4/assets/minecraft/"
records=[]
for i in range(8):
 name="spark_%d.png"%i
 source=url+"textures/particle/"+name
 data=urllib.request.urlopen(source,timeout=30).read()
 (base/name).write_bytes(data)
 records.append(dict(file=name,url=source,sha256=hashlib.sha256(data).hexdigest()))
(base/"FIREWORK_PARTICLE_SOURCE.json").write_text(json.dumps(dict(source_game="Minecraft Java 1.21.4",definition=url+"particles/firework.json",license="Mojang/Microsoft Minecraft assets, Minecraft EULA applies; unchanged game textures via versioned mirror.",files=records),indent=2),encoding="utf-8")
print("8 vanilla firework spark textures downloaded")
