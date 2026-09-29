extends "res://tests/test_mc_frontier.gd"
func run() -> void:
	var o:Vector2=await setup_world()
	create_timer(90).timeout.connect(func():finish(2))
	var source:Node2D=actor("烈焰人",o+Vector2(-180,0))
	var victim:Node2D=dummy(o)
	var ally:Node2D=dummy(o+Vector2(5,0),"Team0")
	var patch:Node2D=load("res://scripts/effects/我的世界/烈焰火场.gd").new()
	world.add_child(patch)
	patch.setup(source,"Team0",o,34,4.5,0.5,0.11,2.2,0.05)
	patch.set_physics_process(false)
	var viola:Node2D=spawn("res://scenes/characters/乐队/薇欧拉.tscn",o+Vector2(220,0),"Team0")
	viola.state_machine.set_physics_process(false); viola.set_process(false)
	var large:Node2D=load("res://scripts/effects/薇欧拉_火场.gd").new()
	world.add_child(large); large.setup(viola,o+Vector2(130,0),{"radius":58,"tick_damage":8,"burn_tick_damage":5})
	large.set_physics_process(false); large.elapsed=0.3; large._update_main_fire_visual()
	await physics_frame
	await process_frame
	check(patch.FIRE_FRAMES==large.FIRE_FRAMES,"Blaze ground fire and Viola large fire share the same new native animation")
	var frames:SpriteFrames=patch.FIRE_FRAMES
	check(frames.get_frame_count(&"default")==32 and frames.get_animation_speed(&"default")==20 and frames.get_animation_loop(&"default"),"native ground fire preserves 32-frame looping at one MC tick per frame")
	var first:AtlasTexture=frames.get_frame_texture(&"default",0)
	var middle:AtlasTexture=frames.get_frame_texture(&"default",16)
	check(first.atlas.resource_path.ends_with("MCFire/fire_0.png") and first.region==Rect2(0,256,16,16) and middle.region==Rect2(0,0,16,16),"fire_0 follows official mcmeta order 16..31 then 0..15")
	check(patch._main_fire.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and large._main_fire.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"both ground fires preserve pixel texture without blur")
	check(patch._radius==34 and patch._duration==4.5 and large.radius==58 and large.duration==5,"visual replacement does not change fire range or duration")
	check(is_equal_approx(patch._main_fire.global_position.y+patch._fire_base_height*0.5,patch._fire_cell_rect.end.y),"Blaze flame bottom aligns with the map cell bottom")
	check(large._main_fire.position==Vector2.ZERO,"Viola keeps her original impact-centered large-fire anchoring")
	var before:float=victim.health
	var ally_before:float=ally.health
	patch._damage_inside(source)
	check(victim.health<before and ally.health==ally_before,"ground fire still damages enemies and respects team filtering")
	var burn:Node2D=victim.get_node_or_null("MinecraftBlazeBurn")
	check(burn!=null and burn._minecraft_burn_visual!=null,"real ground fire hit creates the native burning overlay")
	burn.set_physics_process(false)
	var burn_frames:SpriteFrames=burn.MINECRAFT_BURN_FRAMES
	var burn_first:AtlasTexture=burn_frames.get_frame_texture(&"burn",0)
	check(burn_frames.get_frame_count(&"burn")==32 and burn_frames.get_animation_speed(&"burn")==20 and burn_first.atlas.resource_path.ends_with("MCFire/fire_1.png"),"enemy burning uses separate native fire_1 animation")
	var bounds:Rect2=burn._target_local_bounds()
	var flame:AnimatedSprite2D=burn._minecraft_burn_visual
	var bottom:float=flame.position.y+16.0*flame.scale.y*0.5
	check(is_equal_approx(bottom,bounds.end.y),"burning animation remains aligned with victim's feet")
	check(is_equal_approx(flame.scale.y/flame.scale.x,197.0/151.0),"burning silhouette preserves previous width/height coverage")
	var expected:float=source.effective_outgoing_damage(burn.tick_damage)
	before=victim.health; burn._physics_process(0.56)
	check(is_equal_approx(before-victim.health,ceilf(expected)),"periodic burn damage remains unchanged")
	var count:int=victim.get_child_count()
	burn.refresh(source,3.2,burn.tick_damage)
	check(victim.get_child_count()==count and burn.remaining==3.2,"refresh keeps one overlay rather than duplicating it")
	# Viola still applies her own fire field hit and status using unchanged gameplay logic.
	victim.global_position=large.global_position
	before=victim.health; large._apply_fire_tick()
	check(victim.health<before and victim.get_node_or_null("WarGoddessBurnStatus")!=null,"Viola's new large flame still deals damage and applies its normal status")
	patch._physics_process(4.6)
	check(patch.is_queued_for_deletion(),"ground flame expires at its existing lifetime")
	burn.remaining=0.01; burn._physics_process(0.02)
	check(burn.is_queued_for_deletion(),"burning overlay cleans up when status expires")
	large._physics_process(6)
	check(large.is_queued_for_deletion(),"large fire and its existing particles clean up normally")
	print("MC NATIVE FIRE: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
