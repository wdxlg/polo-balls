extends SceneTree
# Independent legs: cadence from real displacement / own standard speed, legs keep
# walking under upper-body actions, legs settle to the rest pose when still.
var game:Node
var world:Node
var saved:Dictionary
var saved_stop:bool
var checks:int = 0
var failures:int = 0
var finishing:bool = false
var LEGS:Script

func _initialize() -> void: call_deferred("run")

func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
	else:
		print("ok  ",label)

func spawn(path:String,point:Vector2) -> Node2D:
	var u:Node2D = load(path).instantiate()
	u.Team = "Team0"
	u.Can_Attack = false
	u.Can_Skill = false
	world.add_child(u,true)
	u.global_position = point
	u.state_machine.set_physics_process(false)
	return u

## Move the unit at `ratio` x its standard speed for `seconds`, stepping the driver.
func walk(u:Node2D,driver:Node,ratio:float,seconds:float,dt:float = 1.0/60.0) -> void:
	var v:float = LEGS.standard_speed(u)*ratio
	var steps:int = int(round(seconds/dt))
	for i:int in range(steps):
		u.global_position.x += v*dt
		driver.advance(dt)

func idle(driver:Node,seconds:float,dt:float = 1.0/60.0) -> void:
	for i:int in range(int(round(seconds/dt))): driver.advance(dt)

