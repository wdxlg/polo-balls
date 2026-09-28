extends Node2D
## "像素拼身" copy-spawn effect (user choice 2026-09-28, task 9). The copied character's
## own current frame is cut into pixel cells (grayscale, same luminance as the copy's
## `character_grayscale` shader), which fly in from all around and assemble into the
## half-size copy exactly where it will appear. When the copy appears, scatter(true)
## flashes the cells white and bursts them outward as fading shards.
## One node draws every cell. Visual only, per peer; pauses with the battle.
## Shared/public: begin(unit, point, factor, rng_seed, converge) / scatter(flash) / sample().
const MAX_CELLS:int = 360
# Smallest cell ON SCREEN (ball roots are scale 0.2 and the camera zooms in, so a
# world-space minimum would merge a pixel-art mob into a handful of blocks).
const MIN_CELL_SCREEN:float = 2.2
const ALPHA_CUT:float = 0.5
const SCATTER_TIME:float = 0.7
const FLASH_TIME:float = 0.12
const SAFETY_HOLD:float = 1.5
const CACHE_LIMIT:int = 48
# While flying, cells are drawn larger and brighter (visible on dark grass) and settle
# to their exact size and gray as they land.
const FLY_GROW:float = 1.6
const FLY_WHITEN:float = 0.6
enum Stage {ASSEMBLE, SCATTER}
static var _grid_cache:Dictionary = {}

## [{target, start, delay, color, velocity, pos, alpha}]
var cells:Array[Dictionary] = []
var cell_size:float = 4.0
var center:Vector2 = Vector2.ZERO
var stage:int = Stage.ASSEMBLE
var converge_time:float = 0.5
var flashed:bool = false
var _age:float = 0.0
var _scatter_age:float = 0.0
var _extent:float = 10.0

## The character's visible sprite: the shared `image` node, else the first sprite
## (with a texture) under Graphics.
static func image_node(unit:Node) -> Node2D:
	if not is_instance_valid(unit): return null
	var img:Variant = unit.get("image")
	if is_instance_valid(img) and (img is Sprite2D or img is AnimatedSprite2D) and (img as CanvasItem).visible: return img
	var graphics:Node = unit.get_node_or_null("Graphics")
	return _first_sprite(graphics if graphics != null else unit)

static func _first_sprite(node:Node) -> Node2D:
	if node == null: return null
	for child:Node in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible: continue
		if child is Sprite2D and (child as Sprite2D).texture != null: return child
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).sprite_frames != null: return child
		var deep:Node2D = _first_sprite(child)
		if deep != null: return deep
	return null

