extends "res://scripts/training/test_mc_new5.gd"
const SCENE:String="res://scenes/characters/我的世界/凋灵.tscn"
const ARTIFACTS:String="user://wither_intro/"
func check(ok:bool,label:String) -> void:
	super.check(ok,label)
	if ok: print("PASS: "+label)
func advance(actor:Node2D,dt:float) -> void:
	actor.tick_physics(actor.State.Stand,dt)
	actor._update_live_pose(dt)
func run() -> void:
	game=root.get_node("Game")
	saved=game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode=false
	game.Game_Settings.Training_Mode_Type="manual"
	game.Game_Settings.Ball_Can_Move=true
	game.Game_Settings.Have_Team_Damage=false
	game.now_stop_state=false
	AudioServer.set_bus_mute(0,true)
	create_timer(90).timeout.connect(func(): finish(2))
	world=load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene=world,CONNECT_ONE_SHOT)
	root.add_child(world)
	world.now_choose_map="Map50x50"
	world.refresh_map_presentation()
	world.control.hide()
	await create_timer(.5).timeout
	check(await load("res://tests/mc_animation_test_cleanup.gd").wait_for_preloads(self),"preview resources finish loading")
	center=world.return_map_world_rect(world.map_group["Map50x50"]).get_center()
	await clear_units()
	var roster:Array[String]=world.return_all_character_names()
	check(roster.has("凋灵") and not roster.has("凋零"),"selector indexes the canonical Wither mob as 凋灵 only")
	var legacy_scene:PackedScene=world._get_character_scene_any("凋零")
	check(legacy_scene!=null and legacy_scene.resource_path==SCENE,"old character name still resolves to the renamed scene")
	var catalog:Dictionary=load("res://global/translation_catalog.gd").TABLE
	check(catalog.zh.get("凋灵")=="凋灵" and catalog.en.get("凋灵")=="Wither" and catalog.en.get("凋灵信标")=="Wither Beacon","Chinese and English mob/beacon names match the roster")
	check(game._localization._t_for_locale("凋灵","zh",false)=="凋灵" and game._localization._t_for_locale("凋灵","en",false)=="Wither","runtime UI localization actually presents the original Wither name")
	check(load("res://scripts/effects/我的世界/mc_status_effects.gd").SPECS["wither"].zh=="凋零","wither potion effect keeps its distinct official name 凋零")
	var packed:PackedScene=load(SCENE)
	var off_tree:Node2D=packed.instantiate()
	var texture:Texture2D=off_tree.get_preview_texture()
	check(not off_tree.is_inside_tree() and off_tree._bedrock_viewport==null,"selection instance never enters the tree or starts its intro")
	check(texture.resource_path.ends_with("bedrock/wither_preview.png") and texture!=off_tree.BODY,"off-tree selection returns current-rig art, not legacy Wither front")
	check(texture.get_size()==Vector2(384,384),"new preview preserves the live viewport canvas")
	check(off_tree.get_node("Graphics/Image").texture==texture,"scene fallback texture is also the current model")
	off_tree.free()
	var menu:Node2D=world.create_character_preview("凋灵",SCENE,false)
	check(menu!=null and menu.get_node("PreviewImage").texture==texture,"actual selection/portrait factory uses the new art")
	check(not menu is CollisionObject2D and menu.find_children("*","SubViewport",true,false).is_empty(),"selection preview is visual-only, no live 3D or combat side effects")
	world.now_choose_char="凋灵"
	var ghost:Node2D=world.create_ghost_ball()
	check(ghost!=null and ghost.get_node("PreviewImage").texture==texture,"actual placement ghost also uses new art")
	if ghost!=null: ghost.queue_free()
	var actor:Node2D=spawn("凋灵",Vector2.ZERO)
	actor.set_process(false)
	check(actor.summon_time==0 and actor.image.visible and not actor.summoned,"live model is visible immediately at zero intro time")
	check(actor.summon_duration==3.0 and actor._bedrock_model.current_invulnerable,"entire 3-second intro begins in the original blue invulnerable skin")
	check(not actor.has_method("summon_sand_rect") and not actor.has_method("summon_head_rect"),"soul-sand and skull-placement stage removed")
	check(menu.get_node("PreviewImage").scale.is_equal_approx(actor.image.scale) and menu.scale==actor.scale,"selection and live models keep the same calibrated world scale")
	var origin:Vector2=actor.global_position
	actor.take_damage(50)
	check(actor.health==500,"spin keeps original opening immunity")
	advance(actor,.15)
	check(actor._bedrock_model.rotation.y>.5 and actor.image.visible,"rotation is already underway at 0.15s, no 80-percent wait")
	advance(actor,1.35)
	check(absf(actor._bedrock_model.rotation.y-TAU)<.001 and not actor.summoned,"halfway through 3-second spin completes one full turn without waking")
	var time_before:float=actor.summon_time
	var rotation_before:float=actor._bedrock_model.rotation.y
	game.now_stop_state=true
	advance(actor,.5)
	check(actor.summon_time==time_before and actor._bedrock_model.rotation.y==rotation_before,"pause freezes intro progression and rotation")
	game.now_stop_state=false
	advance(actor,1.49)
	check(not actor.summoned and actor.summon_time<3,"no awakening before the full three seconds")
	var threat:Array=actor.get_ai_attack_threats(null)
	check(threat.size()==1 and threat[0].radius==72 and threat[0].damage==45,"last 0.4 seconds declares the smaller real awakening explosion")
	var effects_before:int=get_nodes_in_group("MCExplosion").size()
	advance(actor,.01)
	check(actor.summoned and is_equal_approx(actor.summon_time,3) and actor.image.visible,"wakes exactly at 3 seconds")
	check(not actor._bedrock_model.current_invulnerable and absf(actor._bedrock_model.rotation.y)<.001,"awakening switches back to normal skin and front-facing body")
	check(get_nodes_in_group("MCExplosion").size()==effects_before+1,"awakening emits exactly one original explosion")
	advance(actor,.1)
	check(get_nodes_in_group("MCExplosion").size()==effects_before+1,"next tick cannot replay awakening")
	check(actor.global_position==origin,"intro does not teleport or move the placed character")
	# Appearance messages use the same phase convention at zero and halfway.
	actor._sync_appearance(0,false,false,"",0.0,Vector2.ZERO,origin+Vector2.UP*250)
	actor._update_live_pose(0)
	check(actor.image.visible and absf(actor._bedrock_model.rotation.y)<.001,"synced intro time zero shows new model immediately")
	actor._sync_appearance(1.5,false,false,"",0.0,Vector2.ZERO,origin+Vector2.UP*250)
	actor._update_live_pose(0)
	check(absf(actor._bedrock_model.rotation.y-TAU)<.001,"synced half-intro phase matches the new spin mapping")
	# Check a long physics step independently; no block phase or double awakening.
	actor.summoned=false
	actor.summon_time=0
	var effects:int=get_nodes_in_group("MCExplosion").size()
	advance(actor,3.0)
	check(actor.summoned and actor.summon_time==3 and get_nodes_in_group("MCExplosion").size()==effects+1,"3-second coarse step still awakens once")
	if DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACTS))
		actor._animation_life=0
		actor._bedrock_model.animate(0.0,Vector2.ZERO,true,1.0,false,[Vector2.UP,Vector2.UP,Vector2.UP],1.0)
		await RenderingServer.frame_post_draw
		actor._bedrock_viewport.get_texture().get_image().save_png(ARTIFACTS+"live_reference.png")
		# Record the actual factory preview, followed by the actual 3-second intro.
		var view:=SubViewport.new()
		view.size=Vector2i(384,512)
		view.world_2d=world.get_world_2d()
		view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var captions:=CanvasLayer.new()
		view.add_child(captions)
		var label:=Label.new()
		label.position=Vector2(16,14)
		label.add_theme_font_size_override("font_size",18)
		label.text="Selection preview"
		captions.add_child(label)
		var camera:=Camera2D.new()
		camera.zoom=Vector2(10,10)
		camera.position=center
		view.add_child(camera)
		camera.make_current()
		world.add_child(menu)
		menu.global_position=center
		actor.get_node("Health_Bar").hide()
		actor.hide()
		# Existing test explosions must not cover the selection preview.
		for effect:Node in get_nodes_in_group("MCExplosion"): effect.queue_free()
		await process_frame
		for frame:int in range(150):
			if frame==30:
				menu.hide()
				actor.show()
				actor.summoned=false
				actor.summon_time=0
				actor._animation_life=0
				actor._summon_sound_played=false
			if frame>=30:
				advance(actor,1.0/30.0)
				label.text="Awake" if actor.summoned else "Spawn: %.2fs / 3.00s"%actor.summon_time
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_png(ARTIFACTS+"frame_%03d.png"%frame)
		check(actor.summoned,"150 GPU frames cover selection, the complete spin and awakening")
		view.queue_free()
	menu.queue_free()
	print("WITHER_INTRO: %d checks / %d failures"%[checks,failures])
	await clear_units()
	finish(0 if failures==0 else 1)
