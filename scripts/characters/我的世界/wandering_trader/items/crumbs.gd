extends Node2D
## Vanilla-style texture crumbs. Minecraft's block-break / block-hit particles (TerrainParticle)
## and item particles (ItemParticle: slime ball hits, eating) each draw a random quarter-by-quarter
## square of the source texture, fly out, fall and vanish; terrain ones are shaded to 60 %.
## Wall entry/exit use the real wall tile's atlas region (wall_source), so the crumbs are made of
## the wall the trader walks through.
const WALL = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
const STONE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_stone.png")
const GROUP:StringName = &"MCWanderingTraderFx"
var texture:Texture2D
var parts:Array[Dictionary] = []
var gravity:float = 170.0
var drag:float = 1.6
var shade:Color = Color.WHITE
var _age:float = 0.0
var _end:float = 0.6

## count crumbs from point, fanned around dir (spread = half angle). size in world px.
static func spawn(context:Node,point:Vector2,source:Dictionary,count:int = 14,dir:Vector2 = Vector2.UP,speed:float = 60.0,size:float = 2.2,lifetime:float = 0.6,spread:float = 1.2,terrain_shade:bool = true,scatter:float = 2.0) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tex:Texture2D = source.get("texture",null)
	if tex == null: return null
	var region:Rect2 = source.get("region",Rect2(Vector2.ZERO,tex.get_size()))
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var fx:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd") as Script).new()
	fx.name = "WTCrumbs"
	fx.texture = tex
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_as_relative = false
	fx.z_index = 40
	fx.shade = Color(0.6,0.6,0.6) if terrain_shade else Color.WHITE
	fx.add_to_group(GROUP)
	fx.add_to_group(&"BattleTransient")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base:Vector2 = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.UP
	var quarter:Vector2 = region.size/4.0
	for i:int in range(maxi(count,1)):
		var sub := Rect2(region.position + Vector2(floorf(rng.randf_range(0.0,3.0))*quarter.x + rng.randf_range(0.0,quarter.x*0.5),floorf(rng.randf_range(0.0,3.0))*quarter.y + rng.randf_range(0.0,quarter.y*0.5)),quarter)
		var life:float = lifetime*rng.randf_range(0.55,1.0)
		fx.parts.append({
			"pos": Vector2(rng.randf_range(-scatter,scatter),rng.randf_range(-scatter,scatter)),
			"vel": base.rotated(rng.randf_range(-spread,spread))*speed*rng.randf_range(0.35,1.0),
			"size": size*rng.randf_range(0.7,1.3),
			"life": life,
			"sub": sub,
		})
		fx._end = maxf(fx._end,life)
	parent.add_child(fx)
	fx.global_position = point
	return fx

## {texture, region} of the wall tile just behind a wall surface point (normal points out of the
## wall). Falls back to vanilla stone when no tile is found (e.g. maps whose border is the rect).
static func wall_source(context:Node,point:Vector2,normal:Vector2) -> Dictionary:
	if is_instance_valid(context) and context.is_inside_tree():
		var n:Vector2 = normal.normalized() if normal.length_squared() > 0.000001 else Vector2.UP
		var layers:Array[TileMapLayer] = WALL.map_layers(WALL.current_map(context.get_tree().current_scene))
		for depth:float in [3.0,8.0,16.0,26.0]:
			var probe:Vector2 = point - n*depth
			for layer:TileMapLayer in layers:
				if layer.tile_set == null: continue
				var cell:Vector2i = layer.local_to_map(layer.to_local(probe))
				var id:int = layer.get_cell_source_id(cell)
				if id < 0: continue
				var atlas:TileSetAtlasSource = layer.tile_set.get_source(id) as TileSetAtlasSource
				if atlas == null or atlas.texture == null: continue
				return {"texture": atlas.texture,"region": atlas.get_tile_texture_region(layer.get_cell_atlas_coords(cell))}
	return {"texture": STONE,"region": Rect2(0,0,16,16)}

static func texture_source(tex:Texture2D) -> Dictionary:
	return {"texture": tex,"region": Rect2(Vector2.ZERO,tex.get_size()) if tex != null else Rect2()}

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	_age += delta
	for p:Dictionary in parts:
		var v:Vector2 = p.vel
		v.y += gravity*delta
		v *= maxf(1.0 - drag*delta,0.0)
		p.vel = v
		p.pos = (p.pos as Vector2) + v*delta
	queue_redraw()
	if _age >= _end: queue_free()

func _draw() -> void:
	for p:Dictionary in parts:
		var life:float = p.life
		if _age >= life: continue
		var k:float = _age/life
		var s:float = float(p.size)*(1.0 - 0.35*k)
		var c:Color = shade
		c.a = 1.0 if k < 0.7 else 1.0 - (k - 0.7)/0.3
		draw_texture_rect_region(texture,Rect2((p.pos as Vector2) - Vector2(s,s)*0.5,Vector2(s,s)),p.sub,c)
