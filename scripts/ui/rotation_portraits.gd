extends RefCounted
## Vanilla mob front-face UVs; item / non-Minecraft art comes from its actual scene.
const ROOT:String = "res://Images/UI/rotation_frames/"
const HEADS:Dictionary = {
	"苦力怕":"creeper", "骷髅":"skeleton", "末影人":"enderman",
	"唤魔者":"evoker", "女巫":"witch", "烈焰人":"blaze",
	"蜘蛛":"spider", "溺尸":"drowned", "潜影贝":"shulker",
	"蠹虫":"silverfish", "铁傀儡":"iron_golem", "铁匠村民":"villager",
	"悦灵":"allay", "监守者":"warden", "羊":"sheep", "蝙蝠":"bat",
	"恶魂":"ghast", "守卫者":"guardian", "史莱姆":"slime",
	"雪傀儡":"snow_golem", "雾中人":"fog_man"
}
var cache:Dictionary = {}

func resolve(world:Node,record:Dictionary) -> Texture2D:
	var character:String = str(record.get("char",""))
	var path:String = str(record.get("scene_path",""))
	if path.is_empty(): path = world.character_scene_path(character)
	var key:String = path+":"+character
	if cache.has(key): return cache[key]
	if path.contains("/我的世界/") and HEADS.has(character):
		var texture_path:String = ROOT+str(HEADS[character])+".png"
		if ResourceLoader.exists(texture_path):
			cache[key] = load(texture_path)
			return cache[key]
	var preview:Node2D = world.create_character_preview(character,path,false)
	if preview == null: return null
	var visual:Node = preview.get_node_or_null("PreviewImage")
	var source:Texture2D = null
	if visual is Sprite2D:
		source = visual.texture
		if source != null and (visual.region_enabled or visual.hframes > 1 or visual.vframes > 1):
			var atlas := AtlasTexture.new()
			atlas.atlas = source
			if visual.region_enabled: atlas.region = visual.region_rect
			else:
				var frame_size:Vector2 = source.get_size()/Vector2(visual.hframes,visual.vframes)
				atlas.region = Rect2(Vector2(visual.frame_coords)*frame_size,frame_size)
			source = atlas
	elif visual is AnimatedSprite2D and visual.sprite_frames != null:
		if visual.sprite_frames.has_animation(visual.animation) and visual.sprite_frames.get_frame_count(visual.animation)>0:
			source = visual.sprite_frames.get_frame_texture(visual.animation,0)
	if source != null:
		var image:Image = source.get_image()
		if image != null and not image.is_empty():
			if image.is_compressed(): image.decompress()
			var used:Rect2i = image.get_used_rect()
			if used.has_area(): source = ImageTexture.create_from_image(image.get_region(used))
	preview.free()
	if source != null: cache[key] = source
	return source
