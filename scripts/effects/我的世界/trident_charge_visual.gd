extends Node2D
# One masked native enchantment overlay plus short, rerouting shaft arcs.
# Held alpha/paths follow the independent, smaller native rightItem layer.
const ARC_CLIP = preload("res://scripts/effects/我的世界/trident_arc_clip.gdshader")
const GLINT = preload("res://scripts/effects/我的世界/trident_glint.gdshader")
const NATIVE_GLINT = preload("res://Images/characters/我的世界/native_frames/trident_masks/enchanted_item_glint.png")
var spear:Node2D
var overlay:Sprite2D
var glint_material:ShaderMaterial
var arc_material:ShaderMaterial
var _path := PackedVector2Array()
var _arcs:Array[PackedVector2Array] = []
var _reroute_left:float = 0.0
var _tex_key:String = ""
var _world_scale:float = 1.0
var _rng := RandomNumberGenerator.new()
var reroutes:int = 0
func _ready() -> void:
	set_as_top_level(true)
	z_as_relative = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = hash(str(spear.unit.get_path())+":"+str(spear.serial))
	arc_material = ShaderMaterial.new()
	arc_material.shader = ARC_CLIP
	material = arc_material
	overlay = Sprite2D.new()
	overlay.name = "NativeEnchantment"
	glint_material = ShaderMaterial.new()
	glint_material.shader = GLINT
	glint_material.set_shader_parameter("native_glint",NATIVE_GLINT)
	overlay.material = glint_material
	add_child(overlay)
	visible = false
func _process(_delta:float) -> void:
	# The native bone frame advances during idle processing, after projectile physics.
	# Resync held masks in that same rendered frame without ticking effects twice.
	if not is_instance_valid(spear) or not is_instance_valid(spear.unit) or spear.flight_state!=0: return
	if Game.now_stop_state or get_tree().paused or not spear.unit.is_combat_runtime_active(): return
	advance(0.0)
func advance(delta:float) -> void:
	visible = is_instance_valid(spear) and is_instance_valid(spear.unit) and spear.unit.health>0 and spear.charged
	if not visible: return
	var held:bool = spear.flight_state==0
	var next_key:String
	if held:
		var driver:Node = spear.unit.mc_native_animation
		if not is_instance_valid(driver) or not driver.ready_visual:
			visible = false
			return
		var hand:Node2D = spear.unit.hand_visual
		if not is_instance_valid(hand):
			visible = false
			return
		hand.sync_pose()
		if not hand.visible or hand.is_ghost:
			visible = false
			return
		next_key = str(driver.current_clip)+":"+str(driver.frame_index)
		global_transform = hand.weapon.global_transform
		z_index = hand.z_index+1
		overlay.texture = hand.weapon.texture
		overlay.scale = Vector2.ONE
		_path = PackedVector2Array(hand.record.path)
	else:
		next_key = "free:"+str(spear.flight_state)+":"+str(spear.planted)
		global_transform = spear.global_transform
		z_index = spear.z_index+1
		overlay.texture = spear.TEXTURE
		overlay.scale = Vector2.ONE*spear.DRAW_SIZE/overlay.texture.get_width()
		# 插地时流光跟着戟身一起裁：埋在土里的戟叉不再透出土面。
		var clip_y:float = spear.plant_clip_y() if spear.plant_clip_enabled() else INF
		_path = PackedVector2Array()
		for i:int in range(14):
			var local:Vector2 = Vector2(-8,8).lerp(Vector2(7,-7),float(i)/13.0)*spear.DRAW_SIZE/24.0
			if spear.to_global(local).y>clip_y: continue
			_path.append(local)
	sync_plant_clip()
	_world_scale = maxf(global_transform.x.length(),0.01)
	glint_material.set_shader_parameter("world_texel",_world_scale*overlay.scale.x)
	glint_material.set_shader_parameter("glint_time",spear._clock)
	_reroute_left -= maxf(delta,0.0)
	if next_key!=_tex_key or _reroute_left<=0.0:
		_tex_key = next_key
		_reroute_left = _rng.randf_range(0.045,0.095)
		_rebuild_arcs()
	_clip_arcs_to_ground()
	queue_redraw()
func sync_plant_clip() -> void:
	if not is_instance_valid(spear): return
	var enabled:bool = spear.plant_clip_enabled()
	spear.configure_plant_clip(glint_material,enabled)
	spear.configure_plant_clip(arc_material,enabled)

func _clip_arcs_to_ground() -> void:
	if not is_instance_valid(spear) or not spear.plant_clip_enabled(): return
	# Clip AFTER jitter/fork construction, not just the unperturbed shaft path.
	# Leave half of the widest stroke above the surface too; shader clipping
	# supplies the final pixel-accurate guard for joins and renderer variants.
	var boundary:float = spear.plant_clip_y()-0.85
	var visible_arcs:Array[PackedVector2Array] = []
	for arc:PackedVector2Array in _arcs:
		if arc.size()<2: continue
		var part := PackedVector2Array()
		for i:int in range(arc.size()-1):
			var a:Vector2 = to_global(arc[i])
			var b:Vector2 = to_global(arc[i+1])
			var a_in:bool = a.y <= boundary
			var b_in:bool = b.y <= boundary
			if a_in and part.is_empty(): part.append(arc[i])
			if a_in and b_in:
				part.append(arc[i+1])
			elif a_in != b_in:
				var t:float = clampf((boundary-a.y)/(b.y-a.y),0.0,1.0)
				var edge:Vector2 = to_local(a.lerp(b,t))
				if a_in:
					part.append(edge)
					if part.size()>=2: visible_arcs.append(part)
					part = PackedVector2Array()
				else:
					part.append(edge)
					part.append(arc[i+1])
			elif not part.is_empty():
				if part.size()>=2: visible_arcs.append(part)
				part = PackedVector2Array()
		if part.size()>=2: visible_arcs.append(part)
	_arcs = visible_arcs

func _rebuild_arcs() -> void:
	_arcs.clear()
	if _path.size()<4: return
	reroutes += 1
	var start:int = _rng.randi_range(0,_path.size()/2)
	var end:int = mini(start+_rng.randi_range(4,9),_path.size()-1)
	var arc := PackedVector2Array()
	for i:int in range(start,end+1):
		arc.append(_path[i]+Vector2(_rng.randf_range(-1.3,1.3),_rng.randf_range(-0.7,0.7))/_world_scale)
	_arcs.append(arc)
	# A tiny irregular fork, never a circle orbiting the item.
	var joint:Vector2 = arc[_rng.randi_range(1,arc.size()-2)]
	var side:float = -1.0 if _rng.randf()<0.5 else 1.0
	_arcs.append(PackedVector2Array([joint,joint+Vector2(side*1.8,-1.0)/_world_scale,joint+Vector2(side*2.8,0.5)/_world_scale]))
func _draw() -> void:
	if not visible: return
	for arc:PackedVector2Array in _arcs:
		if arc.size()<2: continue
		draw_polyline(arc,Color(0.2,0.55,1.0,0.62),1.6/_world_scale,false)
		draw_polyline(arc,Color(0.82,0.96,1.0,0.95),0.6/_world_scale,false)