func run() -> void:
	game = root.get_node("Game")
	LEGS = load("res://scripts/effects/我的世界/mc_legs.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Ball_Can_Move = true
	game.Game_Settings.Have_Team_Damage = false
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(180.0).timeout.connect(func(): finish(2))
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(0.4).timeout
	var center:Vector2 = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	var e:Node2D = spawn("res://scenes/characters/我的世界/末影人.tscn",center+Vector2(-300,0))
	var c:Node2D = spawn("res://scenes/characters/我的世界/唤魔者.tscn",center+Vector2(0,0))
	var target:Node2D = spawn("res://scenes/ball.tscn",center+Vector2(0,400))
	target.Team = "Team1"
	target.health = 100000
	await process_frame
	await process_frame
	var ea:Node = e.mc_native_animation
	var ca:Node = c.mc_native_animation
	check(is_instance_valid(ea) and ea.ready_visual and is_instance_valid(ca) and ca.ready_visual,"drivers ready")
	if not (is_instance_valid(ea) and ea.ready_visual and is_instance_valid(ca) and ca.ready_visual):
		finish(1)
		return
	ea.set_process(false)
	ca.set_process(false)
	check(ea.legs_key == "enderman" and ca.legs_key == "evoker","baked leg layers found")
	var g:RefCounted = ea.gait
	var data:Variant = LEGS.layer_data("enderman")
	check(data != null and int(data.WALK) == 24 and (data.NEUTRAL as Array).size() == 2,"enderman layer data: 24 phases, 2 neutral phases")
	# standard speed = own base Speed x 0.6 actual move multiplier
	check(is_equal_approx(LEGS.standard_speed(e),float(e.default_properties.Speed)*0.6),"standard speed = own base speed x 0.6")
	# --- rest
	check(g.at_rest and ea.current_clip == &"idle","starts at rest on idle clip")
	# --- 1x standard speed for one cycle returns to the same phase after a full stride
	var start_phase:float = g.phase
	var seen:Dictionary = {}
	var v:float = LEGS.standard_speed(e)
	for i:int in range(60):
		e.global_position.x += v/60.0
		ea.advance(1.0/60.0)
		seen[g.walk_index(24)] = true
	check(ea.current_clip == &"walk","moving selects walk")
	check(absf(wrapf(g.phase-start_phase,-0.5,0.5)) < 0.02,"1x standard speed: one walk cycle per walk-clip duration (phase %.3f -> %.3f)" % [start_phase,g.phase])
	check(seen.size() >= 22,"1x: walk frames advance through the cycle (%d distinct)" % seen.size())
	# --- 2x speed: half the time for one full cycle; 0.5x: half a cycle in the same time
	var p0:float = g.phase
	walk(e,ea,2.0,0.5)
	check(absf(wrapf(g.phase-p0,-0.5,0.5)) < 0.02,"2x speed: full cycle in half the time")
	p0 = g.phase
	walk(e,ea,0.5,1.0)
	check(absf(absf(wrapf(g.phase-p0,-0.5,0.5))-0.5) < 0.02,"0.5x speed: half a cycle per walk-clip duration")
	p0 = g.phase
	walk(e,ea,1.5,0.4)
	check(absf(fposmod(g.phase-p0,1.0)-0.6) < 0.02,"1.5x speed: 0.6 cycle in 0.4 s")
	# --- stop: legs settle into a neutral pose, then idle
	walk(e,ea,1.0,0.13)
	idle(ea,0.8)
	var neutral_ok:bool = false
	for n:float in g.neutral: neutral_ok = neutral_ok or absf(g.phase-n) < 0.0005
	check(g.at_rest and neutral_ok,"stopped: legs return to a neutral (rest) phase")
	check(ea.current_clip == &"idle","stopped: back to idle pose")
	# --- attack while walking: legs keep walking under the attack upper body
	walk(e,ea,1.0,0.2)
	ea._on_contact_attack(target.self_hurtbox)
	ea.advance(0.0)
	var textures:Dictionary = {}
	var attack_indices:Dictionary = {}
	var legs_seen:Dictionary = {}
	for i:int in range(18):
		e.global_position.x += v/60.0
		ea.advance(1.0/60.0)
		if ea.current_clip == &"attack":
			textures[e.image.texture.get_rid()] = true
			attack_indices[ea.frame_index] = true
			legs_seen[ea._leg_index] = true
	check(ea.current_clip == &"attack","attack clip active while moving")
	check(legs_seen.size() >= 6 and not legs_seen.has(-1),"legs keep cycling during the attack (%d leg phases)" % legs_seen.size())
	check(textures.size() >= 6,"composited frames change while attacking and walking")
	var comp:Texture2D = e.image.texture
	var original:Texture2D = ea.frames.get_frame_texture(&"attack",ea.frame_index)
	check(comp != original and comp.get_size() == original.get_size(),"composite replaces the frozen-leg attack frame at same canvas size")
	var cached:Variant = LEGS.cached_source_image(comp)
	check(cached is Image and (cached as Image).get_size() == Vector2i(original.get_size()),"composite registered in after-image cache")
	# upper body identical to the attack frame above the hips, legs differ below
	var a_img:Image = original.get_image() if DisplayServer.get_name() != "headless" else null
	if a_img != null:
		var c_img:Image = cached
		var top_same:bool = true
		for y:int in range(40,110):
			for x:int in range(0,160,3):
				if a_img.get_pixel(x,y).a8 != c_img.get_pixel(x,y).a8: top_same = false
		check(top_same,"upper body pixels kept from the attack frame")
	# --- attack while standing still: original attack frame (legs at rest)
	idle(ea,1.0)
	check(g.at_rest,"stood still")
	ea._on_contact_attack(target.self_hurtbox)
	ea.advance(1.0/60.0)
	ea.advance(1.0/60.0)
	check(ea.current_clip == &"attack" and ea._leg_index == -1 and e.image.texture == ea.frames.get_frame_texture(&"attack",ea.frame_index),"attack while still uses the original rest-leg frame")
	# --- evoker cast while walking
	var cg:RefCounted = ca.gait
	var cv:float = LEGS.standard_speed(c)
	for i:int in range(20):
		c.global_position.y += cv/60.0
		ca.advance(1.0/60.0)
	ca.trigger_cast(0.65)
	var cast_legs:Dictionary = {}
	for i:int in range(24):
		c.global_position.y += cv/60.0
		ca.advance(1.0/60.0)
		if ca.current_clip == &"cast": cast_legs[ca._leg_index] = true
	check(ca.current_clip == &"cast" and cast_legs.size() >= 8 and not cast_legs.has(-1),"evoker casts with walking legs (%d phases)" % cast_legs.size())
	idle(ca,1.2)
	check(cg.at_rest and ca.current_clip == &"idle","evoker rests after cast + stop")
	# --- second wave: spider / drowned (mc_native_animation) + witch / skeleton / creeper (batch2)
	await action_suite(center)
	await pair_suite(center)
	await warden_suite(center)
	await trader_suite(center)
	await wither_suite(center)
	await vindicator_suite(center)
	# --- cache bound
	var cache:Dictionary = LEGS._cache.get("enderman",{})
	check(cache.is_empty() or (cache["order"] as Array).size() <= LEGS.CACHE_PER_SET,"composite cache bounded")
	finish(0 if failures == 0 else 1)

func driver_of(u:Node) -> Node:
	var d:Variant = u.get("mc_native_animation")
	if d is Node and is_instance_valid(d): return d
	return u.get_node_or_null("MinecraftNativeAnimation")

## Walk with `hold` re-applied every step (scripts may clear their own action flags).
func walk_hold(u:Node2D,d:Node,ratio:float,frames_n:int,hold:Callable,want:StringName) -> Dictionary:
	var v:float = LEGS.standard_speed(u)*ratio
	var out:Dictionary = {"legs":{},"tex":{},"clip_ok":0,"cached":0}
	for i:int in range(frames_n):
		hold.call()
		u.global_position.x += v/60.0
		d.advance(1.0/60.0)
		if d.current_clip == want:
			out.clip_ok += 1
			out.legs[d._leg_index] = true
			out.tex[u.image.texture.get_rid()] = true
			if LEGS.cached_source_image(u.image.texture) != null: out.cached += 1
	return out

func still_hold(u:Node2D,d:Node,frames_n:int,hold:Callable) -> void:
	for i:int in range(frames_n):
		hold.call()
		d.advance(1.0/60.0)

func action_suite(center:Vector2) -> void:
	var specs:Array = [
		["spider","res://scenes/characters/我的世界/蜘蛛.tscn",&"cast"],
		["drowned","res://scenes/characters/我的世界/溺尸.tscn",&"throw"],
		["witch","res://scenes/characters/我的世界/女巫.tscn",&"drink"],
		["skeleton","res://scenes/characters/我的世界/骷髅.tscn",&"shoot"],
		["creeper","res://scenes/characters/我的世界/苦力怕.tscn",&"fuse"],
	]
	var row:float = -600.0
	for spec:Array in specs:
		var key:String = spec[0]
		var want:StringName = spec[2]
		var u:Node2D = spawn(spec[1],center+Vector2(-500,row))
		row += 260.0
		await process_frame
		await process_frame
		var d:Node = driver_of(u)
		check(d != null and d.ready_visual and d.legs_key == key,"%s: driver ready with leg layers" % key)
		if d == null or not d.ready_visual: continue
		d.set_process(false)
		check(u.image is Sprite2D,"%s: Sprite2D presentation (composites can be shown)" % key)
		var hold:Callable
		match key:
			"spider": hold = func(): d._cast_left = 0.5
			"drowned": hold = func():
				u.set("has_trident",true)
				d._action_clip = &"throw"
				d._action_left = 0.4
			"witch": hold = func(): u.set("_action_busy",true)
			"skeleton": hold = func(): d._shoot_left = 0.5
			"creeper": hold = func():
				u.set("_fusing",true)
				u.set("_current_fuse_duration",1.5)
				u.set("_fuse_elapsed",0.9)
		var none:Callable = func(): pass
		walk_hold(u,d,1.0,20,none,&"walk")
		check(d.current_clip in [&"walk",&"walk_empty"],"%s: moving selects walk (%s)" % [key,d.current_clip])
		var r:Dictionary = walk_hold(u,d,1.0,30,hold,want)
		check(r.clip_ok >= 25 and r.legs.size() >= 8 and not r.legs.has(-1),"%s: %s while moving keeps legs walking (%d phases, clip %d/30)" % [key,want,r.legs.size(),r.clip_ok])
		check(r.tex.size() >= 8 and r.cached >= 25,"%s: composited %s frames (%d distinct)" % [key,want,r.tex.size()])
		# stop: legs settle; the action frame then shows the original (rest-leg) pose
		still_hold(u,d,60,hold)
		check(d.gait.at_rest and d.current_clip == want and d._leg_index == -1,"%s: %s while still -> rest legs, original frame" % [key,want])
		var stock:Texture2D = d.hand_frame_record().body if key == "drowned" else d.frames.get_frame_texture(d.current_clip,d.frame_index)
		check(u.image.texture == stock,"%s: still frame is the stock texture" % key)
		if key == "creeper":
			# charged fuse composites with the charged-shell leg variants
			var charged:Callable = func():
				hold.call()
				u.set("_charged",true)
			var rc:Dictionary = walk_hold(u,d,1.0,30,charged,&"fuse_charged")
			check(rc.clip_ok >= 25 and rc.legs.size() >= 8 and not rc.legs.has(-1),"creeper: charged fuse keeps legs walking")
			u.set("_charged",false)
			u.set("_fusing",false)
			# batch2 walk cadence follows speed: 2x speed -> full cycle in half the walk duration
			walk_hold(u,d,1.0,20,none,&"walk")
			var p0:float = d.gait.phase
			walk_hold(u,d,2.0,30,none,&"walk")
			check(absf(wrapf(d.gait.phase-p0,-0.5,0.5)) < 0.02,"creeper: 2x speed -> one full stride in 0.5 s")
		if key == "drowned":
			var rr:Dictionary = walk_hold(u,d,1.0,30,func():
				u.set("has_trident",true)
				d._action_clip = &"catch"
				d._action_left = 0.4,&"catch")
			check(rr.clip_ok >= 25 and rr.legs.size() >= 8 and not rr.legs.has(-1),"drowned: catch while moving keeps legs walking")
		u.queue_free()

## Iron golem / villager pair (pair_base.gd): clip chosen by the scripts, legs by the gait.
func pair_step(u:Node2D,ratio:float,frames_n:int,clip:String,clock:Variant = null) -> Dictionary:
	var v:float = LEGS.standard_speed(u)*ratio
	var out:Dictionary = {"legs":{},"tex":{},"walk_frames":{}}
	for i:int in range(frames_n):
		u.set_pair_clip(clip)
		if clock != null: u.visual_clock = float(clock)
		u.global_position.x += v/60.0
		u._pair_gait().tick(u,1.0/60.0,true)
		u.update_pair_visual()
		out.legs[u._leg_index] = true
		out.tex[u.image.texture.get_rid()] = true
	return out

func pair_suite(center:Vector2) -> void:
	var g:Node2D = spawn("res://scenes/characters/我的世界/铁傀儡.tscn",center+Vector2(400,-500))
	var v:Node2D = spawn("res://scenes/creatures/铁傀儡村民.tscn",center+Vector2(400,-200))
	await process_frame
	await process_frame
	check(g._pair_legs_key() == "golem_0" and v._pair_legs_key() == "villager" and LEGS.layer_data("golem_3") != null and LEGS.layer_data("villager") != null,"pair: leg layer sets for golem stages + villager")
	var gg:RefCounted = g._pair_gait()
	check(absf(gg.cycle-1.0) < 0.001 and gg.neutral.size() == 2,"pair: golem gait = 16-frame / 1 s walk, 2 rest phases")
	# walking: walk frames follow the gait (all 16 visited in one stride at 1x)
	var walk_tex:Dictionary = {}
	for i:int in range(60):
		g.set_pair_clip("walk")
		g.global_position.x += LEGS.standard_speed(g)/60.0
		gg.tick(g,1.0/60.0,true)
		g.update_pair_visual()
		walk_tex[gg.walk_index(16)] = g.image.texture == g.pair_frames.get_frame_texture("walk",gg.walk_index(16))
	check(walk_tex.size() >= 15 and not walk_tex.values().has(false) and g._leg_index == -1,"golem: walk frames driven by gait (%d of 16 indices)" % walk_tex.size())
	# charge + swing while moving: composited, legs keep cycling
	var rc:Dictionary = pair_step(g,1.0,20,"charge",0.2)
	check(rc.legs.size() >= 6 and not rc.legs.has(-1) and rc.tex.size() >= 6,"golem: charging while moving keeps legs walking (%d phases)" % rc.legs.size())
	check(LEGS.cached_source_image(g.image.texture) != null,"golem: charge frame is a leg composite")
	var rs:Dictionary = pair_step(g,1.0,20,"swing",0.3)
	check(rs.legs.size() >= 6 and not rs.legs.has(-1),"golem: swing while moving keeps legs walking")
	# crack stage switches leg set
	g.visual_stage = 2
	g.pair_frames = g.GOLEM_FRAMES[2]
	var r2:Dictionary = pair_step(g,1.0,10,"swing",0.3)
	check(g._pair_legs_key() == "golem_2" and not r2.legs.has(-1),"golem: cracked stage uses its own leg layers")
	# stop: settle -> original charge frame
	for i:int in range(60):
		g.set_pair_clip("charge")
		g.visual_clock = 0.2
		gg.tick(g,1.0/60.0,true)
		g.update_pair_visual()
	check(gg.at_rest and g._leg_index == -1 and g.image.texture == g.pair_frames.get_frame_texture("charge",int(0.2*g.pair_frames.get_animation_speed("charge"))),"golem: charge while still = stock frame")
	# steering into a wall (walk clip, no displacement): legs stand -> idle frame
	for i:int in range(30):
		g.set_pair_clip("walk")
		gg.tick(g,1.0/60.0,true)
		g.update_pair_visual()
	check(g.image.texture == g.pair_frames.get_frame_texture("idle",0),"golem: walk clip without displacement shows standing legs")
	# 2x speed
	pair_step(g,1.0,10,"walk")
	var p0:float = gg.phase
	pair_step(g,2.0,30,"walk")
	check(absf(wrapf(gg.phase-p0,-0.5,0.5)) < 0.02,"golem: 2x speed -> full stride in 0.5 s")
	# villager throw while moving
	var vg:RefCounted = v._pair_gait()
	pair_step(v,1.0,20,"carry_walk")
	var rv:Dictionary = pair_step(v,1.0,20,"throw",0.2)
	check(rv.legs.size() >= 6 and not rv.legs.has(-1),"villager: throw while moving keeps legs walking")
	# real tick_physics hook advances the gait from displacement
	var before:float = vg.phase
	for i:int in range(20):
		v.global_position.x += LEGS.standard_speed(v)/60.0
		v.tick_physics(v.State.Stand,1.0/60.0)
	check(absf(wrapf(vg.phase-before,-0.5,0.5)) > 0.2,"villager: tick_physics advances legs from real displacement")
	g.queue_free()
	v.queue_free()

func warden_step(w:Node2D,ratio:float,frames_n:int,setup:Callable) -> Dictionary:
	var v:float = LEGS.standard_speed(w)*ratio
	var out:Dictionary = {"legs":{},"clips":{}}
	for i:int in range(frames_n):
		setup.call()
		w.global_position.x += v/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
		out.legs[w._leg_index] = true
	return out

func warden_suite(center:Vector2) -> void:
	var w:Node2D = spawn("res://scenes/characters/我的世界/监守者.tscn",center+Vector2(500,300))
	await process_frame
	await process_frame
	w.set_process(false)
	w._form_stats(true)
	w.form = w.Form.AWAKE
	var g:RefCounted = w._warden_gait()
	check(is_equal_approx(LEGS.standard_speed(w),66.0*0.6) and (g.neutral as Array).size() == 2,"warden: awake standard speed 66 x 0.6, 2 rest phases")
	var none:Callable = func(): pass
	var idx:Dictionary = {}
	for i:int in range(60):
		w.global_position.x += LEGS.standard_speed(w)/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
		idx[g.walk_index(16)] = w.image.texture == w.WARDEN.get_frame_texture(&"walk",g.walk_index(16))
	check(idx.size() >= 15 and not idx.values().has(false),"warden: walk frames follow the gait (%d of 16)" % idx.size())
	var ra:Dictionary = warden_step(w,1.0,20,func(): w.melee_visual_left = 0.3)
	check(ra.legs.size() >= 6 and not ra.legs.has(-1),"warden: melee while moving keeps legs walking (%d phases)" % ra.legs.size())
	var rs:Dictionary = warden_step(w,1.0,20,func(): w.sonic_left = w.sonic_windup*0.5)
	check(rs.legs.size() >= 6 and not rs.legs.has(-1) and LEGS.cached_source_image(w.image.texture) != null,"warden: sonic boom while moving composites walking legs")
	for i:int in range(60):
		w.sonic_left = w.sonic_windup*0.5
		w._legs_delta = 1.0/60.0
		w.visual_mob()
	check(g.at_rest and w._leg_index == -1,"warden: sonic while still -> stock frame, legs at rest")
	w.sonic_left = 0.0
	w.melee_visual_left = 0.0
	w._legs_delta = 1.0/60.0
	w.visual_mob()
	check(w.image.texture == w.WARDEN.get_frame_texture(&"idle",int(w._view_clock*w.WARDEN.get_animation_speed(&"idle"))%w.WARDEN.get_frame_count(&"idle")),"warden: still -> idle clip")
	w.queue_free()

func wither_step(w:Node2D,ratio:float,frames_n:int,combo:float) -> Dictionary:
	var v:float = LEGS.standard_speed(w)*ratio
	var out:Dictionary = {"legs":{},"stock":0}
	for i:int in range(frames_n):
		w.combo_time = combo
		w.global_position.x += v/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
		out.legs[w._leg_index] = true
		if w.image.texture == w.ATTACK_PARTS.get_frame_texture(&"body",w._body_frame): out.stock += 1
	return out

func wither_suite(center:Vector2) -> void:
	var w:Node2D = spawn("res://scenes/characters/我的世界/凋灵骷髅.tscn",center+Vector2(-500,300))
	await process_frame
	await process_frame
	w.set_process(false)
	w.set_physics_process(false)
	var g:RefCounted = w._wither_gait()
	check(is_equal_approx(LEGS.standard_speed(w),float(w.default_properties.Speed)*0.6) and (g.neutral as Array).size() == 2,"wither: own base speed x 0.6, 2 rest phases")
	var idx:Dictionary = {}
	var hands_ok:bool = true
	for i:int in range(60):
		w.combo_time = -1.0
		w.global_position.x += LEGS.standard_speed(w)/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
		var k:int = g.walk_index(16)
		idx[k] = w.image.texture == w.FRAMES.get_frame_texture(&"walk",k)
		hands_ok = hands_ok and w._rest_hand().is_equal_approx(w._hand_pixel(w.POSES.HANDS["walk"][k]))
	check(idx.size() >= 15 and not idx.values().has(false),"wither: walk frames follow the gait (%d of 16)" % idx.size())
	check(hands_ok,"wither: resting sword hand follows the shown walk frame")
	var p0:float = g.phase
	for i:int in range(12):
		w.global_position.x += LEGS.standard_speed(w)*0.5/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
	var slow:float = fposmod(g.phase-p0,1.0)
	p0 = g.phase
	for i:int in range(12):
		w.global_position.x += LEGS.standard_speed(w)*1.5/60.0
		w._legs_delta = 1.0/60.0
		w.visual_mob()
	var fast:float = fposmod(g.phase-p0,1.0)
	check(slow > 0.0 and absf(fast/slow-3.0) < 0.15,"wither: leg rate scales with speed (x%.2f for x3)" % (fast/maxf(slow,0.0001)))
	var ra:Dictionary = wither_step(w,0.3,40,0.3)
	check(ra.legs.size() >= 4 and not ra.legs.has(-1) and ra.stock == 0,"wither: sword combo while moving (slowed) keeps legs walking (%d phases)" % ra.legs.size())
	check(w._body_clip == &"attack" and LEGS.cached_source_image(w.image.texture) != null,"wither: combo while moving shows the composited attack body")
	var rs:Dictionary = wither_step(w,0.0,60,0.3)
	check(g.at_rest and w._leg_index == -1 and w.image.texture == w.ATTACK_PARTS.get_frame_texture(&"body",w._body_frame),"wither: combo while still -> stock attack body, legs at rest")
	w.combo_time = -1.0
	w._legs_delta = 1.0/60.0
	w.visual_mob()
	check(w._body_clip == &"idle" and w.image.texture == w.FRAMES.get_frame_texture(&"idle",w._body_frame),"wither: still -> idle clip")
	w.queue_free()

func vind_move(v:Node2D,speed:float,frames_n:int) -> Dictionary:
	var g:RefCounted = v._vindicator_gait()
	var out:Dictionary = {"idx":{},"ok":true}
	for i:int in range(frames_n):
		v.global_position.x += speed/60.0
		g.tick(v,1.0/60.0,true)
		v._update_pose()
		var k:int = g.walk_index(12)
		out.idx[k] = true
		out.ok = out.ok and (v.image.texture == (v.FRAMES.get_frame_texture(&"idle",0) if g.at_rest else v.FRAMES.get_frame_texture(&"walk",k)))
	return out

func vindicator_suite(center:Vector2) -> void:
	var v:Node2D = spawn("res://scenes/characters/我的世界/卫道士.tscn",center+Vector2(-500,-300))
	await process_frame
	await process_frame
	v.set_process(false)
	v.set_physics_process(false)
	var g:RefCounted = v._vindicator_gait()
	var std:float = LEGS.standard_speed(v)
	check(is_equal_approx(std,float(v.default_properties.Speed)*0.6) and is_equal_approx(g.cycle,1.0),"vindicator: own base speed x 0.6, 1 s walk cycle")
	var r:Dictionary = vind_move(v,std,60)
	check(r.ok and r.idx.size() >= 11,"vindicator: walk frames follow the gait (%d of 12)" % r.idx.size())
	v.phase = v.Phase.CHARGE
	v.charge_elapsed = 0.3
	r = vind_move(v,std*0.5,40)
	check(r.ok and r.idx.size() >= 4 and not g.at_rest,"vindicator: axe charge while moving keeps legs walking (%d phases)" % r.idx.size())
	v.phase = v.Phase.IDLE
	var p0:float = g.phase
	vind_move(v,std*0.5,12)
	var slow:float = fposmod(g.phase-p0,1.0)
	p0 = g.phase
	vind_move(v,std*1.5,12)
	var fast:float = fposmod(g.phase-p0,1.0)
	check(slow > 0.0 and absf(fast/slow-3.0) < 0.15,"vindicator: leg rate scales with speed (x%.2f for x3)" % (fast/maxf(slow,0.0001)))
	var base_speed:float = v.Speed
	v.Speed = base_speed*2.0
	p0 = g.phase
	vind_move(v,std,12)
	var buffed:float = fposmod(g.phase-p0,1.0)
	v.Speed = base_speed
	check(absf(buffed/maxf(slow,0.0001)-2.0) < 0.15,"vindicator: a Speed buff does not re-normalise the tempo (standard = base speed)")
	r = vind_move(v,0.0,90)
	check(g.at_rest and v.image.texture == v.FRAMES.get_frame_texture(&"idle",0) and r.ok,"vindicator: still -> legs settle back to the idle pose")
	v.queue_free()

func vis_step(u:Node2D,vis:Node,ratio:float,frames_n:int,setup:Callable) -> Dictionary:
	var v:float = LEGS.standard_speed(u)*ratio
	var out:Dictionary = {"legs":{},"clips":{},"idx":{}}
	for i:int in range(frames_n):
		setup.call()
		u.global_position.x += v/60.0
		vis._process(1.0/60.0)
		out.legs[vis._leg_index] = true
		out.clips[vis.clip] = true
		out.idx[vis.frame_index] = true
	return out

func trader_suite(center:Vector2) -> void:
	var t:Node2D = spawn("res://scenes/characters/我的世界/流浪商人.tscn",center+Vector2(-600,500))
	var l:Node2D = spawn("res://scenes/creatures/流浪商人_羊驼.tscn",center+Vector2(-300,500))
	await process_frame
	await process_frame
	var tv:Node = t.visual
	var lv:Node = l.visual
	check(is_instance_valid(tv) and is_instance_valid(lv),"trader/llama: visual drivers attached")
	if not (is_instance_valid(tv) and is_instance_valid(lv)): return
	tv.set_process(false)
	lv.set_process(false)
	var none:Callable = func(): pass
	var rw:Dictionary = vis_step(t,tv,1.0,60,none)
	check(rw.clips.has(&"walk") and rw.idx.size() >= 22,"trader: walk frames follow the gait (%d)" % rw.idx.size())
	var rd:Dictionary = vis_step(t,tv,1.0,24,func(): t._drink_visual_left = 0.5)
	check(rd.clips.has(&"drink") and rd.legs.size() >= 8 and not rd.legs.has(-1),"trader: drinking while moving keeps legs walking (%d phases)" % rd.legs.size())
	for i:int in range(60):
		t._drink_visual_left = 0.5
		tv._process(1.0/60.0)
	check(tv.gait.at_rest and tv._leg_index == -1 and t.image.texture == tv.frames.get_frame_texture(&"drink",tv.frame_index),"trader: drinking while still -> stock frame")
	t._drink_visual_left = 0.0
	for i:int in range(3): tv._process(1.0/60.0)
	check(tv.clip == &"idle","trader: still -> idle")
	# llama: walk, run (fast) and spit over walking / running legs
	var lw:Dictionary = vis_step(l,lv,1.0,30,none)
	check(lw.clips.has(&"walk") or lw.clips.has(&"run"),"llama: moving selects walk/run")
	var p0:float = lv.gait.phase
	vis_step(l,lv,2.0,30,none)
	check(absf(wrapf(lv.gait.phase-p0,-0.5,0.5)) < 0.02,"llama: 2x speed -> full stride in 0.5 s")
	var rs:Dictionary = vis_step(l,lv,1.0,20,func(): l._spit_anim = 0.3)
	check(rs.clips.has(&"spit") and rs.legs.size() >= 6 and not rs.legs.has(-1),"llama: spit while moving keeps legs walking")
	l._spit_anim = 0.0
	for i:int in range(60): lv._process(1.0/60.0)
	check(lv.gait.at_rest and lv.clip == &"idle","llama: still -> idle (%s, emerging=%s)" % [lv.clip,str(l.get("emerging"))])
	t.queue_free()
	l.queue_free()

func finish(code:int) -> void:
	if finishing: return
	finishing = true
	print("independent legs: %d checks, %d failures" % [checks,failures])
	game.Game_Settings = saved
	game.now_stop_state = saved_stop
	if is_instance_valid(world): world.queue_free()
	await process_frame
	quit(code if failures == 0 or code != 0 else 1)
