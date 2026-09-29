extends "res://scripts/characters/我的世界/new5/base.gd"
const PARTS={"piston_rod":preload("res://Images/characters/我的世界/new5/piston_shaft_model.png"),"piston_head":preload("res://Images/characters/我的世界/new5/piston_head_model.png"),"end_rod_assembled":preload("res://Images/characters/我的世界/new5/end_rod_model.png")}
const CASE=preload("res://Images/characters/我的世界/new5/piston_case.png")
const PROJECTED_PIXELS:float=5.102372
const CASE_SCALE:float=0.16
const REST_EXTENSION:float=4.898277
var _sound_retract:bool=false
const HOLD=preload("res://scripts/characters/我的世界/new5/sticky_hold.gd")
const SLIME_FX=preload("res://scripts/characters/我的世界/new5/piston_slime_fx.gd")
const PUSH=preload("res://scripts/characters/我的世界/new5/piston_push.gd")
@export var max_extension:float=34.4
@export var candle_length:float=22.4
@export var stick_duration:float=0.65
@export var thrust_damage:float=18.0
@export var base_frequency:float=1.25
@export_range(0.03,0.25,0.01) var turn_duration:float=0.08
@export_range(0.0,45.0,1.0) var turn_skip_degrees:float=3.0
var _turn_target:Vector2=Vector2.RIGHT
var _turn_start_angle:float=0.0
var _turn_elapsed:float=0.08
var _turn_active:bool=false
var _received_facing:bool=false
var facing:Vector2=Vector2.RIGHT
var charge:float=0.0
var extending:bool=false
var _manual_extend_held:bool=false
var phase:float=0.0
var extension:float=REST_EXTENSION
var _hit_ids:Dictionary={}
var _hold_ids:Dictionary={}
var weapon:Node2D
var head:Sprite2D
var rod:Sprite2D
var shaft:Sprite2D
func _ready() -> void:
	super._ready()
	if direction.length_squared()>0.001: facing=direction.normalized()
	_turn_target=facing
	weapon=Node2D.new()
	weapon.name="PistonAssembly"
	weapon.top_level=true
	weapon.z_index=5
	add_child(weapon)
	shaft=_part("piston_rod",Vector2(2,0.45))
	head=_part("piston_head",Vector2(0.32,1.3))
	rod=_part("end_rod_assembled",Vector2(1.0,1.0))
	visual_mob()
func _part(asset:String,size:Vector2) -> Sprite2D:
	var sprite:=Sprite2D.new()
	sprite.texture=PARTS[asset]
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale=size
	weapon.add_child(sprite)
	return sprite
func sticky_anchor(victim:ball) -> Vector2:
	return global_position+facing*(extension+U.radius(victim)+4.0)
func controlled_attack_action() -> void:
	if is_player_controlled() and is_multiplayer_authority(): _manual_extend_held=true
func player_control_action_released(index:int) -> void:
	if index==0: _manual_extend_held=false
func player_control_action_cancelled(index:int) -> void:
	if index==0: _manual_extend_held=false
func set_player_control_peer(peer_id:int) -> void:
	if peer_id != player_control_peer_id: _manual_extend_held=false
	super.set_player_control_peer(peer_id)
