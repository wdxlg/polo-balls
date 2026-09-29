extends SceneTree
## Reproduce the exact blocked-parent errors using the production Wither audio helper.
const AUDIO = preload("res://scripts/characters/我的世界/wither/audio.gd")
class Emitter extends Node:
	var on_ready_sound:bool = false
	var on_exit_sound:bool = false
	func _ready() -> void:
		if on_ready_sound: AUDIO.play(self,"shoot",Vector2(12,34))
	func _exit_tree() -> void:
		if on_exit_sound: AUDIO.play(self,"beacon_deactivate",Vector2(56,78))

var checks:int = 0
var failures:int = 0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS: " if ok else "FAIL: ",label)
func sounds(parent:Node) -> Array[AudioStreamPlayer2D]:
	var found:Array[AudioStreamPlayer2D] = []
	if not is_instance_valid(parent): return found
	for child:Node in parent.get_children():
		if child is AudioStreamPlayer2D: found.append(child)
	return found
func settle() -> void:
	await process_frame
	await physics_frame
	await process_frame
func clear_sounds(parent:Node) -> void:
	for p:AudioStreamPlayer2D in sounds(parent): p.free()
func run() -> void:
	var game:Node = root.get_node("Game")
	var stopped:bool = game.now_stop_state
	game.now_stop_state = false
	# The current scene is still entering/setting up children when this child becomes ready.
	var stage:=Node2D.new()
	stage.position = Vector2(120,60)
	stage.scale = Vector2(2,2)
	var born:=Emitter.new()
	born.on_ready_sound = true
	stage.add_child(born)
	stage.tree_entered.connect(func(): current_scene=stage,CONNECT_ONE_SHOT)
	root.add_child(stage)
	await settle()
	check(sounds(stage).size()==1,"child ready sound is attached once after parent setup unlocks")
	if not sounds(stage).is_empty():
		var p:AudioStreamPlayer2D = sounds(stage)[0]
		check(p.is_inside_tree() and p.playing,"ready sound actually plays, not merely suppresses errors")
		check(p.global_position==Vector2(12,34) and p.stream==AUDIO.STREAMS.shoot and p.volume_db==0.0 and p.max_distance==1800.0,"native stream, captured world position and audio parameters are unchanged")
		await create_timer(p.stream.get_length()+0.15).timeout
		check(not is_instance_valid(p),"finished one-shot frees itself naturally")
	clear_sounds(stage)
	var dying:=Emitter.new()
	dying.on_exit_sound = true
	stage.add_child(dying)
	# Parent is blocked during the child's tree-exit notification; source then disappears.
	dying.free()
	await settle()
	check(sounds(stage).size()==1,"tree-exit sound survives deletion of the source and attaches exactly once")
	if not sounds(stage).is_empty():
		var p:AudioStreamPlayer2D = sounds(stage)[0]
		check(p.playing and p.stream==AUDIO.STREAMS.beacon_deactivate and p.global_position==Vector2(56,78),"deactivation tail retains its real stream and original location")
	clear_sounds(stage)
	AUDIO.play(born,"hurt1",Vector2(80,90))
	AUDIO.play(born,"hurt2",Vector2(81,91))
	await settle()
	check(sounds(stage).size()==2,"normal runtime requests are neither duplicated nor silently throttled")
	clear_sounds(stage)
	AUDIO.play(born,"not_an_event",Vector2.ZERO)
	var detached:=Node.new()
	AUDIO.play(detached,"shoot",Vector2.ZERO)
	detached.free()
	await settle()
	check(sounds(stage).is_empty(),"unknown events and detached callers do not allocate orphan players")
	# A pending cue must never be redirected into a replacement scene.
	AUDIO.play(born,"shoot",Vector2.ZERO)
	var replacement:=Node2D.new()
	root.add_child(replacement)
	current_scene = replacement
	await settle()
	check(sounds(stage).is_empty() and sounds(replacement).is_empty(),"scene replacement cancels stale queued audio instead of playing it in either scene")
	current_scene = stage
	replacement.free()
	var departing:=Emitter.new()
	departing.on_exit_sound = true
	stage.add_child(departing)
	stage.queue_free()
	await settle()
	check(not is_instance_valid(stage),"whole-scene deletion completes without resurrecting its sound nodes")
	var leaked:int = 0
	for id:int in Node.get_orphan_node_ids():
		var node:Object = instance_from_id(id)
		if node is AudioStreamPlayer2D and node.stream in AUDIO.STREAMS.values():
			leaked+=1
			node.free() # Baseline failed add_child must not leak out of the test itself.
	check(leaked==0,"failed or cancelled lifecycle requests leave no orphan audio players")
	game.now_stop_state = stopped
	print("WITHER_AUDIO_LIFECYCLE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
