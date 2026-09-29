extends RefCounted
const PROJECTILE_API = preload("res://classes/projectile_interactions.gd")
## Native projectile snapshots. Only called after capture.gd has approved an adapter.
## No original owner/node callbacks are retained: a frozen, non-combat context provides
## the original script's hit/status methods without its AI, movement, attacks or skills.
const EXT = preload("res://scripts/characters/我的世界/allay/extended_capture.gd")
const AUDIO = preload("res://scripts/characters/我的世界/allay/return_audio.gd")
static var context_scripts:Dictionary = {}
const SKIP = ["script","health","block","Max_health","Master_name","Team","name","owner","position","global_position","transform","global_transform","rotation","global_rotation","scale","global_scale","process_mode","visible","velocity","Repel","Target_Enemy","default_properties","_damage_output_disabled_until_msec"]

static func safe_value(value:Variant) -> bool:
	if typeof(value)==TYPE_RID: return false
	if typeof(value)==TYPE_OBJECT and not is_instance_valid(value): return false
	if value is Object: return value is Resource and not value is Script and not value is PackedScene
	if value is Array:
		for item:Variant in value:
			if not safe_value(item): return false
	if value is Dictionary:
		for key:Variant in value:
			if not safe_value(key) or not safe_value(value[key]): return false
	return true

static func copy_value(value:Variant) -> Variant:
	if value is Array:
		var array:Array=value.duplicate(true)
		for i:int in array.size(): array[i]=copy_value(array[i])
		return array
	if value is Dictionary:
		var dictionary:Dictionary=value.duplicate(true)
		for key:Variant in dictionary: dictionary[key]=copy_value(dictionary[key])
		return dictionary
	if value is Resource and not value is Texture2D and not value is AudioStream and not value is SpriteFrames and not value is Font:
		return value.duplicate(true)
	return value

