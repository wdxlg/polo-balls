extends SceneTree
var arena:Node2D
var checks:int = 0
var failures:int = 0
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok: failures += 1; print("RIDER_SHADOW_FAIL ",label)
func _initialize() -> void: call_deferred("run")
func spawn(path:String,point:Vector2,team:String):
	var actor = load(path).instantiate()
	actor.Team = team
	actor.position = point
	arena.add_child(actor,true)
	return actor
func shadow_of(actor) -> Node2D:
	return actor.get("_character_ground_shadow") as Node2D
func run() -> void:
	root.get_node("Game").now_stop_state = false
	root.get_node("Game").Game_Settings.Have_Team_Damage = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var boat = spawn("res://scenes/characters/我的世界/木船.tscn",Vector2.ZERO,"A")
	var enemy = spawn("res://scenes/characters/我的世界/重锤.tscn",Vector2(28,0),"B")
	var ally = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(-28,0),"A")
	boat._board_left = 1e9
	enemy.state_machine.set_physics_process(false)
	ally.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	await process_frame
	check(shadow_of(enemy) != null and shadow_of(enemy).visible,"enemy has a visible shadow before boarding")
	check(boat.board_unit(enemy) and boat.board_unit(ally),"both units boarded")
	await physics_frame
	await process_frame
	check(shadow_of(enemy) != null and not shadow_of(enemy).visible,"boarded enemy shadow hidden")
	check(shadow_of(ally) != null and not shadow_of(ally).visible,"boarded ally shadow hidden")
	check(shadow_of(boat) == null or shadow_of(boat).visible,"boat's own shadow untouched")
	# 换图重建影子后仍保持隐藏
	enemy.refresh_character_ground_shadow()
	await process_frame
	await process_frame
	await physics_frame
	await process_frame
	check(shadow_of(enemy) != null and not shadow_of(enemy).visible,"rebuilt shadow stays hidden while on board")
	boat.release_all()
	await process_frame
	check(shadow_of(enemy) != null and shadow_of(enemy).visible,"shadow restored after disembark")
	check(shadow_of(ally) != null and shadow_of(ally).visible,"ally shadow restored after disembark")
	print("RIDER_SHADOW_RESULT checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
