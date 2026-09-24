extends Node2D
## Bounded native-texture effects. Ground tiles are visual only; gameplay lives on the authority.
const NATIVE = preload("res://scripts/characters/我的世界/minecart/native_particles.gd")
const MOSS_DEBRIS = preload("res://scripts/characters/我的世界/frontier/moss_debris.gd")
const BLOCK_FRAGMENTS = preload("res://scripts/effects/我的世界/block_fragments.gd")
const MOSS_GROUND_Z:int = -3
const MOSS:Texture2D = preload("res://Images/characters/我的世界/frontier/moss_tile.png")
const GRASS:Texture2D = preload("res://Images/characters/我的世界/frontier/grass.png")
const SCULK:Texture2D = preload("res://Images/characters/我的世界/frontier/sculk_top.png")
const BAR = preload("res://scripts/characters/我的世界/frontier/creeper_style_bar.gd")
const TABLE:Texture2D = preload("res://Images/characters/我的世界/frontier/table_block.png")
const VIBRATION:Texture2D = preload("res://Images/characters/我的世界/frontier/vibration.png")
const SONIC:Texture2D = preload("res://Images/characters/我的世界/frontier/sonic.png")
var actor:Node2D
var particles:Array[Dictionary] = []
var beams:Array[Dictionary] = []
var hearing_signals:Array[Dictionary] = []
var time:float = 0.0
var sword_trails:Array[Dictionary] = []
var trail_emission_left:float = 0.0
# 瞄准提示圈：每个圈独立生命周期，攻击出手/取消后不再生成新圈，已有的圈自然渐隐完再消失。
var aim_rings:Array[Dictionary] = []
var _aim_spawn_left:float = 0.0
var _rng := RandomNumberGenerator.new()
func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	global_scale = Vector2.ONE
	z_as_relative = false
	z_index = MOSS_GROUND_Z if is_instance_valid(actor) and actor.role_key() == "moss" else 7
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = get_instance_id()
func burst(kind:String,point:Vector2,end_point:Vector2) -> void:
	if kind in ["emerge","warden_burrow_debris"] and is_instance_valid(actor) and actor.role_key()=="warden":
		var debris:Node2D=preload("res://scripts/characters/我的世界/frontier/warden_ground_debris.gd").new()
		add_child(debris)
		debris.start(actor,point,kind=="emerge",actor.emerge_duration if kind=="emerge" else 1.8)
		return
	if kind in ["summon_screen","sonic_screen","sonic_charge_screen"]:
		preload("res://scripts/characters/我的世界/frontier/warden_screen.gd").ensure(actor).trigger(actor,kind)
		return
	if kind=="heard_noise":
		if not is_instance_valid(actor) or actor.role_key()!="warden" or actor.health<=0: return
		if hearing_signals.size()>=24: hearing_signals.pop_front()
		hearing_signals.append({"point":point,"heading":Vector2.ZERO,"age":0.0,"arrived":false,"fade":0.0})
		queue_redraw()
		return
	if kind == "moss_break" and is_instance_valid(actor):
		var debris:Node2D = BLOCK_FRAGMENTS.spawn_texture(actor,MOSS,point,actor.CELL/float(MOSS.get_width()),{"z_layer":4,"scatter_radius":actor.CELL*0.5,"arc_height_min":12.0,"arc_height_max":28.0})
		debris.add_to_group("MCMossBreakDebris")
		return
	if kind in ["moss_dig","moss_emerge","moss_place"] and is_instance_valid(actor):
		var debris:Node2D = MOSS_DEBRIS.new()
		add_child(debris)
		debris.setup(actor,point,kind != "moss_dig",actor.CELL,kind == "moss_place")
		return
	if kind == "sonic":
		if beams.size() >= 3: beams.pop_front()
		beams.append({"a":point,"b":end_point,"age":0.0})
	var number:int = 16 if kind in ["grow","warning","break","emerge"] else 9
	for i:int in range(number):
		if particles.size() >= 48: break
		var heading:Vector2 = Vector2.RIGHT.rotated(_rng.randf_range(0,TAU))
		particles.append({"point":point,"velocity":heading*_rng.randf_range(15,65),"age":0.0,"life":_rng.randf_range(0.25,0.65),"kind":"electric" if kind in ["warning","emerge","sonic"] else "crit","size":_rng.randf_range(3,6)})
	queue_redraw()
func _process(delta:float) -> void:
	if not is_instance_valid(actor): queue_free(); return
	if not actor.is_combat_runtime_active() or Game.now_stop_state or get_tree().paused: return
	update_hearing_signals(delta)
	time += delta
	if actor.role_key() == "warden": update_aim_rings(delta)
	if actor.role_key() == "wooden_sword": update_sword_trails(delta)
	for i:int in range(particles.size()-1,-1,-1):
		particles[i].age += delta
		particles[i].point += particles[i].velocity*delta
		particles[i].velocity *= maxf(0,1.0-4.0*delta)
		if particles[i].age >= particles[i].life: particles.remove_at(i)
	for i:int in range(beams.size()-1,-1,-1):
		beams[i].age += delta
		if beams[i].age >= 0.5: beams.remove_at(i)
	queue_redraw()
