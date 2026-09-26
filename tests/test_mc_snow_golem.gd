extends SceneTree
const GOLEM_PATH:String = "res://scenes/characters/我的世界/雪傀儡.tscn"
const MINI_PATH:String = "res://scenes/creatures/我的世界/小雪人.tscn"
var COLD:Script
var FIELD:Script
var world:Node
var game:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var done:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func spawn(path:String,point:Vector2,team:String = "Team0") -> Node2D:
	var unit:Node2D = load(path).instantiate()
	unit.Team = team
	unit.position = point
	world.add_child(unit,true)
	unit.state_machine.set_physics_process(false)
	return unit
func dummy(point:Vector2,team:String = "Team1") -> Node2D:
	var unit:Node2D = spawn("res://scenes/ball.tscn",point,team)
	unit.Has_Collision_Damage = false
	unit.self_hitbox.monitoring = false
	unit.Can_Attack = false
	unit.Can_Skill = false
	unit.Health_Restore = 0
	unit.Max_health = 10000
	unit.default_properties.Max_health = 10000
	unit.health = 10000
	return unit
func setup_world() -> Vector2:
	game = root.get_node("Game")
	COLD = load("res://scripts/characters/我的世界/snow_golem/cold.gd")
	FIELD = load("res://scripts/characters/我的世界/snow_golem/snow_field.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	return FIELD.point_at(FIELD.cell_at(world.return_map_world_rect(world.map_group["Map50x50"]).get_center()))
func clear_cold(target:Node2D) -> void:
	var cold:Node = target.get_node_or_null("MCSnowCold")
	if is_instance_valid(cold): cold.free()
func freeze_snow_units() -> void:
	for unit:Node in get_nodes_in_group("MCSnowGolem"): unit.state_machine.set_physics_process(false)
func park_contact(field:Node2D,target:Node2D,point:Vector2) -> void:
	target.global_position = point
	field._positions[target.get_instance_id()] = point
	field._damage_until.erase(target.get_instance_id())
func new_mini(before:Array) -> Node2D:
	for unit:Node in get_nodes_in_group("MCSnowGolem"):
		if unit.miniature and not unit in before: return unit as Node2D
	return null
func finish(code:int) -> void:
	if done: return
	done = true
	print("SNOW GOLEM RESULT: ",checks-failures,"/",checks," passed")
	if is_instance_valid(world) and is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.set_process(false)
	var warmer:Script = load("res://scripts/effects/我的世界/mc_native_prewarm.gd")
	for role:String in warmer.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var state:int = ResourceLoader.load_threaded_get_status(path)
		if state in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	if is_instance_valid(world): world.queue_free()
	await process_frame
	if game != null:
		game.Game_Settings = saved
		game.now_stop_state = saved_stop
	quit(code)

func check_prewarm() -> void:
	var warm:Node = world._mc_prewarmer
	warm.set_process(false)
	# Finish the world's already requested resource loads, then exercise just
	# the new character's real preparation branch (no actor instantiation).
	for role:String in warm.CHARACTERS:
		var path:String = "res://scenes/characters/我的世界/"+role+".tscn"
		var state:int = ResourceLoader.load_threaded_get_status(path)
		if state in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED]: ResourceLoader.load_threaded_get(path)
	for job:Variant in warm._jobs:
		if job is Node and is_instance_valid(job): job.free()
	warm._jobs.clear()
	if is_instance_valid(warm._visual): warm._visual.queue_free()
	warm._visual = null
	warm._paths = {"雪傀儡":GOLEM_PATH}
	warm.finished.clear()
	warm.failed.clear()
	warm._seen.clear()
	warm._active = ""
	warm._wait_frames = 0
	check(ResourceLoader.load_threaded_request(GOLEM_PATH,"PackedScene") == OK,"Snow Golem resource prewarm request succeeds")
	for i:int in range(400):
		warm._process(0.016)
		if warm.is_ready("雪傀儡") or warm.has_failed("雪傀儡"): break
		await process_frame
	check(warm.is_ready("雪傀儡") and warm.scenes.has("小雪人") and warm.scenes.has("雪球") and warm.scenes.has("雪傀儡雪地"),"production prewarm prepares the actor, child, snowball and snow-field scenes")
	check(get_nodes_in_group("MCSnowGolem").is_empty() and not world.has_node("MCSnowField"),"prewarming creates no real actors, terrain, attacks or summon gameplay")

