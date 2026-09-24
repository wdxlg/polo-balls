extends RefCounted
## Match visible pixels, not transparent texture padding. Both weapons inherit
## the same root scale as the reference wooden-sword scene.
const REFERENCE_TEXTURE:Texture2D = preload("res://Images/characters/我的世界/frontier/wood_sword.png")
const REFERENCE_SPRITE_SCALE:float = 7.5
static var _visible_edges:Dictionary = {}

static func visible_long_edge(texture:Texture2D) -> float:
	if texture == null: return 0.0
	var key:int = texture.get_instance_id()
	if not _visible_edges.has(key):
		var pixels:Image = texture.get_image()
		var size:Vector2 = Vector2(pixels.get_used_rect().size) if pixels != null else texture.get_size()
		_visible_edges[key] = maxf(size.x,size.y)
	return float(_visible_edges[key])

static func fit_to_wooden_sword(sprite:Sprite2D,ratio:float = 1.0) -> void:
	if not is_instance_valid(sprite): return
	var own_edge:float = visible_long_edge(sprite.texture)
	var reference_edge:float = visible_long_edge(REFERENCE_TEXTURE)*REFERENCE_SPRITE_SCALE
	if own_edge<=0.0 or reference_edge<=0.0: return
	sprite.scale = Vector2.ONE*(reference_edge/own_edge)*clampf(ratio,0.01,2.0)