func update_hearing_signals(delta:float) -> void:
	if actor.health<=0:
		hearing_signals.clear()
		return
	for i:int in range(hearing_signals.size()-1,-1,-1):
		var signal_fx:Dictionary=hearing_signals[i]
		signal_fx.age+=delta
		if signal_fx.age>2.0:
			hearing_signals.remove_at(i)
			continue
		if signal_fx.arrived:
			signal_fx.point=actor.global_position
			signal_fx.fade+=delta
			if signal_fx.fade>=0.16: hearing_signals.remove_at(i)
			continue
		var point:Vector2=signal_fx.point
		signal_fx.heading=point.direction_to(actor.global_position)
		signal_fx.point=point.move_toward(actor.global_position,420.0*delta)
		if signal_fx.point.distance_to(actor.global_position)<=4.0:
			signal_fx.arrived=true
			signal_fx.point=actor.global_position
func draw_hearing_signals() -> void:
	var cell:int=VIBRATION.get_width()
	var frames:int=maxi(1,VIBRATION.get_height()/cell)
	for signal_fx:Dictionary in hearing_signals:
		# One animated native vibration sprite, no chain of rings or arrival flash.
		var frame:int=int(float(signal_fx.age)*16.0)%frames
		var region:=Rect2(0,frame*cell,cell,cell)
		var fade:float=1.0-clampf(float(signal_fx.fade)/0.16,0,1) if signal_fx.arrived else 1.0
		var point:Vector2=to_local(signal_fx.point)+Vector2(0,-6)
		var size:float=12.0*lerpf(0.7,1.0,fade)
		draw_set_transform(point,Vector2(signal_fx.heading).angle()+PI*0.5)
		draw_texture_rect_region(VIBRATION,Rect2(-Vector2.ONE*size*0.5,Vector2.ONE*size),region,Color(1,1,1,fade))
		draw_set_transform(Vector2.ZERO)
func _draw() -> void:
	if not is_instance_valid(actor) or actor.health <= 0: return
	draw_hearing_signals()
	var center:Vector2 = to_local(actor.global_position)
	match actor.role_key():
		"moss": _draw_moss(center)
		"wooden_sword": _draw_sword(center)
		"warden": _draw_warden(center)
	for particle:Dictionary in particles:
		var age:float = particle.age/particle.life
		NATIVE.draw(self,particle.kind,to_local(particle.point),particle.size,age,1.0-age)
	for beam:Dictionary in beams:
		var age:float = beam.age/0.5
		for i:int in range(1,13):
			var p:Vector2 = to_local(beam.a.lerp(beam.b,float(i)/12.0))
			var size:float = 12.0+age*20.0
			var frame_size:int = mini(SONIC.get_width(),SONIC.get_height())
			draw_texture_rect_region(SONIC,Rect2(p-Vector2.ONE*size*0.5,Vector2.ONE*size),Rect2(0,0,frame_size,frame_size),Color(1,1,1,1.0-age))
func _draw_moss(_center:Vector2) -> void:
	for patch:Dictionary in actor.patches:
		var p:Vector2 = to_local(patch.point)
		var size:float = actor.CELL-1.0
		for layer:int in range(int(patch.layers)):
			var offset:Vector2 = Vector2(0,-3.0*layer)
			draw_texture_rect(MOSS,Rect2(p+offset-Vector2.ONE*size*0.5,Vector2.ONE*size),false,Color(1,1,1,0.85))
			draw_line(p+offset+Vector2(-size*0.5,size*0.5),p+offset+Vector2(size*0.5,size*0.5),Color(0.25,0.42,0.12),1.0)
	# Ground-level ghosts are previews only: no collision, damage, particles or sound.
	if actor._growth_winding:
		for entry:Dictionary in actor._growth_pending:
			var p:Vector2 = to_local(entry.point)+Vector2(0,-3.0*int(entry.layer))
			var size:float = actor.CELL-1.0
			draw_texture_rect(MOSS,Rect2(p-Vector2.ONE*size*0.5,Vector2.ONE*size),false,Color(1,1,1,actor.placement_preview_alpha))
func _draw_sword(center:Vector2) -> void:
	if actor.part_kind != 0: return
	var ratio:float = clampf(float(actor.durability)/float(actor.MAX_DURABILITY),0,1)
	BAR.paint(self,Rect2(center+Vector2(-11,18.4),Vector2(22,3.2)),ratio,1.0-ratio)
