extends "res://tests/test_mc_minecart.gd"
func sounds(event:String) -> Array[Node]:
	var result:Array[Node] = []
	for node:Node in get_nodes_in_group("MCNativeSFX"):
		if not node.is_queued_for_deletion() and node.get_meta("mc_sound_event","")==event: result.append(node)
	return result
func reset_feedback(net:Node2D) -> void:
	for event:String in ["block.metal.place","block.metal.break"]:
		for player:Node in sounds(event):
			player.stop()
			player.remove_from_group("MCNativeSFX")
			player.queue_free()
		net.set_meta("mc_event_sound_"+event.replace(".","_"),-10000)
	for effect:Node in get_nodes_in_group("MCRailBreakFragments"):
		effect.remove_from_group("MCRailBreakFragments")
		effect.queue_free()
func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60).timeout.connect(func(): finish(2))
	var cart:Node2D = actor("矿车",center)
	await physics_frame
	var net:Node2D = cart.rails
	var o:Vector2 = net.cell_to_world(net.world_to_cell(center))
	var h:PackedVector2Array = PackedVector2Array([o-Vector2(144,0),o+Vector2(144,0)])
	var v:PackedVector2Array = PackedVector2Array([o-Vector2(0,144),o+Vector2(0,144)])
	cart.global_position = h[0]
	net.set_preview(1,h)
	check(sounds("block.metal.place").is_empty() and get_nodes_in_group("MCRailBreakFragments").is_empty(),"preview creates neither placement sound nor fragments")
	net.clear_preview(1)
	check(not build_grid(cart,h).is_empty(),"first actual placement commits")
	check(sounds("block.metal.place").size()==1 and sounds("block.metal.break").is_empty(),"real batch plays one metal placement, no break")
	if sounds("block.metal.place").size()==1:
		check(is_equal_approx(sounds("block.metal.place")[0].pitch_scale,1.2),"placement uses metal-block pitch")
	reset_feedback(net)
	build_grid(cart,h)
	check(sounds("block.metal.place").is_empty() and sounds("block.metal.break").is_empty() and get_nodes_in_group("MCRailBreakFragments").is_empty(),"identical placement cannot spam audio or shatter existing rails")
	net.set_preview(2,v)
	check(get_nodes_in_group("MCRailBreakFragments").is_empty(),"crossing preview does not break committed old rail")
	net.clear_preview(2)
	cart.global_position = v[0]
	build_grid(cart,v)
	check(sounds("block.metal.place").size()==1 and sounds("block.metal.break").size()==1,"crossing commit emits placement and metal break independently")
	var effects:Array[Node] = get_nodes_in_group("MCRailBreakFragments")
	check(effects.size()==1,"only overwritten center shatters, not uncut old line")
	if effects.size()==1:
		var fx:Node2D = effects[0]
		check(fx.get_script().resource_path.ends_with("block_fragments.gd"),"rail uses the shared landing block fragmentation, not item death")
		check(fx.get_meta("rail_point")==o and fx.get_meta("rail_mask")==5 and fx.get_meta("rail_powered"),"fragment snapshot is old powered horizontal rail, not new vertical or preview")
		check(not fx.pieces.is_empty() and fx.pieces.size()<=16,"old sprite becomes cropped visible texture pieces")
		var piece:Dictionary = fx.pieces[0]
		check(piece.sprite.texture is AtlasTexture and piece.height>0 and piece.flight>0,"fragments keep texture and arc before landing")
		var cell_texture:AtlasTexture = piece.sprite.texture.atlas
		check(cell_texture.atlas==net.TILES and cell_texture.region==Rect2(80,16,16,16),"fragments use correct old rail atlas region and powered row")
		check(piece.sprite.global_scale.is_equal_approx(Vector2.ONE*1.5),"fragment scale matches one 24-unit rail cell")
		fx.set_process(false)
		fx.advance(piece.flight*0.5)
		check(piece.sprite.global_position.y < piece.start.lerp(piece.landing,0.5).y,"rail tile chips arc above their ground path")
		fx.advance(piece.flight*0.5)
		check(piece.landed and piece.sprite.global_position.is_equal_approx(piece.landing),"rail tile chips land instead of leaving the map")
	check(net.cell_at(o).mask==10 and net.cell_at(o).powered,"new rail remains intact and retains powered precedence")
	check(not net.cell_at(h[0]).is_empty() and not net.cell_at(h[1]).is_empty(),"non-overlapped old track remains usable")
	var count:int = effects.size()
	net._construction_effect(net.serial,o,[{"point":o,"mask":5,"powered":true}])
	check(get_nodes_in_group("MCRailBreakFragments").size()==count and sounds("block.metal.break").size()==1,"repeated construction event cannot replay sound or fragments")
	reset_feedback(net)
	var ghost:Node2D = cart.RAILS.new()
	ghost.set_multiplayer_authority(2)
	world.add_child(ghost)
	ghost._receive_state(100,net.network_state())
	check(sounds("block.metal.place").is_empty() and sounds("block.metal.break").is_empty() and get_nodes_in_group("MCRailBreakFragments").is_empty(),"late-join state snapshot never replays construction history")
	ghost._construction_effect(net.serial+1,o,[{"point":o,"mask":10,"powered":true}])
	check(sounds("block.metal.place").size()==1 and sounds("block.metal.break").size()==1 and get_nodes_in_group("MCRailBreakFragments").size()==1,"remote event path plays new construction feedback")
	ghost.queue_free()
	reset_feedback(net)
	net.clear_tracks()
	check(sounds("block.metal.break").is_empty() and get_nodes_in_group("MCRailBreakFragments").is_empty(),"round cleanup is silent, not a rail-cut event")
	var blocked:StaticBody2D = wall(o,Vector2(36,36))
	await physics_frame
	cart.global_position = h[0]
	check(net.commit_path(cart,h).is_empty(),"blocked construction rejected")
	check(sounds("block.metal.place").is_empty() and sounds("block.metal.break").is_empty(),"failed placement produces no sound")
	blocked.queue_free()
	print("RAIL FEEDBACK CONTRACTS: ",checks-failures,"/",checks)
	finish(0 if failures==0 else 1)
