extends "res://tests/test_rotation_frames_challenge.gd"
## 轮换一键布局：每队最多一个位置、人物列表按顺序勾选、再按一次把每队第 k 个勾选人物
## 放进同一个新轮次（接在已有轮次后面）。

func roster(side:String) -> Array:
	var result:Array = []
	for record:Dictionary in world._rotation_rosters[side]: result.append([str(record.char),int(record.round),Vector2(float(record.x),float(record.y))])
	return result

func fake_char(name:String) -> Button:
	var button := Button.new()
	button.set_meta("choice_value",name)
	return button

func shot(label:String) -> void:
	# Screens only exist with a real renderer; headless never posts a frame.
	if DisplayServer.get_name()=="headless": return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_temp_dir().path_join("quick_layout_"+label+".png"))

func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():push_error("QUICK_LAYOUT_TIMEOUT");quit(2))
	game=root.get_node("Game");saved=game.Game_Settings.duplicate(true)
	var scratch_settings:String=OS.get_temp_dir().path_join("quick_layout_test_settings.cfg")
	# Game saves settings again on exit, so the redirect stays until quit.
	game._settings_storage_path=scratch_settings
	game.Game_Settings.Training_Mode=false;game.Game_Settings.Development_Mode=false;game.Game_Settings.Training_Mode_Type="rotation"
	game.Game_Settings.Rotation_Match_Type="challenge";game.Game_Settings.Training_Wheel_Battle=false
	game.Game_Settings.Rotation_Multi_Characters=false
	game.now_stop_state=false;AudioServer.set_bus_mute(0,true)
	world=load("res://scenes/world.tscn").instantiate();world.tree_entered.connect(func():current_scene=world,CONNECT_ONE_SHOT);root.add_child(world)
	if is_instance_valid(world._mc_prewarmer):world._mc_prewarmer.free()
	world._mc_prewarmer=null;await process_frame
	world.now_choose_map="Map10x10";world.refresh_map_presentation();world.set_physics_process(false)
	for alias:String in ["ball","ballA","ballB"]: world.Characters_Dic[alias]=load("res://scenes/ball.tscn")
	world.control.show();world.control.team.show();world.control._sync_training_mode_controls();await process_frame
	var ui:Control=world.control
	var rect:Rect2=world.return_map_world_rect(world.map_group[world.now_choose_map])
	var blue_spot:Vector2=rect.position+rect.size*Vector2(0.75,0.5)
	var red_spot:Vector2=rect.position+rect.size*Vector2(0.25,0.5)
	var button:Button=ui.rotation_quick_layout_button
	check(is_instance_valid(button) and button.is_visible_in_tree() and button.text==game.ui_t("UI_ROTATION_QUICK_LAYOUT"),"rotation panel shows the quick layout button")
	check(world._has_character_scene_any("ballA") and world._has_character_scene_any("ballB"),"test aliases resolve as characters")
	await world.create_char("__rotation_left","ball",rect.get_center()+Vector2(20,0),1)
	check(roster("left").size()==1 and roster("left")[0][1]==1,"an existing manual round 1 is present")
	ui.change_choose_team("ball","now_choose_char")
	ui._on_rotation_quick_layout_pressed()
	check(world.rotation_quick_layout_active() and world.now_choose_char=="","first press enters position placement and clears the placing character")
	check(button.text==game.ui_t("UI_ROTATION_QUICK_LAYOUT_APPLY"),"button turns into the apply action")
	var list_button:Button=null
	for child:Node in ui.char_box.get_children():
		if child is Button and not child.is_queued_for_deletion(): list_button=child;break
	check(list_button!=null and list_button.icon!=null,"character list shows check boxes")
	var layout:Node=world.rotation_quick_layout()
	ui.set_team_button_callable_choose(list_button)
	check(layout.checks.left.is_empty() and layout.checks.right.is_empty() and world.now_choose_char=="","checking before choosing a team does nothing and never selects a placing character")
	# Blue spot: selected blue team, placed twice -> moved, still one marker.
	ui.team_box.get_node("RotationBlueTeam").button_pressed=true
	check(world.rotation_quick_layout_click(blue_spot+Vector2(0,30)),"layout click is consumed")
	check(world.rotation_quick_layout_click(blue_spot),"second blue click is consumed")
	check(layout.markers.size()==1 and layout.markers.left.distance_to(blue_spot)<0.01 and layout.current_side=="left","each team has at most one position; clicking again moves it")
	ui.set_team_button_callable_choose(list_button)
	var listed:String=str(list_button.get_meta("choice_value"))
	check(layout.checks.left==[listed] and list_button.text.begins_with("1 "),"clicking a list entry checks it with its order")
	ui.set_team_button_callable_choose(list_button)
	check(layout.checks.left.is_empty() and not list_button.text.begins_with("1 "),"clicking again unchecks it")
	ui._toggle_quick_layout_check(fake_char("ballA"));ui._toggle_quick_layout_check(fake_char("ballB"))
	# Red spot via the red team button, then its own list.
	ui.team_box.get_node("RotationRedTeam").button_pressed=true
	world.rotation_quick_layout_click(red_spot)
	check(layout.markers.size()==2 and layout.current_side=="right","the other team gets its own position")
	ui._toggle_quick_layout_check(fake_char("ballB"));ui._toggle_quick_layout_check(fake_char("ballA"));ui._toggle_quick_layout_check(fake_char("ball"))
	check(layout.checks.left==["ballA","ballB"] and layout.checks.right==["ballB","ballA","ball"],"checks are kept per team in check order")
	check(ui.now_char.text.contains("3"),"hint shows the current team's checked count")
	await shot("checking")
	ui._on_rotation_quick_layout_pressed()
	await process_frame;await process_frame
	check(not world.rotation_quick_layout_active() and button.text==game.ui_t("UI_ROTATION_QUICK_LAYOUT"),"second press applies and leaves layout mode")
	var left:Array=roster("left");var right:Array=roster("right")
	print("LEFT ",left," RIGHT ",right)
	check(left.size()==3 and left[1][0]=="ballA" and left[1][1]==2 and left[2][0]=="ballB" and left[2][1]==3,"blue k-th checked goes to round 1+k after the existing round")
	check(left[1][2].distance_to(blue_spot)<0.01 and left[2][2].distance_to(blue_spot)<0.01,"blue entries are all placed at the blue position")
	check(right.size()==3 and right[0][0]=="ballB" and right[0][1]==2 and right[1][0]=="ballA" and right[1][1]==3 and right[2][0]=="ball" and right[2][1]==4,"red k-th checked shares the same new rounds")
	check(right[0][2].distance_to(red_spot)<0.01 and right[2][2].distance_to(red_spot)<0.01,"red entries are all placed at the red position")
	check(roster("left")[0][1]==1,"existing rounds are kept")
	check(list_button.icon==null and not world.rotation_quick_layout_click(blue_spot),"list and clicks return to normal placement")
	# Closing the formation panel abandons an unfinished layout.
	ui._on_rotation_quick_layout_pressed()
	world.rotation_quick_layout_click(blue_spot)
	ui.team.hide();await process_frame;await process_frame
	check(not world.rotation_quick_layout_active() and layout.markers.is_empty(),"closing the team panel cancels an unfinished layout")
	ui.team.show();await process_frame
	game.set_language("en",false);ui._sync_quick_layout_ui()
	print("EN_LABEL ",button.text," / ",game.ui_t("UI_ROTATION_QUICK_LAYOUT")," / ",game.t("UI_ROTATION_QUICK_LAYOUT"))
	check(button.text==game.ui_t("UI_ROTATION_QUICK_LAYOUT") and "Quick layout" in [game.ui_t("UI_ROTATION_QUICK_LAYOUT"),game.t("UI_ROTATION_QUICK_LAYOUT")],"English label")
	game.set_language("zh",false)
	world.reset();await process_frame;world.queue_free();await process_frame;game.Game_Settings=saved
	if FileAccess.file_exists(scratch_settings): DirAccess.remove_absolute(scratch_settings)
	print("ROTATION_QUICK_LAYOUT checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
