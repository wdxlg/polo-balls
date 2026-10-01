extends SceneTree
class Arena extends Node2D:
	var active:bool = true
	func is_combat_runtime_active() -> bool: return active
var arena:Node2D
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ",label)
	if not ok: failures += 1
func unit(role:String,point:Vector2,team:String="Team1",parent:Node2D=null,label:String="") -> Node2D:
	var node:Node2D = load("res://scenes/ball.tscn" if role.is_empty() else "res://scenes/characters/我的世界/"+role+".tscn").instantiate()
	if not label.is_empty(): node.name = label
	node.Team = team
	node.Speed = 0.0
	node.Can_Attack = false
	node.Can_Skill = false
	node.Health_Restore = 0
	node.Has_Collision_Damage = false
	if role.is_empty(): node.Max_health = 500
	(arena if parent==null else parent).add_child(node,true)
	node.global_position = point
	node.state_machine.set_physics_process(false)
	node.set_physics_process(false)
	node.set_process(false)
	return node
func release(caster:Node2D) -> Node2D:
	caster.health = 0
	var wave:Node2D = caster._totem_wave
	wave.set_physics_process(false)
	return wave
func push_of(target:Node2D) -> Node:
	for child:Node in target.get_children():
		if child.get_script()==target.KNOCKBACK_EFFECT_SCRIPT: return child
	return null
func reset_case() -> void:
	for child:Node in arena.get_children(): child.queue_free()
	await process_frame
	await physics_frame
func begin() -> void:
	game = root.get_node("Game")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = Arena.new()
	root.add_child(arena)
	current_scene = arena
	create_timer(70,true,false,true).timeout.connect(func():push_error("TOTEM_WAVE_TIMEOUT");quit(2))
