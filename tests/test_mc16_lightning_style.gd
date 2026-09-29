extends "res://tests/test_mc16_native_feedback.gd"
# Load these before World starts background character/resource prewarming.
# Runtime load() here can stall headless tests despite the texture-preload barrier.
const LIGHTNING_STYLE = preload("res://scripts/effects/我的世界/雷电.gd")
var arc_style:Script # Depends on Game: load after autoload init, before World workers.
var camera:Camera2D
func _trace(stage:String) -> void:
	var file := FileAccess.open("res://tests/mc16_lightning_style_progress.txt",FileAccess.WRITE)
	if file:
		file.store_string(stage+"\n")
		file.close()
func _initialize() -> void:
	_trace("initialize")
	super._initialize()
func check(ok:bool,label:String) -> void:
	_trace(label)
	super.check(ok,label)
func capture(tag:String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/mc16_lightning_"+tag+".png")
func run() -> void:
	_trace("run started")
	game = root.get_node("Game")
	arc_style = load("res://scripts/effects/我的世界/trident_arc.gd")
	saved = game.Game_Settings.duplicate(true)
	saved_stop = game.now_stop_state
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Have_Team_Damage = false
	game.Game_Settings.Ball_Can_Move = true
	game.now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	create_timer(65.0).timeout.connect(func(): finish(2))
	_trace("loading world")
	world = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	_trace("world added")
	world.now_choose_map = "Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	_trace("waiting for preloads")
	if not await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self):
		finish(1)
		return
	_trace("preloads finished")
	center = world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	geometry = load("res://scripts/effects/我的世界/mc16_geometry.gd")
	camera = Camera2D.new()
	world.add_child(camera)
	camera.global_position = center
	camera.zoom = Vector2(2.2,2.2)
	camera.make_current()
	camera.force_update_scroll()
	await process_frame
	var host := Node2D.new()
	world.add_child(host)
	_trace("loading lightning script")
	var style:Script = LIGHTNING_STYLE
	_trace("lightning script loaded")
	var bolt:Node = style.new()
	bolt.setup(center+Vector2(0,90),314159,62.0,0.68)
	host.add_child(bolt)
	bolt.set_process(false)
	var emitted:Array[int] = [0]
	bolt.impact_started.connect(func(_point:Vector2): emitted[0]+=1)
	check(bolt.segment_count==8 and bolt._points.size()==9,"native-like trunk uses eight long angular segments")
	check(bolt.core_width>=7.0 and bolt.inner_glow_width>=16.0 and bolt.outer_glow_width<=32.0,"stronger layered column remains bounded instead of a huge blurry halo")
	check(bolt._branches.size()==2,"only two short upper forks, no fractal spray")
	var monotonic:bool = true
	for i:int in range(bolt._points.size()-1): monotonic = monotonic and bolt._points[i].y<bolt._points[i+1].y
	check(monotonic and bolt._points[-1]==Vector2.ZERO,"single descending trunk ends at the exact impact point")
	var above_ground:bool = true
	for branch:PackedVector2Array in bolt._branches: above_ground = above_ground and branch[-1].y<0.0
	check(above_ground,"upper forks do not manufacture extra ground strikes")
	check(bolt.has_method("_draw_impact_ring") and bolt.has_method("_build_impact_lines"),"compact shock ring and short white streaks are restored")
	bolt._process(0.67)
	check(not bolt._impact_started and emitted[0]==0,"warning duration is unchanged and does not trigger early")
	bolt._process(0.01)
	check(bolt._impact_started and emitted[0]==1,"first visible flash emits exactly one gameplay impact")
	var arc_script:Script = arc_style
	check(bolt.PALETTE==arc_script.PALETTE,"lightning and electrical links share the exact same blue-white palette resource")
	check(bolt.impact_ring_radius()==bolt.impact_radius and bolt.impact_radius==62.0,"initial shock ring uses the true configured attack radius")
	check(bolt._impact_lines.size()==7,"impact emits seven small white streaks rather than the former large spray")
	var compact:bool = true
	for streak:Dictionary in bolt._impact_lines: compact = compact and streak.length<=bolt.impact_radius*0.32 and streak.distance+streak.spawn_offset.length()<=bolt.impact_radius*1.12
	check(compact,"white streak lengths and travel stay compact relative to attack radius")
	check(bolt._white_lines.get_script()==load("res://scripts/effects/hit_burst_effect.gd"),"white lines reuse the original Creeper HitBurst animation, not replacement scratch lines")
	check(not bolt._white_lines.is_processing() and bolt._white_lines.get_parent()==bolt,"white lines use parent clock and clean up with lightning")
	check(bolt._glow.material.blend_mode==CanvasItemMaterial.BLEND_MODE_ADD,"lightning halo really uses additive blending on Compatibility renderer")
	var initial_energy:float = bolt._glow.intensity()
	check(initial_energy>0.9,"first strike has immediate luminous energy")
	var first:PackedVector2Array = bolt._points.duplicate()
	await capture("first")
	bolt._process(0.06)
	check(bolt._points==first,"geometry stays stable throughout one visible stroke")
	check(bolt.impact_ring_radius()>bolt.impact_radius and bolt.impact_ring_radius()<=bolt.impact_radius*1.12,"ring expands only slightly after its exact-radius onset")
	var first_ray:Line2D = bolt._white_lines.get_child(0)
	var ray_points:PackedVector2Array = first_ray.points.duplicate()
	check(first_ray.visible and first_ray.points[0]!=first_ray.points[1] and first_ray.default_color.a>0.0,"Creeper white lines visibly grow and fade in")
	check(bolt._glow.intensity()<initial_energy,"additive halo animates its brightness rather than remaining a static outline")
	await capture("shock")
	bolt._process(0.06)
	check(bolt._flash_slot(bolt._impact_elapsed())==-1,"short dark gap separates visible flashes")
	check(first_ray.points!=ray_points and first_ray.points[1].length()>ray_points[1].length(),"Creeper white lines actually travel outward between frames")
	check(bolt._glow.intensity()<0.1,"flash gap dims the halo rather than leaving a solid light column")
	await capture("gap")
	bolt._process(0.045)
	check(bolt._flash_index==1 and bolt._points!=first,"second short flash gets a new angular route")
	await capture("second")
	var line_id:int = bolt._white_lines.get_instance_id()
	bolt._start_impact()
	check(bolt._white_lines.get_instance_id()==line_id,"second flash cannot spawn duplicate white-line animations")
	check(emitted[0]==1,"visual reflashing and duplicate impact calls cannot repeat damage")
	var clone:Node = style.new()
	clone.setup(bolt.global_position,314159,47.0,0.68)
	host.add_child(clone)
	clone.set_process(false)
	clone._process(0.68)
	check(clone.impact_ring_radius()==47.0,"custom attack radius is honored instead of hardcoded 62")
	clone._process(0.165)
	check(clone._points==bolt._points and clone._branches==bolt._branches,"same seed and flash index produce identical peer geometry")
	clone.hide()
	clone._white_lines.hide()
	check(bolt.bolt_lifetime+bolt.GLOW_SCRIPT.AFTERGLOW_DURATION<bolt.ring_lifetime and bolt._white_lines_end>bolt.ring_lifetime+0.15,"bolt, glow, ring and white lines have visibly separated end times")
	check(bolt.presentation_lifetime()>=bolt._white_lines._end_time+0.02,"parent lifetime covers actual last white-line delay plus duration and cleanup")
	bolt._process(0.255) # impact +0.42s: no lightning/glow, ring and streaks remain.
	check(bolt._flash_slot(bolt._impact_elapsed())<0 and bolt._glow.intensity()==0.0 and bolt.impact_ring_alpha()>0.0,"ring remains after lightning and its afterglow have disappeared")
	var tail_points:PackedVector2Array = first_ray.points.duplicate()
	check(first_ray.visible and not bolt.is_queued_for_deletion(),"white lines keep animating after the bolt disappears")
	await capture("ring_tail")
	bolt._process(0.20) # impact +0.62s: ring gone, last white streak still animates.
	check(bolt.impact_ring_alpha()==0.0 and first_ray.visible and first_ray.default_color.a>0.03 and not bolt.is_queued_for_deletion(),"white lines remain visible after the circle has fully faded")
	check(first_ray.points!=tail_points and emitted[0]==1,"late white-line motion continues without another gameplay impact")
	await capture("white_tail")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		bolt.hide()
		clone.hide()
		bolt._white_lines.hide()
		clone._white_lines.hide()
		var preview:Node = style.new()
		preview.setup(bolt.global_position,314159,62.0,0.68)
		host.add_child(preview)
		preview.set_process(false)
		preview._process(0.68)
		for frame:int in range(35):
			await capture("anim_%02d" % frame)
			if frame<34 and is_instance_valid(preview) and not preview.is_queued_for_deletion(): preview._process(0.025)
		if is_instance_valid(preview): preview.queue_free()
	bolt._process(bolt.presentation_lifetime()+0.01)
	check(bolt.is_queued_for_deletion(),"lightning owner expires only after all independent visual tails finish")
	host.queue_free()
	# Wire cue: actual full-graph pulses, not a direct sound-bank-only probe.
	var owner:Node = spawn("res://scenes/characters/我的世界/溺尸.tscn",center+Vector2(-350,120))
	owner.native_feedback.set_physics_process(false)
	await process_frame
	await process_frame
	var hand:Node = owner._trident
	hand.charge()
	for i:int in range(2):
		var pole:Node = owner._create_trident(100+i)
		pole.set_physics_process(false)
		pole.stick(center+Vector2(-330+i*60,200))
		pole.charge()
	fresh(owner)
	var network:Node = world.get_node("MCTridentNetwork")
	network.pulse()
	check(network.last_pair_count==3,"three charged endpoints still form all three edges")
	check(count(owner,"block.redstone_torch.burnout")==1,"full graph emits one electrical fizz for this caster, not one per edge")
	check(count(owner,"item.trident.thunder")==0,"wire formation no longer impersonates an actual lightning strike")
	var wire:AudioStreamPlayer2D
	for player:Node in get_nodes_in_group("MCNativeSFX"):
		if player.get_meta("mc_sound_event","")=="block.redstone_torch.burnout": wire = player
	check(is_instance_valid(wire) and wire.stream==owner.native_feedback.BANK.EVENTS["block.redstone_torch.burnout"][0] and wire.stream.get_length()>1.2 and wire.stream.get_length()<1.3,"wire uses the short original redstone-burnout clip")
	check(wire.pitch_scale==1.0 and wire.volume_db==-10.0,"wire cue keeps original pitch and a restrained spatial level")
	check(FileAccess.get_sha256("res://audio/characters/溺尸/trident.wire_fizz.ogg")=="4114bc9a87d481f59f08137dcbcc1a2a493b081cfdfc218cd6dd9738986afb3a","wire OGG matches pinned official bytes")
	network.pulse()
	check(count(owner,"block.redstone_torch.burnout")==1,"rapid repeated pulses do not overlap the previous electrical clip")
	owner.native_feedback._clock += 1.5
	network.pulse()
	check(count(owner,"block.redstone_torch.burnout")==2,"a later network pulse can play its own electrical cue")
	game.now_stop_state = true
	var arcs:int = get_nodes_in_group("MCTridentArc").size()
	network.pulse()
	check(count(owner,"block.redstone_torch.burnout")==2 and get_nodes_in_group("MCTridentArc").size()==arcs,"paused network creates neither edges nor audio")
	game.now_stop_state = false
	owner.set_multiplayer_authority(2)
	owner.native_feedback._clock += 2.0
	network.pulse()
	check(count(owner,"block.redstone_torch.burnout")==2,"non-authority replica cannot originate wire audio")
	owner.set_multiplayer_authority(1)
	owner.summon_trident_lightning(hand)
	var actual:Node
	for child:Node in hand.get_children():
		if child.has_signal("impact_started"): actual = child
	actual.set_process(false)
	actual._process(owner.lightning_warning+0.01)
	check(count(owner,"item.trident.thunder")==1 and count(owner,"block.redstone_torch.burnout")==2,"real trident impact retains its own native thunder distinct from wire fizz")
	game.now_stop_state = true
	var elapsed:float = actual._elapsed
	var white_elapsed:float = actual._white_lines._elapsed
	var glow_energy:float = actual._glow.intensity()
	actual._process(0.2)
	check(actual._elapsed==elapsed,"trident pause freezes the new flash animation")
	check(actual._white_lines._elapsed==white_elapsed and actual._glow.intensity()==glow_energy,"pause freezes white-line animation and glow together with lightning")
	game.now_stop_state = false
	actual._process(0.16)
	check(count(owner,"item.trident.thunder")==1,"second visual flash does not duplicate trident thunder")
	# Actual Creeper summon/timer integration, not just a standalone render node.
	var creeper:Node = spawn("res://scenes/characters/我的世界/苦力怕.tscn",center+Vector2(300,150))
	var target:Node = dummy(creeper._self_foot_world_position()+Vector2(25,0))
	var hp:float = target.health
	check(creeper.lightning_damage==38.0 and creeper.lightning_stun_duration==0.55,"Creeper lightning damage/stun parameters are untouched")
	creeper._summon_self_lightning()
	var shared:bool = false
	for child:Node in creeper.get_children():
		if child.has_signal("impact_started"): shared = child.get_script()==style and child.segment_count==8
	check(shared,"real Creeper uses the same new angular lightning renderer")
	await create_timer(0.15).timeout
	check(target.health==hp,"Creeper warning still does not deal premature damage")
	await create_timer(0.6).timeout
	check(creeper._charged and hp-target.health==ceilf(creeper.lightning_damage) and target.dizziness,"Creeper still charges and deals its original timed damage and stun")
	print("MC16_LIGHTNING_STYLE_RESULT checks=",checks," failures=",failures)
	finish(0 if failures==0 else 1)