## Cells of `unit`'s current frame as offsets from unit.global_position, already
## multiplied by `factor` (0.5 = the half-size copy): {cells:[{p,c}], size}.
## {} when the frame cannot be read (e.g. no CPU-side image on a dummy renderer).
static func sample(unit:Node2D,factor:float) -> Dictionary:
	var sprite:Node2D = image_node(unit)
	if sprite == null: return {}
	var tex:Texture2D = null
	var rect:Rect2i
	var centered:bool = true
	var offset:Vector2 = Vector2.ZERO
	var flip_h:bool = false
	var flip_v:bool = false
	if sprite is Sprite2D:
		var s:Sprite2D = sprite as Sprite2D
		tex = s.texture
		if tex == null: return {}
		var full:Vector2i = Vector2i(tex.get_width(),tex.get_height())
		if s.region_enabled: rect = Rect2i(s.region_rect)
		elif s.hframes*s.vframes>1:
			var fs:Vector2i = Vector2i(full.x/maxi(s.hframes,1),full.y/maxi(s.vframes,1))
			rect = Rect2i(Vector2i(s.frame%maxi(s.hframes,1),s.frame/maxi(s.hframes,1))*fs,fs)
		else: rect = Rect2i(Vector2i.ZERO,full)
		centered = s.centered
		offset = s.offset
		flip_h = s.flip_h
		flip_v = s.flip_v
	else:
		var a:AnimatedSprite2D = sprite as AnimatedSprite2D
		if a.sprite_frames == null or not a.sprite_frames.has_animation(a.animation): return {}
		tex = a.sprite_frames.get_frame_texture(a.animation,a.frame)
		if tex == null: return {}
		rect = Rect2i(0,0,tex.get_width(),tex.get_height())
		centered = a.centered
		offset = a.offset
		flip_h = a.flip_h
		flip_v = a.flip_v
	if rect.size.x<=0 or rect.size.y<=0: return {}
	var xform:Transform2D = sprite.global_transform
	var sc:Vector2 = xform.get_scale().abs()
	var texel:float = maxf(maxf(sc.x,sc.y),0.0001)*maxf(factor,0.01)
	var zoom:float = 1.0
	if unit.is_inside_tree(): zoom = clampf(absf(unit.get_viewport().get_canvas_transform().get_scale().x),0.05,20.0)
	var step:int = maxi(ceili(MIN_CELL_SCREEN/zoom/texel),1)
	var grid:Array = _grid(tex,rect,step)
	while grid.size()>MAX_CELLS:
		step += maxi(step/4,1)
		grid = _grid(tex,rect,step)
	if grid.is_empty(): return {}
	var origin:Vector2 = offset-Vector2(rect.size)*0.5 if centered else offset
	var out:Array[Dictionary] = []
	for row:Array in grid:
		var texel_pos:Vector2 = row[0]
		if flip_h: texel_pos.x = float(rect.size.x)-texel_pos.x
		if flip_v: texel_pos.y = float(rect.size.y)-texel_pos.y
		var world:Vector2 = xform*(origin+texel_pos)
		out.append({"p":(world-unit.global_position)*factor,"c":row[1]})
	return {"cells":out,"size":float(step)*texel}

## [[texel centre in the rect, gray Color], ...] for opaque cells; cached per frame.
static func _grid(tex:Texture2D,rect:Rect2i,step:int) -> Array:
	var key:String = "%d|%s|%d" % [tex.get_instance_id(),str(rect),step]
	if _grid_cache.has(key): return _grid_cache[key]
	var result:Array = []
	var image:Image = tex.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed(): image.decompress()
		if not image.is_compressed():
			var clip:Rect2i = rect.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
			if clip.size.x>0 and clip.size.y>0:
				var region:Image = image.get_region(clip)
				region.convert(Image.FORMAT_RGBA8)
				var cols:int = ceili(float(clip.size.x)/float(step))
				var rows:int = ceili(float(clip.size.y)/float(step))
				for cy:int in range(rows):
					for cx:int in range(cols):
						var px:int = mini(cx*step+step/2,clip.size.x-1)
						var py:int = mini(cy*step+step/2,clip.size.y-1)
						var col:Color = region.get_pixel(px,py)
						if col.a<ALPHA_CUT: continue
						var lum:float = col.r*0.299+col.g*0.587+col.b*0.114
						var pos:Vector2 = Vector2(clip.position-rect.position)+Vector2((float(cx)+0.5)*step,(float(cy)+0.5)*step)
						result.append([pos,Color(lum,lum,lum,1.0)])
	if _grid_cache.size()>=CACHE_LIMIT: _grid_cache.clear()
	_grid_cache[key] = result
	return result

