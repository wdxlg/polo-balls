extends SceneTree
func _initialize()->void: call_deferred("run")
func run()->void:
 var game=root.get_node("Game");var old:Variant=game.Game_Settings.Map_Background;game.Game_Settings.Map_Background="blue";AudioServer.set_bus_mute(0,true)
 var world=load("res://scenes/world.tscn").instantiate();root.add_child(world);world.now_choose_map="Map10x10";world.refresh_map_presentation();world.control.hide()
 var layer=world.map_group["Map10x10"];var cam=Camera2D.new();world.add_child(cam);cam.make_current()
 cam.global_position=world.return_map_display_rect(layer).get_center();cam.zoom=Vector2.ONE*2.3
 await create_timer(.25).timeout
 for key in ["blue","grass","sand","stone","nether","end"]:
  game.set_runtime_game_setting("Map_Background",key,false)
  await process_frame;await RenderingServer.frame_post_draw
  var rect=world.return_map_display_rect(layer);cam.global_position=rect.get_center();cam.zoom=Vector2.ONE*2.3
  await process_frame;await RenderingServer.frame_post_draw
  var im=root.get_texture().get_image();var h=maxi(1,mini(300,im.get_height()));var w=mini(480,int(im.get_width()*float(h)/im.get_height()));im.resize(w,h,Image.INTERPOLATE_NEAREST)
  print("BG_PREVIEW_"+key+"="+Marshalls.raw_to_base64(im.save_png_to_buffer()))
 game.Game_Settings.Map_Background=old;print("BG_PREVIEW_DONE");quit()