func finish() -> void:
	current_scene = null
	arena.queue_free()
	await process_frame
	await process_frame
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	print("TOTEM_WAVE_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
func run() -> void:
	begin()
	var caster:Node2D = unit("唤魔者",Vector2.ZERO,"Team0")
	var near:Node2D = unit("",Vector2(90,0))
	var far:Node2D = unit("",Vector2(0,145))
	var outside:Node2D = unit("",Vector2(260,0))
	var friend:Node2D = unit("",Vector2(-90,0),"Team0")
	var summon:Node2D = unit("",Vector2(0,-90))
	summon.Master = caster
	caster.health -= 10
	check(not is_instance_valid(caster._totem_wave),"ordinary health loss creates no wave")
	caster._show_totem_visual()
	check(not is_instance_valid(caster._totem_wave),"standalone totem icon cannot create an attack")
	var wave:Node2D = release(caster)
	check(caster.health==50 and caster._totem_used,"real lethal write still restores fifty health")
	check(wave.get_parent()!=caster and wave.global_position==Vector2.ZERO,"wave is detached at actual trigger origin")
	arena.position = Vector2(40,30)
	check(wave.global_position==Vector2.ZERO,"even parent motion cannot drag the fixed wave origin")
	arena.position = Vector2.ZERO
	check(wave.radius==0 and near.health==500 and far.health==500,"lethal setter never nests enemy damage")
	caster._show_totem_wave(Vector2(300,300),900,5)
	check(get_nodes_in_group("MCEvokerTotemWave").size()==1 and wave.global_position==Vector2.ZERO,"replayed packet cannot duplicate or relocate wave")
	wave.advance(0.15)
	check(is_equal_approx(wave.radius,40) and near.health==500 and far.health==500,"outside the expanding front remains unhurt")
	var alpha:float = wave.opacity()
	caster.global_position = Vector2(45,25)
	caster.Damage = 48
	wave.advance(0.20)
	check(near.health==488 and far.health==500,"front hits near enemy using CURRENT quarter attack, not distant enemy")
	check(wave.global_position==Vector2.ZERO and wave.opacity()<alpha,"ring stays at trigger point and fades while expanding")
	var push:Node = push_of(near)
	check(push!=null,"legitimate wave hit installs shared knockback controller")
	if push!=null:
		check(is_equal_approx(push.distance,60) and is_equal_approx(push.speed,240) and push.stun_duration==0,"medium push has sixty distance, 240 speed, no extra stun")
		check(push.direction.is_equal_approx(Vector2.RIGHT),"outward direction comes from fixed wave origin, not moved caster")
	check(caster.get_ai_attack_threats(near).is_empty(),"already-hit enemy has no repeat threat")
	var threats:Array = caster.get_ai_attack_threats(far)
	check(threats.size()==48 and caster.get_debug_attack_regions().size()==48,"AI and debug share the current 48-segment annulus")
	if not threats.is_empty():
		check(is_equal_approx(threats[0].start.length(),(wave.previous_radius+wave.radius)*0.5) and is_equal_approx(threats[0].radius,3.5+(wave.radius-wave.previous_radius)*0.5),"declared geometry is the actual swept front")
	wave.advance(0.24)
	check(near.health==488 and far.health==488,"each enemy hit once as the front reaches it")
	check(friend.health==500 and summon.health==500 and outside.health==500 and caster.health==50,"self, team, summon lineage and outside radius are excluded")
	wave.advance(0.02)
	check(wave.is_queued_for_deletion() and wave.opacity()==0,"ring finishes fully transparent and self-cleans")
	await reset_case()
	# Ordinary defenses must remain in effect, unlike the other shared-ring caller.
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	var armored:Node2D = unit("",Vector2(90,0))
	armored.Damage_reduction = 0.5
	var blocked:Node2D = unit("",Vector2(-90,0))
	blocked.max_block = 50
	blocked.block = 50
	var immune:Node2D = unit("",Vector2(0,-90))
	immune.set_meta("ignore_combat_targeting",true)
	wave = release(caster)
	wave.advance(0.4)
	check(armored.health==496,"normal damage reduction halves default eight damage")
	check(blocked.health==500 and blocked.block==42,"ordinary block absorbs wave instead of being bypassed")
	check(immune.health==500 and push_of(immune)==null,"untargetable enemy receives neither damage nor push")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	near = unit("",Vector2(90,0))
	wave = release(caster)
	game.now_stop_state = true
	wave.advance(0.4)
	check(wave.age==0 and near.health==500 and wave.threats(near).is_empty(),"battle pause freezes visuals, damage and threat")
	game.now_stop_state = false
	paused = true
	wave.advance(0.4)
	check(wave.age==0,"scene-tree pause also freezes manual advance")
	paused = false
	arena.active = false
	wave.advance(0.4)
	check(wave.age==0,"pre-combat runtime gate cannot consume the wave")
	arena.active = true
	caster.dizziness = true
	wave.advance(0.4)
	check(near.health==492,"ordinary stun does not cancel already-triggered passive wave")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	near = unit("",Vector2(90,0))
	wave = release(caster)
	caster.apply_damage_disable(10)
	wave.advance(0.4)
	check(near.health==500 and push_of(near)==null and wave.threats(near).is_empty(),"output disable suppresses damage, push and danger")
	caster.free()
	wave.advance(0.3)
	check(wave.is_queued_for_deletion(),"orphaned cosmetic wave fades and cleans without source access")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	near = unit("",Vector2(90,0))
	wave = release(caster)
	caster.health = 0
	wave.advance(0.4)
	check(near.health==500 and get_nodes_in_group("MCEvokerTotemWave").size()==1,"second death neither replays nor leaves damaging wave")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	caster.set_meta("__out_of_bounds_forced_death",true)
	caster.health = 0
	check(not caster._totem_used and not is_instance_valid(caster._totem_wave),"forced out-of-bounds death has no totem wave")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	near = unit("",Vector2(90,0))
	var wall:=StaticBody2D.new()
	wall.collision_layer = 1
	var collider:=CollisionShape2D.new()
	var rectangle:=RectangleShape2D.new()
	rectangle.size = Vector2(10,100)
	collider.shape = rectangle
	wall.add_child(collider)
	arena.add_child(wall)
	wall.position = Vector2(45,0)
	await physics_frame
	wave = release(caster)
	wave.advance(0.4)
	check(near.health==500 and push_of(near)==null and wave.threats(near).is_empty(),"real wall occlusion prevents damage, push and receiver threat")
	await reset_case()
	# A hollow annulus, not a repeatedly filled disk or a frame-rate-dependent band.
	for step:float in [1.0/30,1.0/60,1.0/120,0.6]:
		caster = unit("唤魔者",Vector2.ZERO,"Team0")
		near = unit("",Vector2(130,0))
		wave = release(caster)
		while not wave.is_queued_for_deletion(): wave.advance(step)
		check(near.health==492,"continuous sweep hits exactly once with timestep "+str(step))
		await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	wave = release(caster)
	wave.advance(0.3)
	near = unit("",Vector2.ZERO)
	wave.advance(0.1)
	check(near.health==500,"entering already-passed interior cannot be hit by filled-circle approximation")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	wave = release(caster)
	wave.advance(0.30)
	var cactus:Node2D = unit("仙人掌",Vector2.ZERO)
	cactus.levels = 3
	cactus.apply_height()
	var cactus_health:int = cactus.health
	wave.advance(0.05)
	check(cactus.health==cactus_health and wave.hit_ids.is_empty(),"coarse multi-part candidate inside the hollow center consumes no hit eligibility")
	cactus.global_position = Vector2(115,0)
	wave.advance(0.10)
	check(cactus.health==cactus_health-8 and wave.hit_ids.size()==1,"real multi-part body later crossing the front takes only one target hit")
	wave.advance(0.13)
	check(cactus.health==cactus_health-8,"another cactus segment cannot repeat damage from the same wave")
	await reset_case()
	caster = unit("唤魔者",Vector2.ZERO,"Team0")
	near = unit("",Vector2(90,0))
	wave = release(caster)
	arena.remove_child(caster)
	wave.advance(0.7)
	check(near.health==500 and wave.is_queued_for_deletion(),"detached but not yet freed owner leaves only a bounded harmless visual")
	caster.free()
	await reset_case()
	await finish()
