extends Node2D
## Vanilla-style texture crumbs. Minecraft's block-break / block-hit particles (TerrainParticle)
## and item particles (ItemParticle: slime ball hits, eating) each draw a random quarter-by-quarter
## square of the source texture, fly out, fall and vanish; terrain ones are shaded to 60 %.
## Wall entry/exit use the real wall tile's atlas region (wall_source), so the crumbs are made of
## the wall the trader walks through, streamed while his body crosses the wall surface.
## Each crumb keeps its own age, falls under gravity with light drag and fades out smoothly.
const WALL = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
const STONE:Texture2D = preload("res://Images/characters/我的世界/流浪商人/items/block_stone.png")
const GROUP:StringName = &"MCWanderingTraderFx"
var texture:Texture2D
var parts:Array[Dictionary] = []
var gravity:float = 380.0 # px/s^2: every crumb visibly falls (user rule 2026-09-29)
var drag:float = 0.9
var shade:Color = Color.WHITE
var region:Rect2
var persistent:bool = false # stream emitter: stays until released and its crumbs are gone
var emitted:int = 0
var _rng := RandomNumberGenerator.new()

static func _make(context:Node,source:Dictionary,terrain_shade:bool) -> Node2D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var tex:Texture2D = source.get("texture",null)
	if tex == null: return null
	var tree:SceneTree = context.get_tree()
	var parent:Node = tree.current_scene if tree.current_scene != null else tree.root
	var fx:Node2D = (load("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd") as Script).new()
	fx.name = "WTCrumbs"
	fx.texture = tex
	fx.region = source.get("region",Rect2(Vector2.ZERO,tex.get_size()))
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.z_as_relative = false
	fx.z_index = 40
	fx.shade = Color(0.6,0.6,0.6) if terrain_shade else Color.WHITE
	fx._rng.randomize()
	fx.add_to_group(GROUP)
	fx.add_to_group(&"BattleTransient")
	parent.add_child(fx)
	return fx

## count crumbs from point, fanned around dir (spread = half angle). size in world px.
static func spawn(context:Node,point:Vector2,source:Dictionary,count:int = 14,dir:Vector2 = Vector2.UP,speed:float = 60.0,size:float = 2.2,lifetime:float = 0.6,spread:float = 1.2,terrain_shade:bool = true,scatter:float = 2.0) -> Node2D:
	var fx:Node2D = _make(context,source,terrain_shade)
	if fx == null: return null
	fx.global_position = point
	for i:int in range(maxi(count,1)):
		var jitter := Vector2(fx._rng.randf_range(-scatter,scatter),fx._rng.randf_range(-scatter,scatter))
		fx.add(point + jitter,dir,speed,size,lifetime,spread)
	return fx

## A long-lived emitter at the world origin: call add() every frame, release() when done.
static func stream(context:Node,source:Dictionary,terrain_shade:bool = false) -> Node2D:
	var fx:Node2D = _make(context,source,terrain_shade)
	if fx == null: return null
	fx.persistent = true
	fx.global_position = Vector2.ZERO
	return fx

## One crumb at a world point: speed up to `speed` fanned ±spread around dir.
func add(world_point:Vector2,dir:Vector2,speed:float,size:float,lifetime:float,spread:float,extra_velocity:Vector2 = Vector2.ZERO) -> void:
	var base:Vector2 = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.UP
	var quarter:Vector2 = region.size/4.0
	var sub := Rect2(region.position + Vector2(floorf(_rng.randf_range(0.0,3.0))*quarter.x + _rng.randf_range(0.0,quarter.x*0.5),floorf(_rng.randf_range(0.0,3.0))*quarter.y + _rng.randf_range(0.0,quarter.y*0.5)),quarter)
	parts.append({
		"pos": to_local(world_point),
		"vel": base.rotated(_rng.randf_range(-spread,spread))*speed*_rng.randf_range(0.35,1.0) + extra_velocity,
		"size": size*_rng.randf_range(0.7,1.3),
		"life": lifetime*_rng.randf_range(0.6,1.0),
		"age": 0.0,
		"sub": sub,
	})
	emitted += 1

func release() -> void:
	persistent = false

func alive_count() -> int: return parts.size()

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
	var keep:Array[Dictionary] = []
	for p:Dictionary in parts:
		p.age = float(p.age) + delta
		if float(p.age) >= float(p.life): continue
		var v:Vector2 = p.vel
		v.y += gravity*delta
		v *= maxf(1.0 - drag*delta,0.0)
		p.vel = v
		p.pos = (p.pos as Vector2) + v*delta
		keep.append(p)
	parts = keep
	queue_redraw()
	if parts.is_empty() and not persistent: queue_free()

func _draw() -> void:
	for p:Dictionary in parts:
		var k:float = float(p.age)/maxf(float(p.life),0.001)
		var s:float = float(p.size)*(1.0 - 0.2*k)
		var c:Color = shade
		c.a = 1.0 - smoothstep(0.6,1.0,k)
		draw_texture_rect_region(texture,Rect2((p.pos as Vector2) - Vector2(s,s)*0.5,Vector2(s,s)),p.sub,c)