static func properties(node:Node) -> Dictionary:
	var result:Dictionary = {}
	for info:Dictionary in node.get_property_list():
		var key:String = str(info.name)
		if key in SKIP or key.begins_with("_recall_") or not (int(info.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE): continue
		var value:Variant = node.get(key)
		if value==null or not safe_value(value): continue
		value=copy_value(value)
		result[key]=value
	return result

static func restore(node:Node,data:Dictionary) -> void:
	var available:Dictionary={}
	for info:Dictionary in node.get_property_list(): available[str(info.name)]=true
	for key:String in data:
		if not available.has(key): continue
		var value:Variant=data[key]
		value=copy_value(value)
		node.set(key,value)

static func visuals(root:Node,node:Node) -> Dictionary:
	var result:Dictionary={}
	if node!=root and node is CanvasItem:
		var record:Dictionary={}
		for key:String in ["texture","text","sprite_frames","frame","modulate","self_modulate","scale","flip_h","flip_v"]:
			var value:Variant=node.get(key)
			if value!=null: record[key]=value
		result[str(root.get_path_to(node))]=record
	for child:Node in node.get_children(): result.merge(visuals(root,child))
	return result

static func tick_context(context:ball,delta:float) -> void:
	var ref:WeakRef=context.get_meta("allay_context_shot",null)
	if ref==null or is_instance_valid(ref.get_ref()): return
	if context.get("_debts") is Dictionary and not context.get("_debts").is_empty(): return
	var left:float=float(context.get_meta("allay_context_grace",60.0))-delta
	context.set_meta("allay_context_grace",left)
	if left<=0.0: context.queue_free()

static func source_of(shot:Node) -> Node:
	return PROJECTILE_API.source_of(shot)

static func snapshot(shot:Node,data:Dictionary) -> Dictionary:
	var result:Dictionary=data.duplicate(true)
	result["native_script"]=shot.get_script().resource_path
	result["scene"]=shot.scene_file_path
	result["native_properties"]=properties(shot)
	result["native_scale"]=shot.scale
	result["visuals"]=visuals(shot,shot)
	result["kind"]="native"
	result["damage_kind"]=PROJECTILE_API.damage_kind_of(shot)
	var protocol_metadata:Dictionary={}
	for key:String in ["combat_classification","projectile_capabilities","projectile_damage_kind"]:
		if shot.has_meta(key): protocol_metadata[key]=copy_value(shot.get_meta(key))
	result["protocol_metadata"]=protocol_metadata
	result["sound"]=AUDIO.describe(shot,source_of(shot))
	var source:Node=source_of(shot)
	if is_instance_valid(source) and source is ball:
		var context:Dictionary={"scene":source.scene_file_path,"script":source.get_script().resource_path,"properties":properties(source),"attack":source.attack_damage(),"outgoing":source.effective_outgoing_damage(1.0)}
		if source.has_meta("allay_frozen_context"): context=source.get_meta("allay_frozen_context").duplicate(true)
		if source.get("native_feedback") is Node: context["feedback_role"]=source.native_feedback.role
		result["context"]=context
	return result

static func context_code(path:String) -> String:
	var code:String="extends "+JSON.stringify(path)+"\n"
	code+="var _allay_frozen_attack:float=0.0\nvar _allay_frozen_outgoing:float=1.0\n"
	code+="func _ready() -> void: pass\nfunc _enter_tree() -> void: pass\nfunc _process(_delta:float) -> void: pass\n"
	code+="func _physics_process(delta:float) -> void:\n\tload(\"res://scripts/characters/我的世界/allay/native_return.gd\").tick_context(self,delta)\n\tif is_instance_valid(Master) and Master.health>0 and Master.is_combat_runtime_active():\n\t\tif has_method(\"_process_debts\"): call(\"_process_debts\",delta)\n"
	code+="func tick_physics(_state:State,_delta:float) -> void: pass\nfunc Attack() -> void: pass\nfunc Skill() -> void: pass\n"
	code+="func attack_damage(multiplier:float=1.0) -> float: return _allay_frozen_attack*maxf(multiplier,0.0)\n"
	code+="func effective_outgoing_damage(raw_damage:float) -> float: return maxf(raw_damage,0.0)*_allay_frozen_outgoing\n"
	code+="func is_damage_output_disabled() -> bool: return false\nfunc is_combat_targetable() -> bool: return false\n"
	code+="func has_player_control_aim() -> bool: return false\n"
	if path.ends_with("溺尸.gd"):
		code+="func catch_trident(spear:Node2D) -> void: spear.retire()\n"
	return code

static func disable_body(node:Node) -> void:
	for group:StringName in node.get_groups(): node.remove_from_group(group)
	if node is CollisionObject2D:
		node.collision_layer=0
		node.collision_mask=0
	if node is CollisionShape2D: node.disabled=true
	for child:Node in node.get_children():
		child.process_mode=Node.PROCESS_MODE_DISABLED
		disable_body(child)

static func context_for(owner_ball:ball,data:Dictionary) -> ball:
	if not data.has("context"): return owner_ball
	var state:Dictionary=data.context
	var path:String=str(state.script)
	if path.is_empty(): return owner_ball
	var code_script:GDScript=context_scripts.get(path)
	if code_script==null:
		code_script=GDScript.new()
		code_script.source_code=context_code(path)
		if code_script.reload()!=OK: return null
		context_scripts[path]=code_script
	var scene_path:String=str(state.scene)
	if scene_path.is_empty(): scene_path="res://scenes/ball.tscn"
	var context:ball=load(scene_path).instantiate()
	context.set_script(code_script)
	context.set_meta("allay_frozen_context",state)
	context.set_meta("death_return_restore",true)
	context.health=1
	context.Max_health=1
	context.Master=owner_ball
	context.Team=owner_ball.Team
	context.Type=ball.Ball_Type.Shooter
	context.Can_Attack=false; context.Can_Skill=false
	context.process_mode=Node.PROCESS_MODE_DISABLED
	context.visible=false
	context.name="AllayReturnContext_"+str(context.get_instance_id())
	disable_body(context)
	owner_ball.add_child(context,true)
	restore(context,state.properties)
	context.Master=owner_ball; context.Team=owner_ball.Team
	context._allay_frozen_attack=float(state.attack)
	context._allay_frozen_outgoing=float(state.outgoing)
	context.position=Vector2.ZERO
	context.Can_Attack=false; context.Can_Skill=false
	disable_body(context)
	if state.has("feedback_role"):
		context.native_feedback=load("res://scripts/effects/我的世界/mc16_native_feedback.gd").attach(context,str(state.feedback_role))
		context.native_feedback.process_mode=Node.PROCESS_MODE_DISABLED
	context.process_mode=Node.PROCESS_MODE_INHERIT
	return context

static func bind_owner(shot:Node,source:ball,owner_ball:ball,target:ball) -> void:
	PROJECTILE_API.bind_owner(shot,source,owner_ball.Team,target)
	var c:Dictionary=EXT.config(shot)
	if c.has("owner"):
		var key:String=str(c.owner)
		shot.set(key,weakref(source) if key in ["_caster","owner_ref","_src_ref","_source_ref"] else source)
	if c.has("team"): shot.set(c.team,owner_ball.Team)
	if c.has("owner_method"): shot.set("Master_name",str(owner_ball.get_tree().current_scene.get_path_to(source)))
	if shot is ball:
		shot.Master=source
		shot.Master_name=str(owner_ball.get_tree().current_scene.get_path_to(source))
		shot.Team=owner_ball.Team
		shot.Target_Enemy=target
		shot.Ignore_Team_Damage_Setting=true
	if shot.get("_source_ref")!=null or shot.has_method("_source_ball"):
		shot.set("_source_ref",weakref(source))
		shot.set("_source_team",owner_ball.Team)

static func redirect(shot:Node,point:Vector2,target:ball) -> void:
	var aim:Vector2=point.direction_to(ball.body_point(target,point))
	if aim.length_squared()<0.000001: aim=Vector2.RIGHT
	var fields:Dictionary={}
	for info:Dictionary in shot.get_property_list(): fields[str(info.name)]=true
	for key:String in ["direction","_direction","travel_direction","axis","forward"]:
		if fields.has(key): shot.set(key,aim)
	if fields.has("lateral"): shot.set("lateral",aim.rotated(PI*0.5))
	for key:String in ["start_position","spawn_position","travel_origin","_origin","_last_position","_smoke_previous"]:
		if fields.has(key): shot.set(key,point)
	if fields.has("target_position"): shot.set("target_position",target.global_position)
	if fields.has("aimed_position"): shot.set("aimed_position",target.global_position)
	for key:String in ["target_ref","_target_ref"]:
		if fields.has(key): shot.set(key,weakref(target))
	for key:String in ["_elapsed","elapsed","traveled","traveled_x","_travelled","_travelled_distance","_distance","clock","boomerang_outbound_travelled"]:
		if fields.has(key): shot.set(key,0)
	for key:String in ["hit_ids","_hit_target_ids","boomerang_last_hit_msec","_recent_hit_cooldowns"]:
		if fields.has(key): shot.set(key,{})
	if fields.has("_trail_points"): shot.set("_trail_points",PackedVector2Array())
	if fields.has("flight_velocity"): shot.set("flight_velocity",aim*shot.flight_velocity.length())
	if fields.has("returning"): shot.set("returning",false)
	shot.global_position=point
	PROJECTILE_API.set_velocity(shot,aim*maxf(PROJECTILE_API.speed_of(shot),1.0))
	if shot.has_method("relaunch_projectile"): shot.call("relaunch_projectile",point,target)
	shot.rotation=aim.angle()

static func launch(owner_ball:ball,data:Dictionary,target:ball,point:Vector2) -> Node2D:
	if not data.has("native_script"): return null
	var source:ball=context_for(owner_ball,data)
	if source==null: return null
	var scene_path:String=str(data.get("scene",""))
	var shot:Node2D=load(scene_path).instantiate() if not scene_path.is_empty() else load(str(data.native_script)).new()
	restore(shot,data.native_properties)
	for key:String in data.get("protocol_metadata",{}): shot.set_meta(key,copy_value(data.protocol_metadata[key]))
	shot.set_meta("projectile_damage_kind",str(data.get("damage_kind","ordinary")))
	bind_owner(shot,source,owner_ball,target)
	shot.position=point
	shot.scale=data.native_scale
	shot.set_meta("allay_returned",true)
	shot.set_meta("forced_combat_team",owner_ball.Team)
	shot.name=Game.return_random_name(shot)
	owner_ball.get_tree().current_scene.add_child(shot,true)
	# _ready may install defaults; restore captured gameplay values a second time.
	restore(shot,data.native_properties)
	bind_owner(shot,source,owner_ball,target)
	redirect(shot,point,target)
	shot.add_to_group("BattleTransient")
	var path:String=str(data.native_script)
	if path.ends_with("/allay/note.gd"): shot.cancel_recall()
	if path.ends_with("女巫药水.gd"):
		shot.setup(point,target.global_position,shot.effect_type,source)
	elif path.ends_with("收债人_钱.gd"):
		shot.setup(source,point,point.direction_to(ball.body_point(target,point)),shot.projectile_speed,shot.max_lifetime,owner_ball.Team,true)
	elif path.ends_with("数学老师公式弹.gd"):
		shot.configure(source,{"origin":point,"forward":point.direction_to(ball.body_point(target,point)),"speed":shot.travel_speed,"lifetime":shot.max_lifetime,"damage":shot.damage_amount,"team":owner_ball.Team,"span":shot.curve_span,"amplitude":shot.curve_amplitude,"curve_kind":shot.curve_kind},true)
	elif path.ends_with("薇欧拉_文字弹.gd"):
		shot.rotation=0.0
		shot._apply_readable_text_rotation()
	elif path.ends_with("水泼弹.gd") or path.ends_with("蛛网弹.gd"):
		shot.add_to_group("AllayExtendedProjectile")
	elif path.ends_with("三叉戟.gd"):
		source._trident=shot; source._tridents[shot.serial]=shot
		shot.flight_state=1
	elif path.ends_with("fireball.gd"):
		shot.launch_owner_id=owner_ball.get_instance_id()
		shot.configure_launch(point)
		shot.neutral=true; shot.Team=""; shot.Master=null; shot.Master_name=""
	for visual_path:String in data.get("visuals",{}):
		var visual:Node=shot.get_node_or_null(NodePath(visual_path))
		if visual!=null:
			for key:String in data.visuals[visual_path]: visual.set(key,data.visuals[visual_path][key])
	if shot.has_method("_setup_visual"): shot.call("_setup_visual")
	if source!=owner_ball:
		source.set_meta("allay_context_shot",weakref(shot))
		var grace:float=60.0
		for key:String in data.native_properties:
			if ("duration" in key or "lifetime" in key) and data.native_properties[key] is float: grace=maxf(grace,float(data.native_properties[key])+5.0)
		source.set_meta("allay_context_grace",grace)
	var audio_node:Node=AUDIO.play(owner_ball,data.get("sound",{}),point)
	if is_instance_valid(audio_node): shot.set_meta("allay_launch_audio",weakref(audio_node))
	shot.set_meta("allay_launch_sound",data.get("sound",{}))
	return shot
