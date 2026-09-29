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
func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.get_node("Game").now_stop_state = false
	arena = Node2D.new()
	root.add_child(arena)
	current_scene = arena
	var sheep = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2.ZERO,"A")
	wall_at(Vector2(90,0))
	await physics_frame
	sheep._begin_charge(Vector2(100,0))
	sheep._launch_charge()
	sheep.move(sheep.Speed,0.5)
	check(sheep.dizziness,"real high speed wall collision stuns sheep")
	check(sheep.ram_state == sheep.RamState.RECOVER and sheep.velocity == Vector2.ZERO,"impact stops charge")
	check(sheep.wool == 3,"wall stun does not consume defensive wool")
	var effect = effect_for(sheep)
	check(effect != null and effect.stun_duration >= 1,"one second stun controller")
	if effect != null:
		effect._physics_process(0.5)
		check(sheep.dizziness,"stun persists through half second")
		effect._physics_process(0.6)
		check(not sheep.dizziness,"stun eventually releases control")
	var slow = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(1012,0),"A")
	wall_at(Vector2(1035,0))
	await physics_frame
	slow._begin_charge(Vector2(1100,0))
	slow._launch_charge()
	slow._charge_speed = 180
	var hp:int = slow.health
	slow.move(slow.Speed,0.1)
	check(slow.ram_state == slow.RamState.RECOVER,"real low speed wall collision stops charge")
	check(not slow.dizziness and slow.health == hp,"low speed wall contact does not stun or self damage")
	var grazer = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(2000,0),"A")
	grazer.visual_mob()
	check(not grazer._grass_patch.visible,"no grass while roaming")
	grazer.ram_state = grazer.RamState.BRAKE_GRAZE
	grazer.visual_mob()
	check(not grazer._grass_patch.visible,"no grass before braking has finished")
	grazer.health = 300
	grazer.ram_state = grazer.RamState.GRAZE
	grazer.visual_mob()
	check(grazer._grass_patch.visible,"grass visible while eating")
	check(grazer._grass_patch.get_child_count() == 1,"single native grass tuft")
	var tuft:Sprite2D = grazer._grass_patch.get_node("VanillaGrass0")
	check(tuft.texture != null and tuft.texture.resource_path.ends_with("short_grass.png"),"actual Minecraft short grass imported")
	check(tuft.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,"pixel texture filtering")
	check(grazer._grass_patch.global_position == grazer._graze_ground_position(),"grass positioned on ground beneath feet")
	grazer.graphics.rotation = 0.7
	grazer.visual_mob()
	check(grazer._grass_patch.global_rotation == 0,"ground does not rotate with sheep")
	grazer.receive_positional_damage(10,grazer.global_position,false,null)
	check(not grazer._grass_patch.visible,"damage removes grass immediately")
	grazer.health = grazer.Max_health-1
	grazer.ram_state = grazer.RamState.GRAZE
	grazer._graze(1.0)
	grazer.visual_mob()
	check(not grazer._grass_patch.visible,"full health removes grass")
	var patch = grazer._grass_patch
	grazer.queue_free()
	await process_frame
	check(not is_instance_valid(patch),"actor removal cleans up ground patch")
	var busy = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(4000,0),"A")
	wall_at(Vector2(4090,0))
	await physics_frame
	var old_motion = busy.apply_knockback(Vector2.RIGHT,100,400,0,0,{"lock_control":false})
	busy._begin_charge(Vector2(4100,0))
	busy._launch_charge()
	busy.move(busy.Speed,0.5)
	check(busy.dizziness and busy._stun_visual_ref_count == 1,"existing knockback does not delay wall stun visual")
	var crash_stun = busy._wall_stun_effect.get_ref()
	check(crash_stun != old_motion and crash_stun._stage == 1,"dedicated immediate stun stage")
	var fx = busy._stun_visual_instance
	check(is_instance_valid(fx) and fx.is_visible_in_tree(),"head effect visible after actual crash")
	if is_instance_valid(fx):
		var age:float = fx.age
		fx._process(0.15)
		check(fx.age > age and fx.front_layer.pixels.size() > 0,"head orbit animates rather than static icon")
		check(fx.front_layer.z_index > fx.effective_z(busy._wool_visual),"front orbit above wool shell")
	check(bool(busy.visual_state().wall_stunned),"visual snapshot includes active wall stun")
	crash_stun._physics_process(1.05)
	check(busy._stun_visual_ref_count == 0 and not busy._wall_stun_active(),"wall stun visual releases on expiry")
	var remote = spawn("res://scenes/characters/我的世界/羊.tscn",Vector2(5000,0),"A")
	remote.set_multiplayer_authority(2)
	remote.accept_visual({"wall_stunned":true})
	remote.accept_visual({"wall_stunned":true})
	check(remote._stun_visual_ref_count == 1 and is_instance_valid(remote._stun_visual_instance),"remote snapshots show without duplicate visuals")
	remote.accept_visual({"wall_stunned":false})
	check(remote._stun_visual_ref_count == 0,"remote clear removes head effect")
	print("SHEEP_WALL_GRASS_RESULT checks=",checks," failures=",failures)
	current_scene = null
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
