extends SceneTree
var checks:int = 0
var failures:int = 0
var arena:Node2D
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("REWORK_FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var packed:PackedScene = load(path)
	if packed == null:
		push_error("Scene unavailable: "+path)
		quit(2)
		return null
	var actor = packed.instantiate()
	actor.Team = team
	actor.position = point
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	for child:Node in actor.find_children("*","CollisionObject2D",true,false):
		(child as CollisionObject2D).disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	arena.add_child(actor,true)
	return actor
func wall_at(point:Vector2) -> StaticBody2D:
	var wall:StaticBody2D = StaticBody2D.new()
	var cs:CollisionShape2D = CollisionShape2D.new()
	var box:RectangleShape2D = RectangleShape2D.new()
	box.size = Vector2(5,200)
	cs.shape = box
	wall.add_child(cs)
	arena.add_child(wall)
	wall.global_position = point
	return wall
func effect_for(actor):
	for child in actor.get_children():
		if child.has_method("replace_with_hit") and child.is_active_effect(): return child
	return null
func sounds(event:String) -> Array[Node]:
	return get_nodes_in_group("MCNativeSFX").filter(func(n:Node): return not n.is_queued_for_deletion() and n.get_meta("mc_sound_event","")==event)
func clear_sounds() -> void:
	for n:Node in get_nodes_in_group("MCNativeSFX"):
		n.stop()
		n.remove_from_group("MCNativeSFX")
		n.queue_free()
func run() -> void:
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(100,0),"B")
	var audio = load("res://scripts/characters/我的世界/new5/audio.gd")
	for event:String in ["entity.sheep.hit","entity.sheep.ambient","entity.sheep.hurt","entity.sheep.death","entity.sheep.step","block.wool.place","block.wool.break"]:
		check(audio.EVENTS.has(event),"event exists "+event)
		for record:Dictionary in audio.EVENTS[event]: check(record.stream.get_length()>0,"valid native clip "+event)
	for record:Dictionary in audio.EVENTS["entity.sheep.step"]:
		check(record.stream.resource_path.contains("sheep_step"),"footsteps use sheep mob clips not wool block clips")
	check(is_equal_approx(sheep.attack_damage(),sheep.effective_outgoing_damage(float(sheep.Damage))*0.8),"base sheep damage reduced to eighty percent")
	for speed:float in [0.0,92.0,260.0,520.0]:
		var ratio:float = speed/520.0
		var profile:Dictionary = sheep.impact_profile(speed)
		check(is_equal_approx(profile.damage,sheep.effective_outgoing_damage(float(sheep.Damage)*(0.5+3*ratio))*0.8),"ram damage scaled once")
		check(is_equal_approx(profile.wall_damage,sheep.effective_outgoing_damage(float(sheep.Damage)*(0.5+1.8*ratio))*0.8),"victim wall damage also scaled")
	# Saturate the native mixer before defence: placement must still obtain a voice.
	clear_sounds()
	for i:int in range(24): audio.play(sheep,"entity.sheep.step",Vector2.ZERO,-8,false,false,true,true)
	check(get_nodes_in_group("MCNativeSFX").size()==24,"mixer saturated fixture")
	sheep._begin_wool()
	var placement:Array[Node] = sounds("block.wool.place")
	check(placement.size()==1 and placement[0].playing,"wool place still starts with twenty-four active voices")
	check(placement[0].get_meta("mc_sound_priority",false) and placement[0].volume_db==6.0,"wool place has priority and audible gain")
	check(placement[0].stream.resource_path.contains("dig_cloth"),"placement still uses native wool sample")
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	sheep.wool = 3
	clear_sounds()
	sheep._ambient_cd = 0
	sheep._step_sheep_sounds(0.01)
	check(sounds("entity.sheep.ambient").size()==1,"idle sheep breathes")
	var breath = sheep._breath_player
	check(sheep._ambient_cd>=sheep._sound_duration(breath)+2 and sheep._ambient_cd<=sheep._sound_duration(breath)+5,"breath interval includes entire prior clip plus random wait")
	sheep._ambient_cd = 0
	sheep._step_sheep_sounds(0.01)
	check(sounds("entity.sheep.ambient").size()==1,"playing breath never overlaps itself")
	clear_sounds()
	sheep._ambient_cd = 100
	sheep._footstep_cadence.ready_now()
	sheep._step_sheep_sounds(0.01)
	check(sounds("entity.sheep.step").is_empty(),"stationary sheep has no footsteps")
	sheep.global_position.x += 2
	sheep._step_sheep_sounds(0.01)
	check(sounds("entity.sheep.step").size()==1,"actual movement makes footstep")
	var stride:float = sheep.FOOTSTEP.base_speed(sheep)*sheep.footstep_base_interval
	sheep.global_position.x += stride*0.5
	sheep._step_sheep_sounds(0.1)
	check(sounds("entity.sheep.step").size()==1,"half a stride adds no footstep")
	sheep.global_position.x += stride*0.6
	sheep._step_sheep_sounds(0.1)
	check(sounds("entity.sheep.step").size()==2,"after one stride the next footstep starts even while the previous plays")
	sheep.ram_state = sheep.RamState.CHARGE
	sheep.global_position.x += stride*1.1
	sheep._step_sheep_sounds(0.08)
	check(sounds("entity.sheep.step").size()==3,"charging covers a stride faster, so footsteps come faster")
	sheep._step_sheep_sounds(0.2)
	check(sounds("entity.sheep.step").size()==3,"blocked charge with no displacement stays quiet")
	clear_sounds()
	sheep.hurt_voice_chance = 0
	sheep.receive_positional_damage(1,sheep.global_position,false,enemy)
	check(sounds("entity.sheep.hurt").is_empty(),"hurt probability zero suppresses voice")
	sheep.hurt_voice_chance = 1
	sheep.receive_positional_damage(1,sheep.global_position,false,enemy)
	check(sounds("entity.sheep.hurt").size()==1,"actual nonfatal damage can play hurt voice")
	sheep._begin_charge(enemy.global_position)
	sheep._launch_charge()
	sheep._charge_touch(enemy,sheep.global_position)
	check(sounds("entity.sheep.hit").size()==1,"successful ram plays impact sound")
	clear_sounds()
	sheep.wool = 1
	sheep._wool_phase = 0
	sheep._wool_cooldown = 0
	sheep._begin_wool()
	check(sounds("block.wool.place").size()==1,"wool burst uses placement sound")
	check(sounds("entity.sheep.shear").is_empty(),"no shearing sound on burst")
	check(sounds("block.wool.break").is_empty(),"no premature wool break sound")
	sheep._step_wool(0.11)
	check(sounds("block.wool.break").size()==1,"wool break sound coincides with disappearance")
	sheep._step_wool(1)
	check(sounds("block.wool.break").size()==1,"wool break emitted once")
	clear_sounds()
	sheep.play_sound("entity.sheep.ambient")
	sheep.play_sound("entity.sheep.step")
	sheep.health = 0
	sheep.Die()
	check(sounds("entity.sheep.death").size()==1,"death voice plays on death")
	check(sounds("entity.sheep.ambient").is_empty() and sounds("entity.sheep.step").is_empty(),"death stops breath and walking voice")
	sheep.Die()
	check(sounds("entity.sheep.death").size()==1,"death voice deduplicated")
	print("SHEEP_AUDIO_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
