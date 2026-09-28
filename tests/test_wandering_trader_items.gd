extends "res://tests/test_wandering_trader.gd"
## 流浪商人物品 (2026-09-29): item frame, roll rules, wall-texture exit crumbs and the nine items
## (火药 / 蓝冰 / 河豚桶 / 滴水石锥 / 粘液球 / 干草块 / 马铃薯 / 仙人掌 / 热带鱼桶) in a real World.
## Loaded at run time: these scripts use the Game autoload, which a -s script cannot see at compile time.
var CATALOG:GDScript
var CRUMBS_SCRIPT:GDScript
var STATUS:GDScript

func items_of(kind:StringName) -> Array:
	return get_nodes_in_group(&"MCWanderingTraderItem").filter(func(n:Node) -> bool: return n.get(&"kind")==kind and not n.is_queued_for_deletion())

func wait_until(cond:Callable,limit:float) -> bool:
	var t:float=0.0
	while not cond.call() and t<limit:
		await physics_frame;t+=1.0/60.0
	return cond.call()

func dummy(n:String,team:String,pos:Vector2) -> Node2D:
	var u:Node2D=unit("res://scenes/ball.tscn",n,team,pos)
	await process_frame
	hold(u);u.health=u.Max_health
	return u

func run() -> void:
	CATALOG=load("res://scripts/characters/我的世界/wandering_trader/items/catalog.gd")
	CRUMBS_SCRIPT=load("res://scripts/characters/我的世界/wandering_trader/items/crumbs.gd")
	STATUS=load("res://scripts/effects/我的世界/mc_status_effects.gd")
	create_timer(260.0,true,false,true).timeout.connect(func(): print("WANDERING_TRADER_ITEMS_TIMEOUT"); quit(2))
	game=root.get_node("Game")
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
	await process_frame
	trader._invisibility_wait=999.0;trader._wall_wait=999.0;trader._milk_wait=999.0
	for i:int in range(6):await process_frame
	var herd:Array=trader.living_llamas()
	check(herd.size()==2,"herd spawned (%d)" % herd.size())
	# Isolate the item damage: no llama spit and no trader / llama body-contact hits on the dummies.
	for l:Node in herd:
		hold(l);l.spit_range=0.0
	for u:Node in [trader]+herd:
		var contact:Area2D=u.get_node_or_null(^"hitbox") as Area2D
		if contact!=null:contact.set_deferred(&"monitoring",false)
	# --- frame --------------------------------------------------------------------------------------
	var frame:Node2D=trader.item_frame
	check(is_instance_valid(frame) and frame.top_level and frame.get_parent()==trader,"item frame is a world-space child of the trader")
	await physics_frame
	check(frame.global_position.y>trader.global_position.y+8.0 and absf(frame.global_position.x-trader.global_position.x)<0.5,"frame hangs under the trader (%s vs %s)" % [frame.global_position,trader.global_position])
	check(trader.held_item==&"" and frame.kind==&"","frame starts empty")
	await process_frame
	check(frame.self_modulate.a==0.0 and frame.SIZE<=8.0,"empty frame is hidden, frame is small (%.0f px)" % frame.SIZE)
	check(trader.player_control_action_ids().has(&"controlled_item_action"),"manual control: key for the held item")
	# --- roll rules ---------------------------------------------------------------------------------
	trader.item_show_time=999.0;trader.item_delay_min=999.0;trader.item_delay_max=999.0
	var seen:Dictionary={}
	for i:int in range(300):
		seen[trader.roll_item()]=true
	check(not seen.has(CATALOG.HAY) and not seen.has(CATALOG.POTATO),"no hay / potato while nobody is hurt")
	var others_ok:bool=true
	for kind:StringName in [CATALOG.GUNPOWDER,CATALOG.BLUE_ICE,CATALOG.PUFFERFISH,CATALOG.DRIPSTONE,CATALOG.SLIME_BALL,CATALOG.CACTUS,CATALOG.TROPICAL_FISH]:
		if not seen.has(kind):others_ok=false
	check(others_ok,"the other seven items all roll (%s)" % [seen.keys()])
	trader.health=trader.Max_health-50;herd[0].health=herd[0].Max_health-100
	seen.clear()
	for i:int in range(300):
		seen[trader.roll_item()]=true
	check(seen.has(CATALOG.HAY) and seen.has(CATALOG.POTATO) and seen.size()==9,"hurt llama / hurt trader unlock hay and potato (%d kinds)" % seen.size())
	check(frame.kind==trader.held_item and trader.held_item!=&"","frame shows the held item (%s)" % trader.held_item)
	await process_frame
	check(frame.self_modulate.a==1.0,"frame visible while he holds an item")
	trader.give_item(&"");trader.health=trader.Max_health;herd[0].health=herd[0].Max_health
	# --- wall exit: roll + wall-texture crumbs ------------------------------------------------------
	trader.item_show_time=999.0
	var crumbs_before:int=get_nodes_in_group(&"MCWanderingTraderFx").filter(func(n:Node) -> bool: return n.get_script()==CRUMBS_SCRIPT).size()
	var rolled0:int=trader.items_rolled
	var bursts0:int=trader.wall_crumb_bursts
	var entered:bool=await enter_wall(trader)
	check(entered,"trader enters the wall")
	var tex_ok:bool=false
	var saw_crumbs:bool=false
	var t:float=0.0
	var entry_bursts:int=-1 # streams started before he is hidden
	var entry_streaming:bool=false # a crumb stream alive (and emitting) while he is still entering
	var exit_streaming:bool=false
	var falling:bool=false
	while trader.wall_phase!=0 and t<9.0:
		if trader.wall_phase==2 and entry_bursts<0:entry_bursts=trader.wall_crumb_bursts-bursts0
		var stream:Node2D=trader._wall_stream
		if stream!=null and is_instance_valid(stream) and stream.alive_count()>0:
			if trader.wall_phase==1:entry_streaming=true
			if trader.wall_phase==3:exit_streaming=true
			for p:Dictionary in stream.parts:
				if p.age>0.15 and (p.vel as Vector2).y>0.0:falling=true
		for n:Node in get_nodes_in_group(&"MCWanderingTraderFx"):
			if n.get_script()==CRUMBS_SCRIPT:
				saw_crumbs=true
				if n.get(&"texture")!=null:tex_ok=true
		await physics_frame;t+=1.0/60.0
	check(trader.wall_phase==0 and trader.items_rolled==rolled0+1 and trader.held_item!=&"","wall exit rolls one item into the frame (%s)" % trader.held_item)
	check(saw_crumbs and tex_ok and trader.wall_crumb_bursts>=2,"wall entry / exit spray textured block crumbs (%d bursts)" % trader.wall_crumb_bursts)
	check(entry_bursts>=1 and entry_streaming,"entry crumbs stream while he walks into the wall, before he is hidden (%d, %s)" % [entry_bursts,entry_streaming])
	check(exit_streaming,"exit crumbs stream while he walks out of the wall")
	check(falling,"wall crumbs fall under gravity")
	var tile_src:Dictionary={}
	var slots:Array[Dictionary]=WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect())
	if not slots.is_empty():tile_src=CRUMBS_SCRIPT.wall_source(trader,WALL_SCRIPT.face_point(slots[0]),slots[0].normal)
	check(tile_src.get("texture")!=null and (tile_src.region as Rect2).size.x>0.0,"crumb source = the wall tile's atlas texture region (%s)" % [tile_src.get("region")])
	trader.give_item(&"")
	trader._wall_wait=999.0
	# fixed quiet spot for the rest: trader parked, his AI movement off
	trader.Speed=0.0
	trader.global_position=center
	for i:int in range(5):await physics_frame
	# --- gunpowder ---------------------------------------------------------------------------------
	var enemy:Node2D=await dummy("E1","Team1",center+Vector2(60,-50))
	trader.item_delay_min=0.3;trader.item_delay_max=0.3
	trader.give_item(CATALOG.GUNPOWDER)
	check(frame.kind==CATALOG.GUNPOWDER,"frame shows gunpowder while waiting")
	await wait_until(func() -> bool: return trader.is_swinging_item(),1.5)
	var hand:Sprite2D=trader._item_sprite
	await process_frame
	check(trader.is_swinging_item() and trader._item_anchor.visible and hand.texture==CATALOG.icon(CATALOG.GUNPOWDER) and items_of(CATALOG.GUNPOWDER).is_empty(),"use = item taken into his hand first (no effect yet)")
	check(trader.held_item==&"" and frame.self_modulate.a==0.0,"the frame empties and hides while it is in his hand")
	var rot_min:float=0.0
	var rot_max:float=0.0
	while trader.is_swinging_item():
		rot_min=minf(rot_min,hand.rotation);rot_max=maxf(rot_max,hand.rotation)
		await physics_frame
	check(rot_min<-0.1 and rot_max>0.1 and rot_max-rot_min<1.0,"small swing in the hand (%.2f..%.2f rad)" % [rot_min,rot_max])
	check(not items_of(CATALOG.GUNPOWDER).is_empty() and not trader._item_anchor.visible,"at the effect the item vanishes from the hand at once")
	var pile:Array=items_of(CATALOG.GUNPOWDER)
	check(pile.size()==1 and trader.held_item==&"" and frame.kind==&"","gunpowder dropped after its delay, frame empties")
	if pile.size()==1:
		var gp:Node2D=pile[0]
		check(gp.life==INF,"gunpowder never fizzles on its own")
		var ally:Node2D=herd[1]
		var ally_pos:Vector2=ally.global_position
		ally.global_position=gp.global_position
		await seconds(0.8)
		check(is_instance_valid(gp) and not gp.triggered,"the trader's own llama does not set it off")
		ally.global_position=ally_pos
		await seconds(0.2)
		var hp0:float=enemy.health
		var boom0:int=heard("item_explode")
		enemy.global_position=gp.global_position
		await seconds(0.6)
		check(not is_instance_valid(gp) or gp.exploded,"enemy stepping on it sets it off")
		check(absf((hp0-enemy.health)-50.0)<0.01,"explosion deals 50 to the enemy (%.1f)" % (hp0-enemy.health))
		check(heard("item_explode")>boom0 and trader.gunpowder_hits>=1,"vanilla explosion sound")
	enemy.global_position=center+Vector2(60,-50)
	# --- blue ice -----------------------------------------------------------------------------------
	trader.item_show_time=0.1
	trader.give_item(CATALOG.BLUE_ICE)
	await wait_until(func() -> bool: return not items_of(CATALOG.BLUE_ICE).is_empty(),1.0)
	var ices:Array=items_of(CATALOG.BLUE_ICE)
	check(ices.size()==1,"blue ice placed right after the exit")
	if ices.size()==1:
		var ice0:Node2D=ices[0]
		var ice_z:int=ice0.z_index+(ice0.get_parent() as CanvasItem).z_index if ice0.z_as_relative else ice0.z_index
		var unit_z:int=trader.z_index+(trader.get_parent() as CanvasItem).z_index
		var map_z:int=-100
		for layer:TileMapLayer in WALL_SCRIPT.map_layers(WALL_SCRIPT.current_map(world)):
			var parent_z:int=(layer.get_parent() as CanvasItem).z_index if layer.get_parent() is CanvasItem else 0
			map_z=maxi(map_z,layer.z_index+(parent_z if layer.z_as_relative else 0))
		check(ice_z<unit_z and ice_z>map_z,"blue ice sits on the floor layer: above the tiles, under the characters (abs z: ice %d, unit %d, map %d)" % [ice_z,unit_z,map_z])
		check(is_equal_approx(ice0.rect().size.x,ice0.BLOCK*3.0) and ice0.BLOCKS==3,"blue ice is a 3x3 block patch (%.1f px)" % ice0.rect().size.x)
	var runner:Node2D=unit("res://scenes/ball.tscn","Runner","Team1",center)
	await process_frame
	runner.Has_Collision_Damage=false;runner.Can_Attack=false;runner.Can_Skill=false;runner.health=runner.Max_health
	if ices.size()==1:
		var ice:Node2D=ices[0]
		# open lane toward the left wall, away from the parked trader / held llamas
		var lane:Dictionary=WALL_SCRIPT.nearest_slot(WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect()),Vector2(rect.position.x,center.y-20.0))
		var face:Vector2=WALL_SCRIPT.face_point(lane)
		var out:Vector2=(lane.normal as Vector2).normalized()
		for l:Node2D in herd:l.global_position=center-out*20.0+Vector2(0,30)
		ice.global_position=face+out*44.0
		check(ice.life==INF,"blue ice has no timer")
		runner.global_position=face+out*48.0
		runner.direction=-out;runner.Speed=40.0
		var hp1:float=runner.health
		var peak:float=0.0
		var boost:Node=null
		for i:int in range(24):
			await physics_frame
			boost=runner.get_node_or_null(^"WTIceBoost")
			if boost!=null:peak=maxf(peak,boost.momentum.length())
		check(peak>10.0,"enemy on blue ice gains extra speed (%.1f)" % peak)
		t=0.0
		while trader.ice_wall_hits==0 and t<4.0:
			await physics_frame;t+=1.0/60.0
		boost=runner.get_node_or_null(^"WTIceBoost")
		check(trader.ice_wall_hits>=1 and runner.health<hp1,"hitting a wall before the boost wore off hurts (%.1f)" % (hp1-runner.health))
		var ally_on:Node2D=herd[0]
		ally_on.global_position=ice.global_position
		for i:int in range(10):await physics_frame
		check(ally_on.get_node_or_null(^"WTIceBoost")!=null,"neutral ice: his own llama gets the boost too")
		ice.expire()
	if is_instance_valid(runner):runner.take_damage(1e9)
	await seconds(0.2)
	# --- pufferfish --------------------------------------------------------------------------------
	var puff:Node2D=trader.release_fish(true)
	await physics_frame
	check(is_instance_valid(puff) and puff.Type==3 and puff.Master==trader and puff.Team==trader.Team and puff.Max_health==50,"pufferfish: killable summon on his team (50 HP)")
	var y0:float=puff.global_position.y
	var rot0:float=puff.image.rotation
	await seconds(3.0)
	check(puff.hops>=2,"pufferfish falls to the floor and hops (%d hops)" % puff.hops)
	check(puff.global_position.y>y0-80.0 and puff.global_position.y<=rect.end.y,"stays in the arena under gravity")
	check(absf(angle_difference(puff.image.rotation,rot0))>0.01 or absf(puff.spin)>0.01,"body tumbles freely")
	await seconds(2.0)
	check(puff.bounces>=1,"bounces left/right off walls/characters (%d)" % puff.bounces)
	var victim:Node2D=await dummy("E2","Team1",puff.global_position)
	var hpv:float=victim.health
	await seconds(0.3)
	victim.global_position=puff.global_position
	await seconds(0.3)
	check(puff.stings>=1 and victim.health<hpv,"touching an enemy stings it (%.1f)" % (hpv-victim.health))
	check(STATUS.active(victim,"poison"),"sting poisons")
	check(puff.puffed,"puffs up near an enemy")
	puff.take_damage(1e9)
	await seconds(0.2)
	check(not is_instance_valid(puff) or puff.health<=0,"pufferfish can be killed")
	if is_instance_valid(victim):victim.take_damage(1e9)
	# --- tropical fish ------------------------------------------------------------------------------
	var fish:Node2D=trader.release_fish(false)
	await physics_frame
	check(is_instance_valid(fish) and fish.Max_health==75 and fish.Team==trader.Team and not fish.puffer,"tropical fish: 75 HP on his team")
	check(fish.ram_damage(30.0)==0.0 and is_equal_approx(fish.ram_damage(300.0),15.0) and fish.ram_damage(200.0)<fish.ram_damage(300.0) and fish.ram_damage(2000.0)==fish.ram_damage_max,"ram damage scales with the fish's own speed (0 / %.1f / %.1f / cap %.1f)" % [fish.ram_damage(200.0),fish.ram_damage(300.0),fish.ram_damage_max])
	var calm:Node2D=await dummy("E3","Team1",fish.global_position+Vector2(0,-40))
	await seconds(0.3)
	var hpc:float=calm.health
	var rammed:bool=false
	for i:int in range(120):
		if fish.fall_velocity.length()>=fish.ram_min_speed+40.0:
			calm.global_position=fish.global_position
			await physics_frame
			if fish.rams>0:
				rammed=true
				break
		else:
			calm.global_position=fish.global_position+Vector2(0,-40)
			await physics_frame
	check(rammed and fish.stings==0,"tropical fish rams an enemy (no sting / poison)")
	check(fish.last_ram_damage>=fish.ram_damage(fish.ram_min_speed+40.0)-0.01 and absf((hpc-calm.health)-fish.last_ram_damage)<0.01,"ram damage from its speed (%.1f)" % fish.last_ram_damage)
	check(not STATUS.active(calm,"poison"),"tropical ram does not poison")
	calm.global_position=fish.global_position+Vector2(0,-40)
	fish.fall_velocity=Vector2(20,0)
	check(fish.ram_damage(fish.fall_velocity.length())==0.0,"a slow drift does no ram damage")
	await seconds(1.0)
	check(fish.hops>=1,"tropical fish flops like the pufferfish")
	calm.take_damage(1e9)
	trader.release_fish(false)
	trader.release_fish(false)
	await seconds(0.2)
	var alive:int=get_nodes_in_group(&"MCTraderFish").filter(func(n:Node) -> bool: return not n.puffer and n.health>0).size()
	check(alive>=3,"no fish cap: every released fish stays (%d)" % alive)
	check(fish.dry_time<=0.0,"fish never dry out")
	for n:Node in get_nodes_in_group(&"MCTraderFish"):n.take_damage(1e9)
	# --- dripstone ----------------------------------------------------------------------------------
	trader.give_item(CATALOG.DRIPSTONE)
	trader.Speed=80.0
	var near:Dictionary=WALL_SCRIPT.nearest_slot(WALL_SCRIPT.wall_slots(world,trader.mc_arena_rect()),trader.global_position)
	trader.direction=-(near.normal as Vector2).normalized()
	await wait_until(func() -> bool: return not items_of(CATALOG.DRIPSTONE).is_empty(),5.0)
	trader.Speed=0.0
	var spikes:Array=items_of(CATALOG.DRIPSTONE)
	check(spikes.size()==1 and trader.held_item==&"","touching a wall places the dripstone spike")
	if spikes.size()==1:
		var spike:Node2D=spikes[0]
		check((spike.normal as Vector2).dot(near.normal)>0.7,"spike points out of the wall")
		check(spike.life==INF,"dripstone never expires on its own")
		trader.global_position=center
		await seconds(1.0)
		var target:Node2D=await dummy("E4","Team1",center)
		target.global_position=spike.global_position+spike.normal*(spike.LENGTH+CATALOG.body_rect(target).size.x*0.5-3.0)
		var hps:float=target.health
		await seconds(0.2)
		check(hps-target.health>=17.9,"spike damages an enemy (%.1f)" % (hps-target.health))
		target.global_position=center+Vector2(0,60)
		var llama:Node2D=herd[0]
		var hpl:float=llama.health
		var lpos:Vector2=llama.global_position
		llama.global_position=spike.global_position+spike.normal*(spike.LENGTH+CATALOG.body_rect(llama).size.x*0.5-3.0)
		await seconds(0.1)
		check(llama.health<hpl,"neutral: it hurts his own llama too")
		llama.global_position=lpos
		llama.health=llama.Max_health
		spike.expire()
		target.take_damage(1e9)
	# --- slime ball ---------------------------------------------------------------------------------
	trader.global_position=center;trader.direction=Vector2.ZERO
	await physics_frame
	var mark:Node2D=await dummy("E5","Team1",center+Vector2(50,0))
	var hpm:float=mark.health
	trader.item_show_time=0.1
	trader.give_item(CATALOG.SLIME_BALL)
	await seconds(2.2)
	check(trader.slime_hits>=1 and hpm-mark.health>=9.9,"slime ball on a parabola hits the enemy (%.1f)" % (hpm-mark.health))
	check(STATUS.active(mark,"slowness"),"slime ball slows")
	mark.take_damage(1e9)
	await seconds(0.1)
	# ballistic arc: rises, then drops (aim on the hand's own height), with a falling slime trail
	var hand0:Vector2=trader.hand_point()
	trader._throw(CATALOG.SLIME_BALL,null,hand0+Vector2(40,0),0.5)
	var shot:Node2D=null
	for n:Node in get_nodes_in_group(&"MCWanderingTraderItem"):
		if n.get(&"kind")==CATALOG.SLIME_BALL and not n.done:shot=n as Node2D
	var min_y:float=hand0.y
	var after_peak:float=-1e9
	var trail_fall:bool=false
	var trail_node:Node2D=null
	for i:int in range(30):
		await physics_frame
		if shot==null or not is_instance_valid(shot):break
		min_y=minf(min_y,shot.global_position.y)
		after_peak=shot.global_position.y
		if shot.trail!=null and is_instance_valid(shot.trail):
			trail_node=shot.trail
			for p:Dictionary in trail_node.parts:
				if p.age>0.1 and (p.vel as Vector2).y>0.0:trail_fall=true
	check(min_y<hand0.y-8.0 and after_peak>min_y+4.0,"slime ball flies a real parabola (rise %.1f, then drop %.1f)" % [hand0.y-min_y,after_peak-min_y])
	check(trail_node!=null and trail_node.emitted>=5 and trail_fall,"slime ball leaves a falling slime-particle trail (%d)" % (trail_node.emitted if trail_node!=null else 0))
	await seconds(1.0)
	var outside:Vector2=Vector2(rect.position.x-80.0,center.y)
	trader._throw(CATALOG.SLIME_BALL,null,outside,0.5)
	await seconds(0.8)
	check(trader.slime_wall_bounces>=1,"slime ball bounces off a wall with a slime splash")
	# --- hay ------------------------------------------------------------------------------------
	var hurt_llama:Node2D=herd[1]
	hurt_llama.health=hurt_llama.Max_health-150
	var hpb:float=hurt_llama.health
	trader.give_item(CATALOG.HAY)
	await seconds(2.0)
	check(trader.hay_healed>=60 and hurt_llama.health>hpb,"hay bale flies to the hurt llama and heals it (+%d)" % trader.hay_healed)
	# --- potato ---------------------------------------------------------------------------------
	trader.health=trader.Max_health-80
	var hpt:float=trader.health
	var eat0:int=heard("item_eat")
	trader.give_item(CATALOG.POTATO)
	await wait_until(func() -> bool: return trader.is_swinging_item(),1.0)
	await process_frame
	check(trader._item_sprite.texture==CATALOG.icon(CATALOG.POTATO) and trader._item_anchor.visible,"potato is swung in the hand before it is eaten")
	await seconds(1.9)
	check(trader.health-hpt>=39.9 and trader.potato_healed>=40,"potato is eaten at once and heals (+%d)" % (trader.health-hpt))
	check(heard("item_eat")>=eat0+3 and heard("item_burp")>=1,"three bites + burp")
	# --- cactus ---------------------------------------------------------------------------------
	trader.direction=Vector2.RIGHT
	trader.item_delay_min=0.2;trader.item_delay_max=0.2
	trader.give_item(CATALOG.CACTUS)
	await wait_until(func() -> bool: return not items_of(CATALOG.CACTUS).is_empty(),2.0)
	var cacti:Array=items_of(CATALOG.CACTUS)
	check(cacti.size()==1,"cactus placed a while after the exit")
	if cacti.size()==1:
		var cactus:Node2D=cacti[0]
		check(cactus.life==INF,"cactus never expires on its own")
		trader.global_position=center+Vector2(0,45);trader.direction=Vector2.ZERO
		cactus.global_position=center+Vector2(0,-20) # open floor, clear of the tiny map's walls
		await physics_frame
		check(cactus.body.collision_layer==1,"cactus is a solid obstacle (layer 1)")
		var probe:Node2D=await dummy("E6","Team1",center+Vector2(0,70))
		var r:Rect2=cactus.rect()
		var half:Vector2=CATALOG.body_rect(probe).size*0.5
		var hpp:float=probe.health
		probe.global_position=Vector2(r.position.x-half.x-0.5,r.get_center().y)
		await seconds(0.1)
		check(hpp-probe.health>=7.9,"touching its left side hurts (%.1f)" % (hpp-probe.health))
		hpp=probe.health
		probe.global_position=Vector2(r.get_center().x,r.position.y-half.y-0.5)
		await seconds(0.6)
		check(probe.health==hpp,"its top face is harmless")
		var hph:float=trader.health
		var tpos:Vector2=trader.global_position
		trader.global_position=Vector2(r.end.x+CATALOG.body_rect(trader).size.x*0.5+0.5,r.get_center().y);trader.direction=Vector2.ZERO
		await seconds(0.1)
		check(trader.health<hph,"neutral: its side hurts the trader too")
		trader.global_position=tpos
		probe.take_damage(1e9)
	print("WANDERING_TRADER_ITEMS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
