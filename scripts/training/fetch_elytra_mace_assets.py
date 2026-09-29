import urllib.request,pathlib,hashlib,json
base=pathlib.Path(__file__).resolve().parents[2]
commit="46ba6ea985fb5a92d79a9419198f10dda14c199d"
files=[
("Images/characters/我的世界/elytra_mace/elytra.png","https://raw.githubusercontent.com/Mojang/bedrock-samples/"+commit+"/resource_pack/textures/models/armor/elytra.png",None),
("Images/characters/我的世界/elytra_mace/fireworks.png","https://raw.githubusercontent.com/Mojang/bedrock-samples/"+commit+"/resource_pack/textures/items/fireworks.png",None),
("audio/characters/我的世界/elytra_mace/launch.ogg","https://resources.download.minecraft.net/9d/9d1ba828a27b2a6b5be6b97e4d6b554db885cb08","9d1ba828a27b2a6b5be6b97e4d6b554db885cb08"),
("audio/characters/我的世界/elytra_mace/elytra_loop.ogg","https://resources.download.minecraft.net/75/75c3df1293a7a559a780b47d2f9e630e7b0a46ff","75c3df1293a7a559a780b47d2f9e630e7b0a46ff")]
records=[]
for dest,url,expected in files:
 data=urllib.request.urlopen(url,timeout=45).read()
 sha1=hashlib.sha1(data).hexdigest()
 if expected and sha1!=expected: raise ValueError("SHA1 mismatch: "+dest)
 path=base/dest;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
 records.append(dict(path=dest,url=url,sha1=sha1,sha256=hashlib.sha256(data).hexdigest()))
 print("VANILLA_ASSET",dest,len(data))
(base/"Images/characters/我的世界/elytra_mace/SOURCES.json").write_text(json.dumps(dict(copyright="Mojang Studios / Microsoft. Minecraft assets; Minecraft EULA applies. Not original artwork.",texture_commit=commit,sound_version="Java 1.21.4 official asset index",processing="Textures unmodified; worn wings use mirrored AtlasTexture region (34,2,12,20).",files=records),ensure_ascii=False,indent=2),encoding="utf-8")