func _draw_warden(center:Vector2) -> void:
	_draw_warden_aim()
	if actor.form==actor.Form.DORMANT:
		BAR.paint(self,Rect2(center+Vector2(-19,17),Vector2(38,3.2)),actor.alert_level/maxf(actor.alert_max,1.0),1.0-actor.alert_level/maxf(actor.alert_max,1.0),Color(0.08,0.45,1.0,1.0))
		for i:int in range(5):
			draw_texture_rect(SCULK,Rect2(center+Vector2(-19+i*8,23),Vector2(6,6)),false,Color(0.6,1,1,1.0 if i<actor.signals_received else 0.2))
	if actor.sonic_left>0.0:
		var frame:int = mini(SONIC.get_width(),SONIC.get_height())
		for i:int in range(1,12):
			var p:Vector2 = to_local(actor.sonic_origin.lerp(actor.sonic_end,float(i)/12.0))
			var size:float = 7.0+5.0*(1.0-actor.sonic_left/actor.sonic_windup)
			draw_texture_rect_region(SONIC,Rect2(p-Vector2.ONE*size*0.5,Vector2.ONE*size),Rect2(0,frame*8 if SONIC.get_height()>=frame*16 else 0,frame,frame),Color(0.7,1,1,0.2+0.5*(1.0-actor.sonic_left/actor.sonic_windup)))
# 瞄准提示：和重锤落地圈同一个 pixel_arc 像素圆环，从中心向外扩大并快速渐隐；
# 前摇期间每隔 AIM_RING_INTERVAL 发一圈，配色取自尖啸体声波贴图 sonic.png 的两个主色
#（青 44,227,235 / 深青 11,180,170）。只是提示，不参与判定。
const PIXEL_ARC = preload("res://scripts/effects/我的世界/pixel_arc.gd")
const AIM_CYAN:Color = Color(44.0/255.0,227.0/255.0,235.0/255.0)
const AIM_TEAL:Color = Color(11.0/255.0,180.0/255.0,170.0/255.0)
const AIM_RING_LIFE:float = 0.42
const AIM_RING_INTERVAL:float = 0.28
func update_aim_rings(delta:float) -> void:
	for i:int in range(aim_rings.size()-1,-1,-1):
		aim_rings[i].age += delta
		if aim_rings[i].age >= AIM_RING_LIFE: aim_rings.remove_at(i)
	if actor.aim_left>0.0 and actor.aim_total>0.0 and actor.health>0:
		_aim_spawn_left -= delta
		if _aim_spawn_left <= 0.0:
			_aim_spawn_left = AIM_RING_INTERVAL
			if aim_rings.size() >= 6: aim_rings.pop_front()
			aim_rings.append({"point":actor.aim_point,"age":0.0,"big":actor.aim_kind=="sonic"})
	else: _aim_spawn_left = 0.0
func _draw_warden_aim() -> void:
	for ring:Dictionary in aim_rings:
		var t:float = clampf(float(ring.age)/AIM_RING_LIFE,0.0,1.0)
		# 像重锤落地圈一样先快后慢地扩大，同时较快地渐隐
		var expand:float = 1.0-pow(1.0-t,2.6)
		var alpha:float = pow(1.0-t,1.6)
		if alpha <= 0.01: continue
		var p:Vector2 = to_local(ring.point).round()
		var radius:float = lerpf(6.0,42.0 if ring.big else 30.0,expand)
		PIXEL_ARC.draw(self,p,radius,0.0,TAU,64,Color(AIM_TEAL,0.55*alpha),3.0,false)
		PIXEL_ARC.draw(self,p,radius,0.0,TAU,64,Color(AIM_CYAN,0.95*alpha),1.0,false)

func update_sword_trails(delta:float) -> void:
	for i:int in range(sword_trails.size()-1,-1,-1):
		var record:Dictionary = sword_trails[i]
		record.age += delta
		if record.age >= 0.12 or actor.part_kind != 0 or actor.health <= 0:
			record.sprite.queue_free()
			sword_trails.remove_at(i)
		else: record.sprite.modulate.a = 0.45*(1.0-record.age/0.12)
	trail_emission_left = maxf(0,trail_emission_left-delta)
	if actor.part_kind != 0 or actor.health <= 0 or actor.swing_visual_left <= 0 or actor._swing_charge < actor.trail_charge_threshold or trail_emission_left > 0: return
	trail_emission_left = 0.025
	if sword_trails.size() >= 4:
		sword_trails[0].sprite.queue_free()
		sword_trails.pop_front()
	var source:Sprite2D = actor.image
	var ghost := Sprite2D.new()
	ghost.texture = source.texture
	ghost.centered = source.centered
	ghost.offset = source.offset
	ghost.flip_h = source.flip_h
	ghost.flip_v = source.flip_v
	ghost.hframes = source.hframes
	ghost.vframes = source.vframes
	ghost.frame = source.frame
	ghost.region_enabled = source.region_enabled
	ghost.region_rect = source.region_rect
	# Clone the actual sprite shader too: its UV mirroring/presentation must
	# match the body, not a separately reconstructed raw-texture rectangle.
	if source.material != null: ghost.material = source.material.duplicate()
	ghost.texture_filter = source.texture_filter
	ghost.z_as_relative = false
	ghost.z_index = source.z_index-1
	add_child(ghost)
	ghost.global_transform = source.global_transform
	ghost.modulate = Color(1,1,1,0.45)
	sword_trails.append({"sprite":ghost,"age":0.0})