## Starts assembling `unit`'s current frame (scaled by `factor`) at `point`.
## Returns false (caller frees this node / uses a fallback) if nothing could be read.
func begin(unit:Node2D,point:Vector2,factor:float,rng_seed:int,converge:float = 0.5) -> bool:
	var data:Dictionary = sample(unit,factor)
	if data.is_empty() or (data.cells as Array).is_empty(): return false
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 3
	cell_size = float(data.size)
	center = point
	converge_time = maxf(converge,0.1)
	var rng:RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	var extent:float = 0.0
	for row:Dictionary in data.cells: extent = maxf(extent,(row.p as Vector2).length())
	# Everything scales with the figure (ball roots are scale 0.2, so fixed world
	# distances would be several figure heights): fly in from 1.6-3.2 figure radii,
	# burst like the preview (sideways ~3.5x, random ~0.6 radius/s, gravity ~1.15).
	_extent = maxf(extent,2.0)
	var delay_max:float = converge_time*0.4
	for row:Dictionary in data.cells:
		var rel:Vector2 = row.p
		var target:Vector2 = point+rel
		var start:Vector2 = target+Vector2.RIGHT.rotated(rng.randf()*TAU)*_extent*rng.randf_range(1.6,3.2)
		var velocity:Vector2 = Vector2(rel.x*5.0,rel.y*2.0)+Vector2(rng.randf_range(-1.3,1.3),rng.randf_range(-2.2,-0.2))*_extent
		cells.append({"target":target,"start":start,"delay":rng.randf_range(0.0,delay_max),"color":row.c,"velocity":velocity,"pos":start,"alpha":0.0,"k":0.0})
	add_to_group(&"BattleTransient")
	add_to_group(&"MCHaochenAssembleParticle")
	queue_redraw()
	return true

## The copy has appeared (flash=true: white flash on the assembled shape) or the cast
## ended without a copy (flash=false): shards burst outward from where they are and fade.
func scatter(flash:bool) -> void:
	if stage==Stage.SCATTER: return
	stage = Stage.SCATTER
	flashed = flash
	_scatter_age = 0.0
	for c:Dictionary in cells: c.target = c.pos
	queue_redraw()

func is_assembled() -> bool:
	return stage==Stage.ASSEMBLE and _age>=converge_time

func _process(delta:float) -> void:
	if Game.now_stop_state or get_tree().paused: return
	if stage==Stage.ASSEMBLE:
		_age += delta
		for c:Dictionary in cells:
			var span:float = maxf(converge_time-float(c.delay)*0.6,0.05)
			var k:float = clampf((_age-float(c.delay))/span,0.0,1.0)
			k = 1.0-pow(1.0-k,3.0)
			c.pos = (c.start as Vector2).lerp(c.target,k)
			c.alpha = minf(k*2.5,1.0)
			c.k = k
		if _age>converge_time+SAFETY_HOLD: scatter(false)
	else:
		_scatter_age += delta
		if _scatter_age>=SCATTER_TIME:
			queue_free()
			return
	queue_redraw()

## Current on-screen cell positions (for tests / diagnostics).
func cell_positions() -> Array[Vector2]:
	var out:Array[Vector2] = []
	for c:Dictionary in cells: out.append(_draw_pos(c))
	return out

func _draw_pos(c:Dictionary) -> Vector2:
	if stage==Stage.ASSEMBLE: return c.pos
	var u:float = _scatter_age
	return (c.target as Vector2)+(c.velocity as Vector2)*u+Vector2(0.0,1.15*_extent)*u*u

func _draw() -> void:
	if stage==Stage.ASSEMBLE:
		for c:Dictionary in cells:
			if float(c.alpha)<=0.0: continue
			var fly:float = 1.0-float(c.k)
			var box:Vector2 = Vector2.ONE*cell_size*(1.0+FLY_GROW*fly)
			var col:Color = (c.color as Color).lerp(Color.WHITE,FLY_WHITEN*fly)
			col.a = float(c.alpha)
			draw_rect(Rect2((c.pos as Vector2)-box*0.5,box),col)
		return
	var u:float = _scatter_age
	var size:float = cell_size*(1.25+0.35*u/SCATTER_TIME)
	var alpha:float = 0.9*(1.0-u/SCATTER_TIME)
	var white:float = 1.0-clampf(u/FLASH_TIME,0.0,1.0) if flashed else 0.0
	var box2:Vector2 = Vector2.ONE*size
	for c:Dictionary in cells:
		var col:Color = (c.color as Color).lerp(Color.WHITE,maxf(white,0.35))
		col.a = maxf(alpha,white)
		draw_rect(Rect2(_draw_pos(c)-box2*0.5,box2),col)
