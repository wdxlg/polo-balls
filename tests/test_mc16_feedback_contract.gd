extends SceneTree
var game:Node
var arena:Node2D
var checks:int = 0
var failures:int = 0
var saved:Dictionary
var stopped:bool
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func clear_audio() -> void:
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		player.stop()
		player.free()
func make(role:String) -> Node2D:
	var actor:Node2D = load("res://scenes/characters/我的世界/"+role+".tscn").instantiate()
	actor.Team = "Team0"
	actor.Can_Attack = false
	actor.Can_Skill = false
	actor.Health_Restore = 0
	arena.add_child(actor,true)
	actor.state_machine.set_physics_process(false)
	actor.set_process(false)
	actor.set_physics_process(false)
	return actor
func run() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	stopped = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	create_timer(45,true,false,true).timeout.connect(func():push_error("MC16_CONTRACT_TIMEOUT");quit(2))
	for role:String in ["铜剑","蜘蛛","溺尸"]:
		var actor:Node2D = make(role)
		var feedback:Node = actor.native_feedback
		feedback.set_physics_process(false)
		var fields:Dictionary = {}
		for property:Dictionary in actor.get_property_list(): fields[property.name] = true
		for key:String in ["global_position","health","Speed","dizziness"]:
			check(fields.has(key),role+" implements shared field "+key)
		for method:String in ["mc_live","mc_enemy","is_combat_runtime_active","is_multiplayer_authority"]:
			check(actor.has_method(method),role+" implements feedback method "+method)
		feedback._last_position = actor.global_position
		feedback.advance(0.1)
		check(feedback.played.is_empty(),role+" stationary tick is silent")
		var event:String = "entity."+str(feedback.role)+".step"
		if role=="铜剑":
			check(not fields.has("footstep_gap_min") and not fields.has("footstep_gap_max"),"real copper retains item-only schema, not fake creature parameters")
			check(not feedback.BANK.EVENTS.has(event),"copper has no invented native footstep")
			check(is_equal_approx(feedback._footstep_interval(),0.65),"optional tuning reader safely defaults both missing fields")
			var before:float = feedback._clock
			for i:int in range(120):
				actor.global_position += Vector2(1,0)
				feedback.advance(1.0/60.0)
			check(feedback._clock>before+1.9 and feedback.played.is_empty(),"moving copper advances cue clock without creature-only access or sounds")
			check(feedback._step_cadence._since_step==INF,"unsupported footsteps never consume distance cadence")
			feedback.set_physics_process(true)
			await physics_frame
			await physics_frame
			feedback.set_physics_process(false)
			check(feedback._clock>before+2.0,"real engine physics callback also completes for copper")
			var sound:Node = feedback.request("block.enchantment_table.use",actor.global_position,-7.0,0.0)
			check(is_instance_valid(sound) and int(feedback.played.get("block.enchantment_table.use",0))==1,"skipping creature steps does not disable copper's actual enchantment cue")
		else:
			actor.footstep_gap_min = 0.2
			actor.footstep_gap_max = 0.6
			check(is_equal_approx(feedback._footstep_interval(),feedback._step_length+0.4),role+" preserves configured creature interval")
			actor.global_position += Vector2(2,0)
			feedback.advance(0.1)
			check(int(feedback.played.get(event,0))==1,role+" genuine movement still emits native step")
			var step:Node = feedback._players[-1].get_ref()
			check(is_instance_valid(step) and step.stream!=null and step.bus==&"GameplayRecord",role+" uses playable native resource and recording bus")
			check(is_equal_approx(feedback._step_length,step.stream.get_length()),role+" interval continues to use actual clip length")
			actor.footstep_gap_min = -1
			actor.footstep_gap_max = -2
			check(is_equal_approx(feedback._footstep_interval(),feedback._step_length+0.05),role+" invalid negative interval remains clamped")
			actor.footstep_gap_min = 0.15
			actor.footstep_gap_max = 0.45
			var count:int = feedback.played[event]
			actor.dizziness = true
			actor.global_position += Vector2(4,0)
			feedback.advance(0.2)
			check(feedback.played[event]==count,role+" stun does not generate footsteps")
			actor.dizziness = false
			actor.global_position += Vector2(400,0)
			feedback.advance(0.016)
			check(feedback.played[event]==count,role+" teleport does not generate footsteps")
			if role=="蜘蛛":
				actor._lunge_left = 0.2
				actor.global_position += Vector2(4,0)
				feedback.advance(0.2)
				check(feedback.played[event]==count,"spider airborne lunge remains silent")
				actor._lunge_left = 0
		var clock:float = feedback._clock
		game.now_stop_state = true
		feedback.advance(1)
		check(feedback._clock==clock,role+" battle pause freezes cue clock")
		game.now_stop_state = false
		actor.set_multiplayer_authority(2)
		var previous:Dictionary = feedback.played.duplicate()
		actor.global_position += Vector2(4,0)
		feedback.advance(0.2)
		check(feedback.played==previous and feedback.request("block.enchantment_table.use",Vector2.ZERO)==null,role+" replica originates no audio")
		actor.set_multiplayer_authority(1)
		clear_audio()
		actor.free()
		await process_frame
	# A returned projectile's context uses the original script inheritance but
	# deliberately skips _ready; it must also tolerate item-only feedback.
	var native:Script = load("res://scripts/characters/我的世界/allay/native_return.gd")
	var context_script:=GDScript.new()
	context_script.source_code = native.context_code("res://scripts/characters/我的世界/铜剑.gd")
	check(context_script.reload()==OK,"real Allay return context code compiles")
	var context:Node2D = load("res://scenes/characters/我的世界/铜剑.tscn").instantiate()
	context.set_script(context_script)
	arena.add_child(context)
	context.set_physics_process(false)
	var effect:Node = load("res://scripts/effects/我的世界/mc16_native_feedback.gd").attach(context,"copper_sword")
	effect.set_physics_process(false)
	check(is_equal_approx(effect._footstep_interval(),0.65),"returned copper context also lacks no required walking configuration")
	context.free()
	clear_audio()
	arena.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = stopped
	print("MC16_FEEDBACK_CONTRACT_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