func step_mob(delta:float) -> void:
	var desired:Vector2=direction
	if is_player_controlled() and has_player_control_aim(): desired=player_control_aim_direction(facing)
	request_turn(desired)
	advance_turn(delta)
	extending=false
	if can_act() and (not is_player_controlled() or _manual_extend_held):
		for other:Node in get_tree().get_nodes_in_group("Ball"):
			if not U.enemy(self,other): continue
			var p:float=(ball.body_point(other,global_position)-global_position).dot(facing)
			if p<5.6 or p>max_extension+candle_length+U.radius(other): continue
			if U.segment_distance(ball.body_point_seg(other,global_position+facing*REST_EXTENSION,global_position+facing*(max_extension+candle_length)),global_position+facing*REST_EXTENSION,global_position+facing*(max_extension+candle_length))>U.radius(other)+3.2: continue
			if U.line_clear(self,global_position,ball.body_point(other,global_position)): extending=true; break
	charge=clampf(charge+delta if extending else charge-delta*7.0,0,6)
	if not extending:
		if extension>REST_EXTENSION+0.4 and not _sound_retract:
			play_sound("block.piston.contract",-5.0)
			_sound_retract=true
		extension=move_toward(extension,REST_EXTENSION,delta*88.0)
		phase=0
		_hit_ids.clear()
		_hold_ids.clear()
		return
	_sound_retract=false
	if phase==0: play_sound("block.piston.extend",-5.0)
	var previous:float=extension
	var next_phase:float=phase+delta*base_frequency*(1+charge*0.4)
	if phase<0.5 and next_phase>=0.5: play_sound("block.piston.contract",-5.0)
	if next_phase>=1:
		play_sound("block.piston.extend",-5.0)
		_hit_ids.clear()
		_hold_ids.clear()
	phase=fmod(next_phase,1.0)
	extension=lerpf(REST_EXTENSION,max_extension,(1-cos(phase*TAU))*0.5)
	if extension<=previous: return
	var head_point:Vector2=global_position+facing*extension
	for other:Node in get_tree().get_nodes_in_group("Ball"):
		if not U.enemy(self,other) or not U.line_clear(self,global_position,ball.body_point(other,global_position)): continue
		var id:int=other.get_instance_id()
		if not _hold_ids.has(id) and not other.has_meta("mc_sticky_hold") and U.segment_distance(ball.body_point_seg(other,global_position+facing*previous,head_point),global_position+facing*previous,head_point)<U.radius(other)+3.2:
			_hold_ids[id]=true
			if other.can_receive_negative_effects() and other.can_receive_control_from(self):
				# A captured victim follows the head, not an older displacement controller.
				# Preserve unrelated true-stun effects (stage 1) and their own lock counts.
				for effect:Node in other.get_children():
					if effect.has_method("replace_with_hit") and int(effect.get("_stage"))==0: effect.call("_finish",false)
				var hold:Node=HOLD.new()
				hold.target=other
				hold.source=self
				hold.duration=stick_duration
				other.add_child(hold)
				play_sound("block.slime_block.place",-7.0)
		if _hit_ids.has(id): continue
		if U.segment_distance(ball.body_point_seg(other,global_position+facing*(previous+4.0),head_point+facing*candle_length),global_position+facing*(previous+4.0),head_point+facing*candle_length)>U.radius(other)+2.4: continue
		_hit_ids[id]=true
		var dealt:bool=U.damage(self,other,attack_damage(thrust_damage/maxf(float(default_properties.get("Damage",Damage)),0.01)),global_position)
		# Generic feedback belongs to the settled victim, not the nominal thrust.
		if dealt and other.has_meta("mc_sticky_hold"):
			play_sound("block.slime_block.step",-7.0)
			var fx_seed:int=rng.randi()
			if multiplayer.has_multiplayer_peer(): _sticky_attack_fx.rpc(head_point+facing*2.0,facing,fx_seed)
			_sticky_attack_fx(head_point+facing*2.0,facing,fx_seed)
		if dealt and other.can_receive_negative_effects() and other.can_receive_control_from(self):
			# A sticky target still takes each forward stroke. Do not replace
			# its active hold with a competing push controller.
			if other.has_meta("mc_sticky_hold"): continue
			# Avoid two controllers writing Repel. Release only active displacement effects.
			for effect:Node in other.get_children():
				if effect.has_method("replace_with_hit") and int(effect.get("_stage"))==0: effect.call("_finish",false)
			var push:Node=PUSH.new()
			push.target=other
			push.source=self
			push.direction=facing
			push.distance=75.0
			push.speed=340.0
			other.add_child(push)
func move(speed_value:float,delta:float) -> void:
	var movement_ratio:float=1.0/(1.0+charge*0.45)
	if extending: movement_ratio*=0.55
	super.move(speed_value*movement_ratio,delta)
func visual_mob() -> void:
	image.texture=CASE
	set_character_visual_flip_h(false)
	image.rotation=facing.angle()
	if not is_instance_valid(weapon): return
	weapon.global_position=global_position
	weapon.global_rotation=facing.angle()
	var world_per_unit:float=PROJECTED_PIXELS*CASE_SCALE
	head.position=Vector2(extension,0)
	head.scale=Vector2.ONE*CASE_SCALE
	var case_front:float=4.0*world_per_unit
	var head_back:float=extension-2.0*world_per_unit
	shaft.position=Vector2((case_front+head_back)*0.5,0)
	shaft.scale=Vector2(maxf(head_back-case_front,0.01)/(16*PROJECTED_PIXELS),CASE_SCALE)
	shaft.visible=head_back>case_front+0.1
	rod.scale=Vector2.ONE*(candle_length/(15*PROJECTED_PIXELS))
	rod.position=Vector2(extension+2.0*world_per_unit+candle_length*8.0/15.0,0)

func visual_state() -> Dictionary: return {"time":clock,"facing":facing,"extension":extension,"charge":charge,"attacking":extending}
func accept_visual(data:Dictionary) -> void:
	super.accept_visual(data)
	var incoming:Vector2=data.get("facing",facing)
	if not _received_facing:
		facing=incoming.normalized() if incoming.length_squared()>0.001 else facing
		_turn_target=facing
		_received_facing=true
	else: request_turn(incoming)
	extension=data.get("extension",12.0)
	charge=data.get("charge",0.0)
	extending=data.get("attacking",false)

@rpc("authority","call_remote","reliable")
func _sticky_attack_fx(point:Vector2,heading:Vector2,random_seed:int) -> void:
	if health<=0 or _death_visual_done: return
	SLIME_FX.spawn(self,point,heading,random_seed)

func request_turn(heading:Vector2) -> void:
	if heading.length_squared()<0.001: return
	var desired:Vector2=heading.normalized()
	if desired.is_equal_approx(_turn_target): return
	_turn_target=desired
	_turn_start_angle=facing.angle()
	_turn_elapsed=0.0
	var difference:float=absf(wrapf(desired.angle()-_turn_start_angle,-PI,PI))
	_turn_active=difference>deg_to_rad(turn_skip_degrees)
	if not _turn_active: facing=desired
func advance_turn(delta:float) -> void:
	if not _turn_active or health<=0 or not is_combat_runtime_active(): return
	var duration:float=maxf(turn_duration,0.03)
	_turn_elapsed=minf(_turn_elapsed+maxf(delta,0.0),duration)
	var t:float=clampf(_turn_elapsed/duration,0.0,1.0)
	facing=Vector2.RIGHT.rotated(lerp_angle(_turn_start_angle,_turn_target.angle(),smoothstep(0.0,1.0,t)))
	if t>=1.0:
		facing=_turn_target
		_turn_active=false
func client_visual_step(delta:float) -> void:
	advance_turn(delta)