func run() -> void:
	var center:Vector2 = await setup_world()
	await check_prewarm()
	create_timer(50.0).timeout.connect(func(): finish(2))
	var golem:Node2D = spawn(GOLEM_PATH,center)
	var enemy:Node2D = dummy(center+Vector2(96,0))
	var field:Node2D = golem._field
	field.set_physics_process(false)
	await physics_frame
	await process_frame
	check(golem.get_script().resource_path.ends_with("snow_golem.gd"),"production scene loads the Snow Golem script")
	check(golem.health == 360 and golem.Damage == 9 and golem.Attack_Cooling == 2.0,"baseline stats (9 damage, 2s cooldown) are wired into the actual scene")
	world._ensure_character_path_index()
	check(world._character_paths_by_folder["我的世界"].has("雪傀儡"),"Snow Golem is indexed in the Minecraft selection category")
	var translations:Script = load("res://global/translation_catalog.gd")
	check(translations.TABLE.en.get("雪傀儡") == "Snow Golem" and translations.TABLE.en.has("小雪人"),"both character names have export-safe English translations")
	check(golem.PUMPKIN[1] != golem.BARE[1] and golem.PUMPKIN[1].get_size() == Vector2(160,224),"native pumpkin and bare-face textures are separate, consistently anchored renders")
	check(field.is_in_group("BattleTransient"),"snow grid participates in ordinary battle cleanup")
	var sounds:Script = load("res://scripts/characters/我的世界/snow_golem/native_sounds.gd")
	var decoded:bool = true
	for event:String in sounds.EVENTS:
		for record:Dictionary in sounds.EVENTS[event]: decoded = decoded and record.stream.get_length() > 0.0 and record.stream.resource_path.ends_with(".ogg")
	check(decoded and sounds.EVENTS.has("entity.snow_golem.shoot") and sounds.EVENTS.has("entity.snow_golem.shear"),"all native sound events decode, including snowball launch and pumpkin removal")
	check(golem.Hit_Audio.is_empty() and golem.Dead_Audio.is_empty() and golem.Collide_Audio.is_empty(),"generic non-Minecraft impact/death/collision sounds are disabled")

	# Full, tile-aligned trail and one shared damage interval per victim.
	golem.lay_trail()
	var start_cell:Vector2i = FIELD.cell_at(center)
	check(field.patches.has(start_cell) and field.patches[start_cell].level == 2 and FIELD.CELL == 24.0,"normal trail occupies one complete map-sized snow tile")
	golem.global_position = center+Vector2(48,0)
	golem.lay_trail()
	check(field.patches.has(start_cell+Vector2i.RIGHT) and field.patches.has(start_cell+Vector2i(2,0)),"movement sweeps fill intermediate snow cells without gaps")
	var count:int = field.patches.size()
	for i:int in range(12): golem.lay_trail()
	check(field.patches.size() == count,"standing still does not manufacture additional trail entries")
	park_contact(field,enemy,center)
	var hp:int = enemy.health
	field.advance(0.01)
	check(enemy.health == hp-3,"enemy entering full snow receives the low periodic damage")
	var cold:Node2D = enemy.get_node_or_null("MCSnowCold")
	check(is_instance_valid(cold) and is_equal_approx(cold.amount,8.0),"full snow also adds cold")
	cold.set_physics_process(false)
	field.advance(0.2)
	check(enemy.health == hp-3,"snow does not damage again before its half-second interval")
	field.advance(0.31)
	check(enemy.health == hp-6,"remaining on snow repeatedly damages at the configured interval")
	var allied:Node2D = dummy(center,"Team0")
	field.advance(0.6)
	check(allied.health == 10000 and not allied.has_node("MCSnowCold"),"allied walkers do not receive damage or cold")
	allied.queue_free()
	clear_cold(enemy)

	# Little snowman: harmless half-size tile, genuine re-entry completes it.
	field.patches.clear()
	var small_point:Vector2 = center+Vector2(-96,0)
	var mini:Node2D = spawn(MINI_PATH,small_point)
	mini.family = golem.family
	mini.set_meta("mc_snow_family",golem.family)
	mini.lay_trail()
	var small_cell:Vector2i = FIELD.cell_at(small_point)
	check(mini.health == 150 and mini.Damage == golem.Damage and mini.Speed == golem.Speed and mini.snowball_knockback == golem.snowball_knockback and mini.global_scale.x < golem.global_scale.x,"mini keeps only lower HP/smaller body, with matching combat values")
	check(field.patches[small_cell].level == 1,"little snowman initially leaves a half-size patch")
	for i:int in range(30): mini.lay_trail()
	check(field.patches[small_cell].level == 1,"stationary mini cannot upgrade its own patch every frame")
	park_contact(field,enemy,small_point)
	hp = enemy.health
	field.advance(0.6)
	check(enemy.health == hp and not enemy.has_node("MCSnowCold"),"half-size snow causes neither damage nor cold")
	mini.global_position += Vector2(24,0)
	mini.lay_trail()
	mini.global_position = small_point
	mini.lay_trail()
	check(field.patches[small_cell].level == 2,"a real leave-and-return pass completes the mini's snow tile")
	field.advance(0.6)
	check(enemy.health == hp-3 and is_instance_valid(enemy.get_node_or_null("MCSnowCold")),"completed mini snow uses the same full-tile damage and cold as normal snow")
	clear_cold(enemy)
	field.patches.clear()
	park_contact(field,enemy,center+Vector2(160,96))

	# Shared cold meter, progressive slow/tint/particles, reset and independent lock.
	cold = COLD.ensure(enemy)
	cold.add_cold(25.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	var low_ratio:float = cold.speed_ratio()
	var low_rate:float = cold.particle_rate()
	cold._process(0.4)
	var low_particles:int = cold.particles.size()
	check(cold.amount == 25.0 and low_ratio < 1.0 and cold._last_tint > 0.0,"initial cold produces a real slow and a snow-color shader channel")
	var low_attack:float = cold.attack_speed_ratio()
	check(low_attack < 1.0 and low_attack > 0.5 and is_equal_approx(cold.attack_cooling_ratio(),1.0/low_attack),"initial cold already slows attacks a little")
	cold.add_cold(50.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	cold._process(0.4)
	check(cold.speed_ratio() < low_ratio and cold.particle_rate() > low_rate and cold.particles.size() > low_particles,"more cold increases slow strength and the actual emitted snowflake count")
	check(cold.attack_speed_ratio() < low_attack,"more cold slows attacks further")
	check(cold._last_tint == 0.75 and COLD.ensure(enemy) == cold,"all cold sources share one meter and whitening intensity")
	enemy.restore_default_runtime_properties_fast()
	var base_speed:float = enemy.Speed
	var base_cooling:float = enemy.Attack_Cooling
	var base_reduction:float = enemy.Damage_reduction
	world.figure_buffs(0.0,[enemy])
	check(is_equal_approx(enemy.Speed,base_speed*cold.speed_ratio()),"slow is applied by the real World buff pipeline without changing base stats")
	check(is_equal_approx(enemy.Attack_Cooling,base_cooling*cold.attack_cooling_ratio()) and enemy.Attack_Cooling > base_cooling,"attack cooldown is lengthened by the real World buff pipeline in proportion to cold")
	check(is_equal_approx(enemy.Damage_reduction,base_reduction),"unfrozen cold does not change incoming damage")
	cold.add_cold(25.0,1.4)
	cold.set_physics_process(false)
	cold.set_process(false)
	check(cold.amount == 0.0 and is_equal_approx(cold.frozen_left,1.4) and enemy.dizziness,"full meter is cleared and the victim is actually frozen")
	var frozen_buffs:Dictionary = enemy.Buff_Dic.get(cold.get_instance_id(),{})
	check(not frozen_buffs.has(COLD.BUFF_KEY) and not frozen_buffs.has(COLD.ATTACK_BUFF_KEY),"threshold clears the accumulated speed/attack debuffs rather than leaving a permanent slow")
	check(frozen_buffs.has(COLD.VULN_BUFF_KEY),"freezing installs the vulnerability debuff")
	enemy.restore_default_runtime_properties_fast()
	world.figure_buffs(0.0,[enemy])
	check(is_equal_approx(1.0-enemy.Damage_reduction,(1.0-base_reduction)*COLD.FREEZE_DAMAGE_MULTIPLIER),"frozen victim's effective incoming damage factor is doubled")
	var frozen_hp:int = enemy.health
	enemy.receive_positional_damage(10.0,enemy.global_position,true,null)
	check(enemy.health == frozen_hp-20,"a 10-point hit on a frozen victim removes 20 health")
	enemy.restore_default_runtime_properties_fast()
	check(is_equal_approx(enemy.Damage_reduction,base_reduction),"vulnerability is a runtime buff, not a permanent stat change")
	check(not cold.add_cold(100.0,1.4) and cold.freeze_count == 1,"cold during a freeze cannot immediately refill or indefinitely refresh it")
	game.now_stop_state = true
	var frozen:float = cold.frozen_left
	var flake_point:Vector2 = cold.particles[0].point
	var paused_hp:int = enemy.health
	cold.advance(5.0)
	cold._process(5.0)
	check(cold.frozen_left == frozen and cold.particles[0].point == flake_point and enemy.health == paused_hp,"pause freezes status duration, particle motion and freeze damage")
	game.now_stop_state = false
	paused = true
	cold.advance(5.0)
	check(cold.frozen_left == frozen,"SceneTree pause also cannot consume the freeze duration")
	paused = false
	var other_lock:Node = enemy.apply_stun(3.0)
	other_lock.set_physics_process(false)
	var tick_hp:int = enemy.health
	enemy.max_block = 50
	enemy.block = 50
	world.figure_buffs(0.0,[enemy])
	cold.advance(COLD.FREEZE_TICK_INTERVAL*0.5)
	check(enemy.health == tick_hp,"freeze damage waits for its tick interval")
	cold.advance(COLD.FREEZE_TICK_INTERVAL*0.51)
	check(enemy.health == tick_hp-int(COLD.FREEZE_TICK_DAMAGE*COLD.FREEZE_DAMAGE_MULTIPLIER) and enemy.block == 50,"each freeze tick bites through block for doubled damage")
	enemy.block = 0
	enemy.max_block = 0
	var ticks_before:float = cold.freeze_damage_dealt
	cold.advance(1.5)
	cold._process(0.0)
	check(cold.freeze_damage_dealt > ticks_before,"freeze keeps ticking damage until it thaws")
	check(cold.frozen_left == 0.0 and enemy.dizziness,"thaw releases only the snow lock, preserving another active stun")
	check(cold._last_tint == 0.0,"thaw clears only the snow tint channel")
	check(not enemy.Buff_Dic.has(cold.get_instance_id()),"thaw removes the vulnerability debuff")
	var thawed_hp:int = enemy.health
	cold.advance(1.0)
	check(enemy.health == thawed_hp,"no freeze damage after thawing")
	other_lock.free()
	check(not enemy.dizziness and not enemy.has_meta("generic_motion_lock_count"),"last independent control lock restores the original movement state")
	enemy.negative_effect_ratio = 0.0
	check(not cold.add_cold(100.0,1.4) and cold.amount == 0.0,"negative-effect immunity rejects cold and freezing")
	enemy.negative_effect_ratio = 1.0
	clear_cold(enemy)

	# Real half-health damage hook, falling head, snow absorption and one birth.
	golem.global_position = center+Vector2(120,-72)
	golem.direction = Vector2.RIGHT
	var landing:Vector2i = field.choose_drop_cell(golem)
	check(field.deposit(golem,landing,false),"fixture lays real snow beneath the predicted pumpkin landing cell")
	golem.take_damage(179.0,true)
	check(golem.health == 181 and golem.has_pumpkin and golem.head_drop_count == 0,"pumpkin remains above the half-health threshold")
	golem.take_damage(1.0,true)
	check(golem.health == 180 and not golem.has_pumpkin and golem.head_drop_count == 1,"actual damage crossing exactly half HP drops the pumpkin once")
	var head_id:int = field._serial
	check(field.heads[head_id].blocks == 0 and not field.heads[head_id].landed,"pumpkin first flies to the floor instead of instantly becoming a minion")
	check(golem.image.texture in golem.BARE,"headless parent reveals the original snow face")
	game.now_stop_state = true
	field.advance(1.0)
	check(field.heads[head_id].elapsed == 0.0,"pause also stops the falling pumpkin")
	game.now_stop_state = false
	field.advance(0.33)
	check(field.heads[head_id].landed and field.heads[head_id].blocks == 1 and not field.patches.has(landing),"landing absorbs exactly that snow cell into one snow block below the head")
	golem.heal(500.0)
	golem.take_damage(200.0,true)
	check(golem.head_drop_count == 1,"healing and crossing half HP again cannot duplicate a lost head")
	golem._trail_started = false
	golem.global_position = FIELD.point_at(landing)+Vector2(24,0)
	golem.lay_trail()
	var before_birth:Array = get_nodes_in_group("MCSnowGolem")
	golem.global_position = FIELD.point_at(landing)
	golem.lay_trail()
	check(field.heads[head_id].blocks == 2 and field.heads[head_id].pending,"another snow-laying pass reaches two blocks and schedules a birth")
	check(not field.deposit(golem,landing,false) and not field.patches.has(landing),"pending pumpkin cannot be double-built or generate an extra free snow tile")
	for i:int in range(20): golem.lay_trail()
	await process_frame
	await physics_frame
	freeze_snow_units()
	var child:Node2D = new_mini(before_birth)
	check(is_instance_valid(child) and not field.heads.has(head_id),"two blocks consume the pumpkin stack and create one real mini scene")
	check(get_nodes_in_group("MCSnowGolem").size() == before_birth.size()+1,"repeated same-frame checks cannot duplicate the mini")
	if is_instance_valid(child):
		check(child.Team == golem.Team and child.family == golem.family and child.Master == null,"mini inherits the family and team but has no parent-lifetime dependency")
		check(child.get_meta("battle_continuation_victory_side_key") == golem.get_meta("battle_continuation_victory_side_key") and child.is_in_group("BattleTransient"),"offspring retain the battle side and participate in cleanup")

	# Dry ground needs two later passes; a mini itself also loses its own head.
	field.patches.clear()
	mini.global_position = center+Vector2(-144,-96)
	mini.direction = Vector2.RIGHT
	mini.take_damage(75.0,true)
	var dry_id:int = field._serial
	field.advance(0.4)
	check(not mini.has_pumpkin and mini.head_drop_count == 1 and field.heads[dry_id].blocks == 0,"mini keeps the same half-health rule; dry landing is just one pumpkin block")
	var dry_point:Vector2 = field.heads[dry_id].point
	mini._trail_started = false
	mini.global_position = dry_point+Vector2(24,0)
	mini.lay_trail()
	mini.global_position = dry_point
	mini.lay_trail()
	check(field.heads[dry_id].blocks == 1 and not field.heads[dry_id].pending,"first later pass adds exactly one snow block under a dry pumpkin")
	for i:int in range(20): mini.lay_trail()
	check(field.heads[dry_id].blocks == 1,"remaining on the pumpkin cannot instantly create its second block")
	before_birth = get_nodes_in_group("MCSnowGolem")
	mini.global_position = dry_point+Vector2(24,0)
	mini.lay_trail()
	mini.global_position = dry_point
	mini.lay_trail()
	await process_frame
	freeze_snow_units()
	check(get_nodes_in_group("MCSnowGolem").size() == before_birth.size()+1 and not field.heads.has(dry_id),"second later pass works for a mini too and creates exactly one descendant")
	var grandchild:Node2D = new_mini(before_birth)
	check(is_instance_valid(grandchild) and grandchild.Max_health == 150 and grandchild.Damage == mini.Damage and grandchild.global_scale == mini.global_scale and grandchild.has_pumpkin,"later generations keep the fixed mini form instead of recursively shrinking or losing their pumpkin mechanic")
	if is_instance_valid(child):
		var survivor:WeakRef = weakref(child)
		golem.queue_free()
		await process_frame
		check(is_instance_valid(survivor.get_ref()) and child.health > 0,"existing mini survives removal of the original parent")

	# Production projectile: cooldown, swept contact, cold, slight knockback and walls.
	field.patches.clear()
	clear_cold(enemy)
	var shooter:Node2D = spawn(GOLEM_PATH,center)
	park_contact(field,enemy,center+Vector2(100,0))
	shooter._shot_left = 0.0
	check(shooter.fire_at(enemy.global_position) and not shooter.fire_at(enemy.global_position),"snowball attack fires once and enforces its slow cooldown")
	var shot:Node2D
	for node:Node in get_nodes_in_group("MCSnowball"):
		if node.Master == shooter: shot = node
	check(is_instance_valid(shot) and shot.cold_gain == 22.0 and shot.snow_knockback == 8.0,"real projectile carries cold and small knockback parameters")
	if is_instance_valid(shot):
		shot.state_machine.set_physics_process(false)
		hp = enemy.health
		shot.move(260.0,0.7)
		check(enemy.health == hp-9 and shot._spent,"swept snowball contact deals its damage once, even across a long frame")
		cold = enemy.get_node_or_null("MCSnowCold")
		check(is_instance_valid(cold) and cold.amount == 22.0,"snowball hit adds its cold amount through the shared status")
		var knocked:bool = false
		for effect:Node in enemy.get_children():
			if effect.get_script() != null and effect.get_script().resource_path.ends_with("knockback_effect.gd"): knocked = is_equal_approx(float(effect.distance),8.0)
		check(knocked,"snowball uses the existing physical knockback controller for an eight-pixel push")
	await process_frame
	var wall := StaticBody2D.new()
	wall.set_meta("mc_wall",true)
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10,100)
	collider.shape = rectangle
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = center+Vector2(40,0)
	await physics_frame
	await process_frame
	shooter._shot_left = 0.0
	check(not shooter.fire_at(enemy.global_position),"normal targeting cannot shoot through a wall")
	shooter._spawn_snowball("SnowWallProbe",center,Vector2.RIGHT,6.0)
	shot = world.get_node("SnowWallProbe")
	shot.state_machine.set_physics_process(false)
	hp = enemy.health
	shot.move(260.0,0.7)
	check(shot._spent and enemy.health == hp and shot.global_position.x < enemy.global_position.x,"already airborne snowball stops at terrain before a target behind it")
	wall.queue_free()
	await process_frame
	# Defense and immunity go through the production hurtbox/hit callback.
	clear_cold(enemy)
	enemy.max_block = 100
	enemy.block = 100
	shooter._spawn_snowball("SnowShieldProbe",center,Vector2.RIGHT,6.0)
	shot = world.get_node("SnowShieldProbe")
	shot.state_machine.set_physics_process(false)
	hp = enemy.health
	shot.move(260.0,0.7)
	check(enemy.health == hp and enemy.block == 94 and shot._spent,"shield absorbs the snowball through the normal ranged-block contract")
	check(not enemy.has_node("MCSnowCold"),"a fully shielded snowball cannot apply cold through its blocked damage")
	enemy.max_block = 0
	enemy.block = 0
	enemy.negative_effect_ratio = 0.0
	shooter._spawn_snowball("SnowImmuneProbe",center,Vector2.RIGHT,9.0)
	shot = world.get_node("SnowImmuneProbe")
	shot.state_machine.set_physics_process(false)
	hp = enemy.health
	shot.move(260.0,0.7)
	check(enemy.health == hp-9 and not enemy.has_node("MCSnowCold"),"negative-effect immune victim still takes snowball damage but receives no cold or freeze component")
	enemy.negative_effect_ratio = 1.0

	# Family identity also works without colored teams.
	var family_point:Vector2 = center+Vector2(168,144)
	var solo_parent:Node2D = spawn(GOLEM_PATH,family_point,"")
	var solo_child:Node2D = spawn(MINI_PATH,family_point,"")
	solo_child.family = solo_parent.family
	solo_child.set_meta("mc_snow_family",solo_parent.family)
	var solo_enemy:Node2D = dummy(family_point,"")
	solo_parent.lay_trail()
	field.advance(0.6)
	check(solo_child.health == 150 and not solo_child.has_node("MCSnowCold"),"unteamed relatives are not damaged or chilled by their family's terrain")
	check(solo_enemy.health == 9997 and solo_enemy.has_node("MCSnowCold"),"a different unteamed combatant is still an enemy of that same snow family")
	var sound:AudioStreamPlayer2D = shooter.SNOW_AUDIO.play(shooter,"entity.snow_golem.hurt",center,-10.0)
	# AudioStreamPlayer2D starts its spatial playback on the following physics step.
	await physics_frame
	await process_frame
	check(is_instance_valid(sound) and sound.playing,"native sound is actually playing before the pause test")
	game.now_stop_state = true
	field._process(0.0)
	check(is_instance_valid(sound) and sound.stream_paused,"native audio pool pauses existing snow sounds during the gameplay pause")
	game.now_stop_state = false
	field._process(0.0)
	check(is_instance_valid(sound) and not sound.stream_paused,"native audio resumes without spawning substitute sound effects")
	shooter._spawn_snowball("SnowPauseProbe",center,Vector2.UP,6.0)
	shot = world.get_node("SnowPauseProbe")
	shot.state_machine.set_physics_process(false)
	var life_before:float = shot.life
	game.now_stop_state = true
	shot.tick_physics(0,2.0)
	check(shot.life == life_before and not shooter.fire_at(center+Vector2(20,0)),"pause stops projectile lifetime and new attacks")
	game.now_stop_state = false
	var capture:Script = load("res://scripts/characters/我的世界/allay/capture.gd")
	check(not capture.describe(shot).is_empty(),"new snowball is explicitly compatible with Allay's native projectile capture")
	var native:Dictionary = capture.NATIVE_RETURN.snapshot(shot,capture.describe(shot))
	check(native.native_properties.cold_gain == 22.0 and native.native_properties.freeze_duration == 1.4,"native return snapshot preserves snowball status parameters")
	shooter.apply_damage_disable(5.0)
	shooter._shot_left = 0.0
	check(not shooter.fire_at(enemy.global_position),"damage-output disable prevents firing new snowballs")
	capture.discard(shot)
	check(shot.is_queued_for_deletion(),"capture consumes the projectile without invoking cold or hit callbacks")
	# Use the actual public reset, not a test-only group deletion shortcut.
	var field_ref:WeakRef = weakref(field)
	var mini_refs:Array[WeakRef] = []
	for unit:Node in get_nodes_in_group("MCSnowGolem"):
		if unit.miniature: mini_refs.append(weakref(unit))
	var victim_cold:Node = COLD.ensure(enemy)
	victim_cold.add_cold(100.0,1.4)
	var cold_ref:WeakRef = weakref(victim_cold)
	world.reset()
	await process_frame
	await process_frame
	check(not is_instance_valid(field_ref.get_ref()) and not has_group("MCSnowField"),"ordinary battle reset removes the shared snow grid and all pumpkins")
	var no_minis:bool = true
	for reference:WeakRef in mini_refs: no_minis = no_minis and not is_instance_valid(reference.get_ref())
	check(no_minis and get_nodes_in_group("MCSnowGolem").is_empty(),"ordinary reset removes normal actors and every autonomous descendant")
	check(not is_instance_valid(cold_ref.get_ref()) and get_nodes_in_group("MCSnowCold").is_empty(),"ordinary reset removes cold components, their buffs, particles and control locks")
	check(get_nodes_in_group("MCSnowball").is_empty() and get_nodes_in_group("MCSnowSound").is_empty(),"ordinary reset leaves no snow projectiles or sound players behind")
	var retired:Node2D = FIELD.ensure(world)
	retired.queue_free()
	var replacement:Node2D = FIELD.ensure(world)
	check(replacement != retired and str(replacement.name) == "MCSnowField","same-frame reset/recreation preserves one stable snow-field path")
	await process_frame
	check(world.get_node_or_null("MCSnowField") == replacement,"queued old field cannot remove or hide the next battle field")
	replacement.queue_free()
	await process_frame
	finish(0 if failures == 0 else 1)
