extends "res://tests/test_sulfur_cube_balance.gd"
## Task 13 (2026-09-28): 流浪商人 + two leashed trader llamas, in a real World.
## Herd spawn/leash, yank-back ignoring character collision, llama-only speed damage with knockback
## along the llama's motion, spit (medium interval, medium-fast shot), delayed retaliation spit,
## milk only with a negative effect (copper-sword cleanse, long cooldown), Witch invisibility,
## wall phase (leash snaps, hidden/untargetable, exits at the safest wall slot, leash reconnects),
## killable llamas without respawn, herd retires with the trader, manual controls.
const WALL_CLIP_SCRIPT = preload("res://scripts/characters/我的世界/wandering_trader/wall_clip.gd")
const WALL_SCRIPT = preload("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
var sounds:Dictionary = {}

func hold(u:Node) -> void:
	u.state_machine.set_physics_process(false);u.set_physics_process(false)
	u.Has_Collision_Damage=false;u.Can_Attack=false;u.Can_Skill=false

func unit(scene:String,n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=load(scene).instantiate();u.name=n;u.Team=team;u.position=pos
	if u.has_node("CharacterAutoFit"):u.get_node("CharacterAutoFit").enabled=false
	world.add_child(u,true)
	return u

func seconds(t:float) -> void:
	var left:float=t
	while left>0.0:
		await physics_frame;left-=1.0/60.0

## The wall skill only arms: aim him at the nearest wall and wait until he runs into it.
func enter_wall(trader:Node2D) -> bool:
	var slots:Array[Dictionary]=WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect())
	var slot:Dictionary=WALL_SCRIPT.nearest_slot(slots,trader.global_position)
	if slot.is_empty():return false
	trader.direction=-(slot.normal as Vector2).normalized()
	if not trader.start_wall_phase():return false
	var t:float=0.0
	while trader.wall_phase==0 and t<4.0:
		await physics_frame;t+=1.0/60.0
	return trader.wall_phase!=0

func heard(ev:String) -> int: return int(sounds.get(ev,0))

## MC §1 hit feedback players currently alive (new5 table, parented to the scene).
func hit_players() -> Array:
	return get_nodes_in_group(&"MCNativeSFX").filter(func(n:Node) -> bool: return String(n.get_meta(&"mc_sound_event","")) in ["entity.player.hurt","entity.player.attack.crit"])

func _on_node_added(n:Node) -> void:
	if n.has_meta(&"wt_event"):
		var ev:String=String(n.get_meta(&"wt_event"));sounds[ev]=int(sounds.get(ev,0))+1

func run() -> void:
	create_timer(220.0,true,false,true).timeout.connect(func(): print("WANDERING_TRADER_TIMEOUT"); quit(2))
	game=root.get_node("Game")
	var saved:bool=game.Game_Settings.Have_Team_Damage
	game.now_stop_state=false
	game.Game_Settings.Training_Mode=true
	game.Game_Settings.Training_Mode_Type="manual"
	AudioServer.set_bus_mute(0,true)
	node_added.connect(_on_node_added)
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	for i:int in range(20):await process_frame
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.queue_free()
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var center:Vector2=rect.get_center()
	print("map ",world.now_choose_map," rect ",rect)
	var trader:Node2D=unit("res://scenes/characters/我的世界/流浪商人.tscn","WT","Team0",center)
	var enemy:Node2D=unit("res://scenes/ball.tscn","WTEnemy","Team1",center+Vector2(rect.size.x*0.4,0))
	await process_frame
	hold(enemy);enemy.Max_health=100000;enemy.health=100000
	trader._invisibility_wait=999.0;trader._wall_wait=999.0;trader._milk_wait=999.0
	for i:int in range(6):await process_frame
	# --- herd ---------------------------------------------------------------------
	var herd:Array=trader.living_llamas()
	check(herd.size()==2,"trader brings exactly two llamas (%d)" % herd.size())
	if herd.size()<2:
		print("WANDERING_TRADER checks=",checks," failures=",failures);quit(1);return
	var l0:Node2D=herd[0];var l1:Node2D=herd[1]
	check(String(l0.name)=="WT_Llama0" and String(l1.name)=="WT_Llama1","llama names are deterministic (%s,%s)" % [l0.name,l1.name])
	check(l0.Master==trader and l1.Master==trader and l0.Type==3 and l0.Team=="Team0","llamas are Creature summons of the trader on his team")
	check(l0.leash_connected and l1.leash_connected and trader.wt_leash_active(),"both leashes connected at spawn")
	check(trader.leashes.size()==2 and trader.leashes[0].is_inside_tree() and trader.leashes[0].is_connected_visual() and trader.leashes[1].is_connected_visual(),"two leash views drawn in world space")
	check(l0.is_combat_targetable() and l1.is_combat_targetable(),"llamas are killable (targetable) summons")
	check(not l0.get_meta(&"haochen_copy",false) and l0.get_node("Graphics/Image").texture!=null and trader.get_node("Graphics/Image").texture!=null,"baked frames applied to trader and llama")
	check(trader.Max_health==250 and l0.Max_health==350 and l1.Max_health==350,"HP: trader 250, llamas 350 (%d / %d / %d)" % [trader.Max_health,l0.Max_health,l1.Max_health])
	for l:Node2D in [l0,l1]:l.Max_health=100000;l.health=100000
	# --- yank back through a character (ignore character collision) ----------------
	hold(trader)
	var p:Vector2=center+Vector2(-rect.size.x*0.15,0)
	trader.global_position=p
	l0.global_position=p+Vector2(-80,0);l1.global_position=p+Vector2(0,-14)
	var blocker:Node2D=unit("res://scenes/ball.tscn","WTBlocker","Team0",p+Vector2(-40,0))
	await process_frame
	hold(blocker);blocker.Max_health=100000;blocker.health=100000
	var saw_yank:bool=false;var ghost_layers:bool=true;var closest:float=INF
	for i:int in range(150):
		await physics_frame
		if l0.yanking:
			saw_yank=true
			if l0.collision_layer!=0 or (l0.collision_mask & 2)!=0:ghost_layers=false
		closest=minf(closest,l0.global_position.distance_to(trader.global_position))
		if saw_yank and not l0.yanking:break
	check(saw_yank,"a llama beyond leash_pull_start is yanked back")
	check(ghost_layers,"while yanked the llama ignores character collision (layer 0, no character mask)")
	check(closest<=trader.leash_pull_end+6.0,"the yank brings it back through a same-team character (closest %.1f)" % closest)
	check(blocker.health==100000,"the teammate on the path takes no speed damage")
	await seconds(2.0) # still overlapping the teammate: leaves ghost mode by the 1.5 s fallback
	check(l0.collision_layer==2 and l0.collision_mask==3,"normal collision restored after the yank (%d/%d)" % [l0.collision_layer,l0.collision_mask])
	blocker.queue_free()
	# --- speed damage on the yank path + knockback parallel to motion ---------------
	var foe:Node2D=unit("res://scenes/ball.tscn","WTFoe","Team1",p+Vector2(-45,0))
	await process_frame
	hold(foe);foe.Max_health=100000;foe.health=100000
	l0.global_position=p+Vector2(-90,0)
	var hits0:int=l0.speed_hits_dealt
	for i:int in range(90):
		await physics_frame
		if l0.speed_hits_dealt>hits0:break
	check(l0.speed_hits_dealt>hits0 and foe.health<100000,"a yanked llama rams an enemy on its path (hp %d)" % foe.health)
	check(l0.speed_damage_for(100.0)==0.0 and is_equal_approx(l0.speed_damage_for(200.0),18.0) and l0.speed_damage_for(9999.0)==l0.speed_damage_max,"speed damage scales with speed, 0 below the threshold, capped")
	check(trader.get("speed_hits_dealt")==null and not trader.has_method(&"apply_speed_hit"),"the trader itself has no speed damage (llama body only)")
	foe.Speed=0.0;foe.default_properties.Speed=0.0
	var ram_from:Vector2=foe.global_position
	foe.set_physics_process(true);foe.state_machine.set_physics_process(true)
	await seconds(0.6)
	var ram_moved:Vector2=foe.global_position-ram_from
	check(ram_moved.x>2.0 and absf(ram_moved.y)<ram_moved.x*0.35,"the ram knocks the enemy along the yank direction (+x, moved %s)" % ram_moved)
	# Measure the direct hit away from the herd: crowd separation / body contacts with the moving
	# llamas would otherwise add their own displacement.
	for l:Node in [l0,l1]:l.state_machine.set_physics_process(false);l.set_physics_process(false)
	foe.global_position=Vector2(rect.end.x-40.0,rect.position.y+40.0)
	await seconds(0.2)
	var before:Vector2=foe.global_position;var hp:int=foe.health
	l0._speed_hits.clear()
	var hit_sfx0:Array=hit_players()
	var hit:bool=l0.apply_speed_hit(foe,250.0,Vector2(0,1))
	var hit_sfx:Array=hit_players().filter(func(n:Node) -> bool: return not hit_sfx0.has(n))
	check(hit_sfx.size()==1 and String(hit_sfx[0].get_meta(&"mc_sound_event"))=="entity.player.hurt" and hit_sfx[0].volume_db>=0.0,"speed hit plays the MC hurt hit sound once (%d)" % hit_sfx.size())
	await seconds(0.35)
	var moved:Vector2=foe.global_position-before
	check(hit and foe.health<hp,"direct speed hit damages")
	check(moved.y>2.0 and absf(moved.x)<moved.y*0.35,"knockback follows the llama's motion direction (moved %s)" % moved)
	foe.queue_free()
	for l:Node in [l0,l1]:l.state_machine.set_physics_process(true);l.set_physics_process(true)
	# --- spit ---------------------------------------------------------------------------
	enemy.global_position=l1.global_position+Vector2(90,0)
	await physics_frame
	var fired:int=l1.spits_fired;hp=enemy.health
	var old_puffs:Array=get_nodes_in_group(&"MCLlamaSpitSmoke")
	l1.spit_at(enemy)
	var shot:Node=world.get_node_or_null(NodePath("%s_Spit%d" % [l1.name,l1._spit_serial]))
	check(shot!=null and is_equal_approx(shot.Speed,300.0) and shot.Damage==14 and shot.Master==l1,"spit spawned with medium-fast speed 300 and 14 damage")
	check(l1.spits_fired==fired+1 and heard("llama_spit")>=1,"spit counted and plays llama spit sound")
	var puffs:Array=get_nodes_in_group(&"MCLlamaSpitSmoke").filter(func(n:Node) -> bool: return not old_puffs.has(n))
	var along:int=0
	for puff:Node in puffs:if (puff.velocity as Vector2).normalized().dot(shot.direction)>0.8:along+=1
	check(puffs.size()==7 and along==7,"vanilla launch: 7 spit smoke puffs fly along the shot (%d, %d along)" % [puffs.size(),along])
	check(shot!=null and absf(angle_difference(shot.image.rotation+PI,shot.direction.angle()))<0.01,"spit model turned to its flight direction")
	var bursts_before:int=get_nodes_in_group(&"MCWanderingTraderFx").size()
	var spit_sfx0:Array=hit_players()
	for i:int in range(60):
		await physics_frame
		if enemy.health<hp:break
	check(enemy.health<hp,"spit hits the enemy (hp %d -> %d)" % [hp,enemy.health])
	var spit_sfx:Array=hit_players().filter(func(n:Node) -> bool: return not spit_sfx0.has(n))
	var HG:Script=load("res://scripts/effects/我的世界/hit_audio_gain.gd")
	check(spit_sfx.size()==1 and String(spit_sfx[0].get_meta(&"mc_sound_event"))==HG.damage_event(float(hp-enemy.health)) and is_equal_approx(spit_sfx[0].volume_db,clampf(HG.damage_gain(float(hp-enemy.health)),0.0,6.0)) and spit_sfx[0].get_parent()==world,"spit hit plays the MC hit sound once at 0 dB+ gain, outliving the spit (%d)" % spit_sfx.size())
	check(get_nodes_in_group(&"MCWanderingTraderFx").size()==bursts_before,"no invented block-chip splash on impact (vanilla spit just disappears)")
	check(is_equal_approx(l1.spit_interval,2.0) and l1.spit_range>100.0,"medium attack interval 2.0 s")
	# --- retaliation --------------------------------------------------------------------
	await seconds(0.4)
	l1._spit_wait=99.0
	var r0:int=l1.retaliations
	l1.receive_positional_damage(5.0,l1.global_position,false,enemy)
	await seconds(0.25)
	check(l1.retaliations==r0,"no instant retaliation (delay)")
	await seconds(0.45)
	check(l1.retaliations==r0+1 and heard("llama_angry")>=1,"retaliation spit after the delay")
	# --- milk ----------------------------------------------------------------------------
	enemy.global_position=center+Vector2(rect.size.x*0.4,0)
	trader.global_position=center+Vector2(-rect.size.x*0.15,0)
	trader.set_physics_process(true);trader.state_machine.set_physics_process(true)
	trader._milk_wait=0.0
	var POT:Script=load("res://scripts/effects/我的世界/女巫药水效果.gd")
	POT.apply_effect(trader,"speed",trader)
	await seconds(0.5)
	check(not trader.has_negative_effect() and trader.milk_drinks==0,"no milk with only a positive effect")
	POT.apply_effect(trader,"slowness",enemy)
	POT.apply_effect(trader,"poison",enemy)
	check(trader.has_negative_effect(),"slowness/poison detected as negative")
	await seconds(0.4)
	check(trader.milk_drinks==1 and heard("drink_milk")>=1,"drinks milk once a negative effect exists")
	await seconds(1.2)
	check(not trader.has_negative_effect() and trader.last_cleansed>=1,"milk cleared all negative effects (removed %d)" % trader.last_cleansed)
	var STATUS:Script=load("res://scripts/effects/我的世界/mc_status_effects.gd")
	check(STATUS.active(trader,"speed"),"positive effect kept by the milk")
	POT.apply_effect(trader,"slowness",enemy)
	await seconds(1.0)
	check(trader.milk_drinks==1 and trader._milk_wait>10.0,"long cooldown: no second milk right away")
	trader.cleanse_negative_effects()
	# --- invisibility ------------------------------------------------------------------------
	trader._invisibility_wait=0.0
	check(trader.start_drink(&"invisibility"),"invisibility drink starts")
	await seconds(1.0)
	check(trader.is_invisible() and STATUS.active(trader,"invisibility") and trader.potion_drinks==1 and heard("drink_potion")>=1,"Witch invisibility applied after drinking")
	# --- wall ------------------------------------------------------------------------------------
	enemy.global_position=trader.global_position+Vector2(50,0)
	var invis_at_start:bool=trader.is_invisible()
	var hp_t:int=trader.health
	var orig_material:Material=trader.image.material
	check(WALL_CLIP_SCRIPT.clip_shader(WALL_CLIP_SCRIPT.base_shader_of(trader.image))!=null,"clip shader built from the character's own set_rgb_color shader")
	var near_slot:Dictionary=WALL_SCRIPT.nearest_slot(WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect()),trader.global_position)
	enemy.global_position=trader.global_position+(near_slot.normal as Vector2).normalized()*50.0
	var l0_dir:Vector2=l0._last_motion_dir
	var aim:Vector2=-(near_slot.normal as Vector2).normalized()
	var entered:bool=await enter_wall(trader)
	check(entered and not trader.wall_armed,"wall skill arms; he keeps moving and goes in at the wall he runs into")
	var entry:Dictionary=trader.entry_slot
	var normal_speed:float=trader.Speed*trader.CHARACTER_BASE_MOVE_SPEED_MULTIPLIER
	check(trader._wall_walk_speed<=normal_speed*1.05+0.5 and trader._wall_walk_speed>=normal_speed*0.5,"walks in at his normal speed, no speed-up (%.1f, normal %.1f)" % [trader._wall_walk_speed,normal_speed])
	check(trader.wall_phase==1 and not trader.wt_leash_active() and trader.collision_layer==0,"entering: leash broken, collision off")
	await seconds(0.1)
	check(not trader.leashes[0].is_connected_visual() and heard("leash_break")>=1 and heard("trader_disappeared")>=1,"leash views snap with leash_break + disappeared sounds")
	var clip_material:Callable=func() -> bool: return trader.image.material is ShaderMaterial and (trader.image.material as ShaderMaterial).shader==WALL_CLIP_SCRIPT.clip_shader((orig_material as ShaderMaterial).shader)
	var face:Vector2=trader.wall_face_point(entry)
	var normal:Vector2=(entry.normal as Vector2).normalized()
	check(clip_material.call() and trader.image.self_modulate.a>0.99 and trader.visible,"entering: fully opaque, body clipped on the wall surface (no fade)")
	var t:float=0.0
	var seen_partial:bool=false
	var hidden_early:bool=false
	var walk_ok:bool=true;var prev:Vector2=trader.global_position
	await physics_frame
	check(l0.free_moving and l1.free_moving and (l0_dir==Vector2.ZERO or l0.direction.dot(l0_dir)>0.99),"leash off: llamas switch to normal free movement, starting in their last motion direction (free %s/%s, dir %s, before %s)" % [l0.free_moving,l1.free_moving,l0.direction,l0_dir])
	while trader.wall_phase==1 and t<3.2:
		var step_now:Vector2=trader.global_position-prev;prev=trader.global_position
		if step_now.length()>0.01 and (step_now.length()*60.0>trader._wall_walk_speed*1.1 or step_now.normalized().dot(aim)<0.99):walk_ok=false
		var front:float=(trader.global_position-face).dot(normal)-trader.body_reach(-normal)
		if front<0.0 and trader.wall_body_visible():seen_partial=true
		if not trader.visible:hidden_early=true
		await physics_frame;t+=1.0/60.0
	check(walk_ok,"walk-in keeps his movement direction and speed")
	check(seen_partial and not hidden_early,"walks straight in: partly inside the wall while still visible, never hidden early")
	check(trader.wall_phase==2 and not trader.visible and not trader.is_combat_targetable(),"hidden inside the wall: invisible and untargetable")
	check((trader.global_position-face).dot(normal)+trader.body_reach(normal)<=0.01 and heard("stone_break")>=1,"disappears only once the whole body is behind the wall surface (stone break) pos %s face %s" % [trader.global_position,face])
	check(not trader.receive_positional_damage(50.0,trader.global_position,false,enemy) and trader.health==hp_t,"no damage while inside the wall")
	check(not l1.leash_active(trader),"llamas are free (leash broken) while he hides")
	var free_from:Vector2=l0.global_position
	await seconds(0.5)
	check(l0.free_moving and l0.global_position.distance_to(free_from)>15.0,"free llama keeps moving on its own (%.1f px in 0.5 s, free %s, spit %.2f, phys %s)" % [l0.global_position.distance_to(free_from),l0.free_moving,l0._spit_anim,l0.state_machine.is_physics_processing()])
	while trader.wall_phase==2 and t<6.5:
		await physics_frame;t+=1.0/60.0
	await physics_frame
	var exit_face:Vector2=trader.wall_face_point(trader.exit_slot)
	var exit_normal:Vector2=(trader.exit_slot.normal as Vector2).normalized()
	check(trader.wall_phase==3 and trader.visible and clip_material.call() and trader.image.self_modulate.a>0.99,"emerging: opaque, clipped on the exit wall surface")
	check((trader.global_position-exit_face).dot(exit_normal)<0.0,"emerging starts from inside the wall")
	var dirs_ok:bool=true
	var last:Vector2=trader.global_position
	while trader.wall_phase==3 and t<9.5:
		await physics_frame;t+=1.0/60.0
		var step:Vector2=trader.global_position-last
		if step.length()>0.01 and (step.normalized().dot(trader.exit_direction)<0.99 or step.length()*60.0>trader._wall_walk_speed*1.1):dirs_ok=false
		last=trader.global_position
	check(dirs_ok,"comes straight out at the walk-in angle and normal speed")
	check(trader.direction.normalized().dot(trader.exit_direction)>0.99 or trader.wall_phase!=0,"keeps moving in the exit direction afterwards")
	check(not clip_material.call() and trader.image.material==orig_material,"original character material restored after emerging")
	check(trader.wall_phase==0 and trader.visible and trader.is_combat_targetable(),"emerged and targetable again")
	var WALL:Script=load("res://scripts/characters/我的世界/wandering_trader/wall_phase.gd")
	var slots:Array[Dictionary]=WALL.wall_slots(world,trader.mc_arena_rect())
	var threats:Array[Vector2]=trader.threat_points()
	var best:float=0.0
	for s:Dictionary in slots:best=maxf(best,WALL.min_threat_distance(s.floor,threats))
	var got:float=WALL.min_threat_distance(trader.global_position,threats)
	check(not trader.exit_slot.is_empty() and got>=best-40.0,"exit chosen at (near) the safest wall slot (%.0f of best %.0f, %d slots)" % [got,best,slots.size()])
	check(trader.mc_body_position_clear(trader.global_position),"exit point is body-clear (not stuck in a wall)")
	check(heard("stone_hit")>=1 and heard("trader_reappeared")>=1,"emerges with stone hit + reappeared")
	await seconds(0.2)
	check(trader.wt_leash_active() and trader.leashes[0].is_connected_visual() and trader.leashes[1].is_connected_visual() and heard("leash_place")>=1,"leashes reconnect when he comes out")
	var invis_now:bool=trader.is_invisible()
	check(((trader.collision_layer & 2)!=0)==(not invis_now) and (trader.collision_mask & 1)!=0,"collision restored consistently (invisible at start %s, now %s, %d/%d)" % [invis_at_start,invis_now,trader.collision_layer,trader.collision_mask])
	check(not trader.has_meta(&"ignore_combat_targeting") and not trader.has_meta(&"ignore_combat_locking") or invis_now,"wall metas cleared")
	check(not trader.has_meta(&"submission_allow_map_escape"),"map-escape exemption cleared after the wall phase")
	# --- potion and wall are independent skills --------------------------------------------------
	enemy.global_position=center+Vector2(rect.size.x*0.4,0)
	trader._wall_wait=999.0;trader._invisibility_wait=999.0
	t=0.0
	while trader.is_invisible() and t<8.0:
		await physics_frame;t+=1.0/60.0
	check(not trader.is_invisible(),"previous invisibility wore off")
	check(await enter_wall(trader),"wall again for the independence checks")
	t=0.0
	while trader.wall_phase!=2 and t<4.0:
		await physics_frame;t+=1.0/60.0
	trader._invisibility_wait=0.0
	check(trader.wall_phase==2 and trader.start_drink(&"invisibility"),"drinks the potion while hidden inside the wall")
	var inv_w:float=trader._invisibility_wait;var wall_w:float=trader._wall_wait
	await seconds(0.9)
	check(trader._invisibility_wait<inv_w-0.8 and trader._wall_wait<wall_w-0.8,"both cooldowns tick inside the wall (%.2f->%.2f, %.2f->%.2f)" % [inv_w,trader._invisibility_wait,wall_w,trader._wall_wait])
	check(trader.wall_phase!=0 and trader._drink_left<=0.0 and trader._pending_invisibility and not STATUS.active(trader,"invisibility") and trader.collision_layer==0,"potion finished in the wall: invisibility deferred, collision stays off")
	t=0.0
	while trader.wall_phase!=0 and t<5.0:
		await physics_frame;t+=1.0/60.0
	check(trader.wall_phase==0 and STATUS.active(trader,"invisibility") and not trader._pending_invisibility,"deferred invisibility applied when he comes out")
	check((trader.collision_layer & 2)==0 and (trader.collision_layer & ~2)==(trader._saved_layer & ~2) and (trader.collision_mask & 1)!=0,"invisibility on top of the restored collision (%d/%d)" % [trader.collision_layer,trader.collision_mask])
	trader._wall_wait=999.0;trader._invisibility_wait=999.0
	t=0.0
	while trader.is_invisible() and t<8.0:
		await physics_frame;t+=1.0/60.0
	check(((trader.collision_layer & 2)!=0) and not trader.is_invisible(),"collision layer 2 back after the deferred invisibility ends (%d)" % trader.collision_layer)
	# AI: both skills in the same frame (threat inside both radii).
	var near_side:Vector2=Vector2(40,0) if trader.global_position.x<center.x else Vector2(-40,0)
	enemy.global_position=trader.global_position+near_side
	trader._wall_wait=0.0;trader._invisibility_wait=0.0
	await physics_frame;await physics_frame
	check(trader.wall_armed and trader._drink_left>0.0 and trader._drink_kind==&"invisibility","AI uses wall and potion together (wall armed while drinking)")
	enemy.global_position=center+Vector2(rect.size.x*0.4,0)
	var aim_slot:Dictionary=WALL_SCRIPT.nearest_slot(WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect()),trader.global_position)
	trader.direction=-(aim_slot.normal as Vector2).normalized()
	t=0.0
	while trader.wall_phase==0 and t<4.0:
		await physics_frame;t+=1.0/60.0
	check(trader.wall_phase!=0,"the armed wall goes in at the next wall he runs into")
	trader._wall_wait=999.0;trader._invisibility_wait=999.0
	trader.finish_wall_phase_now()
	check(trader.wall_phase==0 and STATUS.active(trader,"invisibility") and trader.visible,"forced exit applies the deferred invisibility")
	# --- llama death: leash removed, no respawn ------------------------------------------------
	trader._wall_wait=999.0;trader._invisibility_wait=999.0
	l1.take_damage(1e9)
	await seconds(0.1)
	check(trader.living_llamas().size()==1 and not trader.leashes[1].is_connected_visual(),"a dead llama loses its leash")
	await seconds(1.5)
	check(trader.living_llamas().size()==1 and world.get_node_or_null("WT_Llama1")==null and trader._llama_return_wait[1]>15.0,"no instant respawn: the 20 s return cooldown runs (%.1f)" % trader._llama_return_wait[1])
	# --- exit tell + llama return through the wall ---------------------------------------------
	check(trader.due_llama_slot()==-1,"dead llama not due before its return cooldown")
	trader._llama_return_wait[1]=0.0
	check(trader.due_llama_slot()==1,"llama slot due once the cooldown is over")
	var warn0:int=trader.exit_warnings;var stone0:int=heard("stone_hit")
	trader._wall_wait=0.0
	check(await enter_wall(trader),"wall phase for the exit tell / llama return")
	trader._wall_wait=999.0
	t=0.0
	while trader.exit_warnings==warn0 and trader.wall_phase!=3 and t<5.0:
		await physics_frame;t+=1.0/60.0
	var lead:float=trader.wall_hidden_time-trader._phase_time
	check(trader.exit_warnings==warn0+1 and trader.wall_phase==2 and absf(lead-trader.wall_exit_warning)<0.05,"exit tell fires while still hidden, %.2f s before he comes out" % lead)
	var warned:Dictionary=trader.exit_slot.duplicate()
	var warn_face:Vector2=trader.wall_face_point(warned)
	await physics_frame
	var chips:int=0
	for n:Node in get_nodes_in_group(&"MCWanderingTraderFx"):if n is Node2D and (n as Node2D).global_position.distance_to(warn_face)<30.0:chips+=1
	check(chips>=1 and heard("stone_hit")>stone0,"exit wall cracks: stone chips at the exit surface + stone hit (%d)" % chips)
	while trader.wall_phase==2 and t<6.0:
		await physics_frame;t+=1.0/60.0
	await physics_frame
	check(trader.wall_phase==3 and (trader.exit_slot.floor as Vector2).distance_to(warned.floor)<0.5,"comes out exactly where the wall cracked")
	var back:Node2D=world.get_node_or_null("WT_Llama1")
	var ex_face:Vector2=trader.wall_face_point(trader.exit_slot);var ex_normal:Vector2=(trader.exit_slot.normal as Vector2).normalized()
	check(back!=null and back.emerging and back.wall_clip_active() and back.collision_layer==0 and not back.is_combat_targetable(),"the returning llama walks out of the wall with him (clipped, non-solid, untargetable)")
	check(back!=null and (back.global_position-ex_face).dot(ex_normal)<0.0,"the llama starts inside the wall")
	check(back!=null and trader.llamas_returned==1 and not trader.leashes[1].is_connected_visual(),"leash not drawn while still in the wall")
	while trader.wall_phase!=0 and t<8.0:
		await physics_frame;t+=1.0/60.0
	await seconds(0.2)
	check(is_instance_valid(back) and not back.emerging and not back.wall_clip_active() and back.collision_layer==2 and back.collision_mask==3 and back.is_combat_targetable(),"llama out: normal collision, targetable, clip removed")
	check(is_instance_valid(back) and back.Max_health==350 and back.Master==trader and trader.living_llamas().size()==2 and trader.leashes[1].is_connected_visual() and back.leash_connected,"returned llama is leashed to him again (350 HP)")
	check(is_instance_valid(back) and back.herd_position_clear(back.global_position) and not back.has_meta(&"submission_allow_map_escape"),"returned llama stands body-clear (herd excluded), map-escape exemption cleared (clear %s, meta %s)" % [back.herd_position_clear(back.global_position) if is_instance_valid(back) else false,back.has_meta(&"submission_allow_map_escape") if is_instance_valid(back) else false])
	trader._wall_wait=0.0
	check(await enter_wall(trader),"another wall with a full herd")
	trader._wall_wait=999.0
	t=0.0
	while trader.wall_phase!=0 and t<6.0:
		await physics_frame;t+=1.0/60.0
	check(trader.llamas_returned==1 and trader.living_llamas().size()==2,"no extra llama when none is due")
	# --- Haochen copy of a llama: owned by a plain ball, lives free -------------------------------
	var copy:Node2D=load("res://scenes/creatures/流浪商人_羊驼.tscn").instantiate()
	copy.name="HaochenLlamaCopy";copy.Team="Team1";copy.Master=enemy;copy.set_meta(&"haochen_copy",true)
	copy.position=center
	world.add_child(copy,true)
	var copy_from:Vector2=center
	await seconds(1.0)
	check(is_instance_valid(copy) and copy.health>0 and copy.trader()==null and copy.is_free_agent() and copy.free_moving,"Haochen llama copy (plain-ball Master) lives on with free movement, no leash lookups")
	check(is_instance_valid(copy) and copy.global_position.distance_to(copy_from)>10.0,"the copy moves")
	if is_instance_valid(copy):copy.take_damage(1e9)
	await seconds(0.2)
	# --- controls ------------------------------------------------------------------------------------
	var ids:Array=trader.player_control_action_ids()
	check(ids.has(&"controlled_attack_action") and ids.has(&"controlled_skill_action") and ids.has(&"controlled_middle_action"),"manual controls: potion / wall / milk (%s)" % [ids])
	# --- trader death retires the herd -------------------------------------------------------------
	trader.take_damage(1e9)
	await seconds(1.0)
	check((not is_instance_valid(l0) or l0.health<=0) and (not is_instance_valid(back) or back.health<=0),"remaining llamas (incl. the returned one) retire with the trader")
	var views_ok:bool=true
	for n:Node in world.get_children():
		if String(n.name).begins_with("WT_Leash") and n.has_method(&"is_connected_visual") and n.is_connected_visual():views_ok=false
	check(views_ok,"no connected leash left after the trader's death")
	game.Game_Settings.Have_Team_Damage=saved
	print("WANDERING_TRADER checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
