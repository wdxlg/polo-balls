extends SceneTree
## Lightweight roster regression + optional real-GPU screenshots (-- --visual).
const OVERLAY_PATH = "res://scripts/ui/random_character_draw_overlay.gd"
var checks:int = 0
var failures:int = 0
var visual:bool = false
func _initialize() -> void: call_deferred("run")
func check(ok:bool,message:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)
func record(index:int,team:String) -> Dictionary:
	return {"id":index+100,"display_team":team,"team":team,"char":"剑客","category":"人物"}
func capture(name:String) -> void:
	if not visual: return
	await process_frame
	await RenderingServer.frame_post_draw
	var image:Image = root.get_texture().get_image()
	if root.use_hdr_2d:
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	image.resize(540,960,Image.INTERPOLATE_LANCZOS)
	image.save_png("res://tests/random_roster_"+name+".png")
func fake_preview() -> Node2D:
	var preview := Node2D.new()
	var image := Sprite2D.new()
	image.name = "PreviewImage"
	image.texture = load("res://Images/bilibili.png") as Texture2D
	preview.add_child(image)
	return preview
func roulette_preview(_name:String,_path:String,_attach:bool) -> Node2D:
	return fake_preview()

func validate_geometry(ui:Control) -> void:
	for slot:Dictionary in ui._slots:
		check(ui.BOARD.encloses(slot.rect),"slot remains inside the square board")
		check(slot.rect.size.x>0 and is_equal_approx(slot.rect.size.x,slot.rect.size.y),"square slot has positive size")
		check(ui._groups[int(slot.group)].rect.encloses(slot.rect),"slot stays in its team panel")
func run() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	root.get_node("Game").set_language("zh",false)
	var ui:Control = load(OVERLAY_PATH).new()
	root.add_child(ui)
	await process_frame
	var candidates:Array[String] = ["DO NOT LEAK"]
	var empty_candidates:Array[String] = []
	var colors:Array = [Color("ff5555"),Color("55aaff"),Color("66dd88")]
	for mode:String in ["manual","timed","rotation","boss"]:
		var records:Array = []
		for index:int in range(8): records.append(record(index,"Team0" if index<4 else "Team1"))
		ui.configure_roster(records,mode,"Team1",colors)
		ui.configure_roulette([{"char":"剑客"},{"char":"保安"},{"char":"猎人"}],Callable(self,"roulette_preview"))
		check(ui._slots.size()==8 and ui._groups.size()==2,mode+": all seats exist before first reveal")
		check(ui._xp_segments.size()==8,mode+": exactly eight experience segments")
		check(ui._experience_filled_segments()==0,"initial experience has no filled segments")
		validate_geometry(ui)
		for slot:Dictionary in ui._slots:
			check(slot.question.text=="?" and not slot.done,mode+": hidden slots show only question marks")
		ui.begin_ticket(0,8,records[0],candidates,1.0)
		check(ui._roulette.visible and not ui._roulette.landed,"dedicated roulette starts spinning")
		var start_distance:float = ui._roulette._distance
		await create_timer(0.08).timeout
		check(ui._roulette._distance>start_distance,"candidate portraits physically scroll")
		await process_frame
		check(ui._slots[0].question.text=="?","rolling does not leak candidates")
		check(int(ui._sound.played_counts.get("tick",0))>0,"physical reel steps trigger quiet Minecraft clicks")
		await capture(mode+"_unknown")
		var pixel_scale_before:float = ui._experience_pixel_scale()
		ui.reveal_ticket(records[0],fake_preview())
		check(int(ui._sound.played_counts.get("confirm",0))==1,"authority reveal triggers exactly one experience-orb cue")
		check(ui._fx._flights.size()>0 and 0 in ui._animated_slots,"reveal launches portrait transfer and card animation")
		check(ui._fx._gains.size()>0,"experience gain emits pixel particles")
		check(is_equal_approx(pixel_scale_before,ui._experience_pixel_scale()),"experience gain never stretches native pixels")
		check(ui._roulette.landed and ui._roulette.confirmed_name==root.get_node("Game").ui_t("剑客"),"accelerated reel lands on the authoritative identity")
		check(is_equal_approx(ui._roulette._distance,ui._roulette.LANDING*ui._roulette.STEP),"final portrait aligns exactly to center marker")
		await create_timer(0.6).timeout
		check(int(ui._sound.played_counts.get("arrival",0))==1,"actual portrait arrival triggers one pickup cue")
		check(ui._slots[0].card.modulate.a==1.0 and ui._slots[0].card.scale==Vector2.ONE,"card returns to stable full visibility after landing")
		await capture(mode+"_landed")
		ui.begin_ticket(1,8,records[1],empty_candidates)
		check(ui._slots[0].done and ui._slots[0].name.text!="01","earlier identity persists during next draw")
		check(is_instance_valid(ui._slots[0].portrait),"previous texture portrait persists")
		check(ui._slots[1].question.text=="?","next seat remains unknown")
		check(ui.revealed_count==1,"count increments once")
		check(ui._experience_filled_segments()==1 and is_equal_approx(ui._xp_display,0.125),"one reveal immediately fills exactly one segment")
		ui.reveal_ticket(records[1])
		ui.reveal_ticket(records[1])
		check(ui.revealed_count==2,"duplicate reveal is idempotent")
		check(ui._slots[1].question.text!="?","missing preview still reveals character identity")
		ui.begin_ticket(4,8,records[4],empty_candidates)
		ui.reveal_ticket(records[4],fake_preview())
		await create_timer(0.3).timeout
		check(ui._xp_display>0.0 and ui._xp_display<=1.0,"experience tracks revealed seats")
		await capture(mode+"_partial")
		if mode=="boss": check(ui._groups[0].title.begins_with("BOSS"),"boss side is visually prioritized")
		for index:int in range(8):
			if ui._slots[index].done: continue
			ui.begin_ticket(index,8,records[index],empty_candidates)
			ui.reveal_ticket(records[index],fake_preview())
		ui.show_finishing()
		ui.show_complete()
		check(int(ui._sound.played_counts.get("complete",0))==1,"completion triggers the level-up cue once")
		check(ui._animated_slots.is_empty() and ui._fx._flights.is_empty(),"completion settles all outstanding transitions")
		check(ui.revealed_count==8 and is_equal_approx(ui._xp_display,1.0),"completion fills experience bar")
		check(ui.find_children("*","Button",true,false).is_empty(),"draw has no acceleration or replacement button")
		await capture(mode+"_complete")
	for count:int in [1,4,8,17,18,45,128,1024]:
		var records:Array = []
		for index:int in range(count): records.append(record(index,""))
		ui.configure_roster(records,"manual")
		check(ui._slots.size()==count,"every seat retained at count "+str(count))
		check(ui._xp_segments.size()==count,"experience segment count equals roster size")
		var accumulated:int = 0
		for row:Dictionary in ui._xp_rows:
			check(row.count<=ui.XP_ROW_LIMIT,"large drafts wrap before segments become subpixel")
			accumulated += int(row.count)
			var image:Image = row.full.get_image()
			var original:Image = ui.XP_PROGRESS.get_image()
			check(image.get_size()==Vector2i(182,5),"experience composition retains vanilla aspect ratio")
			for index:int in range(row.bodies.size()):
				var body:Rect2i = row.bodies[index]
				for sample:int in [0,body.size.x/2,body.size.x-1]:
					var source_x:int = 1+((int(row.first)+index)%18)*10+sample%9
					check(image.get_pixel(body.position.x+sample,2)==original.get_pixel(source_x,2),"native pixel copies repeat instead of horizontal stretching")
		check(accumulated==count,"wrapped rows contain exactly total segments")
		for segment:Rect2 in ui._xp_segments:
			check(segment.size.x>=9 and segment.end.y<ui._design.size.y,"segments remain legible and inside the design")
		validate_geometry(ui)
		await capture("count_"+str(count))
	var uneven:Array = []
	for index:int in range(25): uneven.append(record(index,"Team0" if index==0 else ("Team2" if index==24 else "Team1")))
	ui.configure_roster(uneven,"timed","Team1",colors)
	validate_geometry(ui)
	check(ui._groups.size()==3,"multiteam layout keeps distinct teams")
	await capture("three_teams")
	var many_teams:Array = []
	for index:int in range(1024): many_teams.append(record(index,"Team"+str(index)))
	ui.configure_roster(many_teams,"manual")
	validate_geometry(ui)
	check(ui._groups.size()==1024,"dense team layout retains every team")
	ui.configure_roster([record(0,"Team0")],"rotation")
	check(ui._groups.size()==2,"empty opposing side remains visible in two-side modes")
	ui.configure_roster([record(0,"Team0"),record(1,"Team1")],"boss","Team0",colors)
	check(ui._slots[0].group==0 and ui._groups[0].title.begins_with("BOSS"),"left-side boss setting respected")
	for viewport_size:Vector2i in [Vector2i(360,640),Vector2i(1280,720),Vector2i(540,960)]:
		root.size = viewport_size
		await process_frame
		ui._layout()
		var design_rect := Rect2(ui._design.position,ui._design.size*ui._factor)
		check(Rect2(Vector2.ZERO,ui.get_viewport_rect().size).encloses(design_rect),"portrait/landscape layout stays visible")
		var physical_scale:float = ui._experience_pixel_scale()*float(root.size.x)/ui.get_viewport_rect().size.x
		check(is_equal_approx(physical_scale,roundf(physical_scale)),"experience pixels use integer window-pixel scaling")
	root.get_node("Game").Game_Settings.Only_In_Game_Translation = false
	root.get_node("Game").set_language("en",false)
	ui.configure_roster([record(0,"Team0")],"rotation")
	check("LINEUP" in ui._groups[0].title,"English team presentation copy")
	root.get_node("Game").set_language("zh",false)
	ui.configure_roster([],"manual")
	check(ui.total==0 and ui._slots.is_empty(),"empty roster safe")
	check(ui._xp_segments.is_empty() and ui._experience_filled_segments()==0,"empty draft has no phantom segment")
	var overlay_source:String = FileAccess.get_file_as_string(OVERLAY_PATH)
	check(not "RANDOM_DRAW_TITLE" in overlay_source and not "var _subtitle" in overlay_source,"decorative heading and subtitle removed")
	check(ui.XP_BACKGROUND.get_size()==Vector2(182,5) and ui.XP_PROGRESS.get_size()==Vector2(182,5),"vanilla 182x5 textures loaded")
	check(FileAccess.get_sha256("res://Images/UI/minecraft_xp/experience_bar_background.png")=="1a465d395131f10fff6695fd7ca3243ef5fd2cccb0a496581a8c1d84c358a6d6","background PNG matches official extracted bytes")
	check(FileAccess.get_sha256("res://Images/UI/minecraft_xp/experience_bar_progress.png")=="a94235503f186fd84ac66ce4b09a4ba9796bc4b8efb9ad43dcc3486698fc26dd","progress PNG matches official extracted bytes")
	# Stress rapid results: bounded effects and no permanently hidden cards, even when
	# more results arrive within one frame than the visible animation budget.
	var fast_records:Array = []
	for index:int in range(40): fast_records.append(record(index,"Team0"))
	ui.configure_roster(fast_records,"manual")
	check(ui.find_children("*","Button",true,false).is_empty(),"fast internal test path does not create a skip button")
	for index:int in range(fast_records.size()):
		ui.begin_ticket(index,fast_records.size(),fast_records[index],empty_candidates,0.0)
		ui.reveal_ticket(fast_records[index],fake_preview())
	check(ui._animated_slots.size()<=24,"card transition budget remains bounded")
	check(ui._fx._flights.size()<=ui._fx.MAX_FLIGHTS and ui._fx._bursts.size()<=ui._fx.MAX_BURSTS,"particle and flight budgets remain bounded")
	ui.show_complete()
	for slot:Dictionary in ui._slots:
		check(slot.card.modulate.a==1.0 and slot.card.scale==Vector2.ONE,"rapid completion cannot leave hidden portraits")
	ui._fx.advance(2.0)
	check(ui._fx._flights.is_empty() and ui._fx._bursts.is_empty() and ui._fx._rings.is_empty() and ui._fx._gains.is_empty(),"all transient effects expire")
	seed(73491)
	var expected_random:float = randf()
	seed(73491)
	ui._fx.burst(Vector2.ZERO,Color.WHITE,14)
	ui._fx.advance(0.1)
	check(is_equal_approx(randf(),expected_random),"UI particles do not consume the global battle RNG")
	var effect_reference:WeakRef = weakref(ui._fx)
	var saved_time_scale:float = Engine.time_scale
	var saved_pause:bool = paused
	Engine.time_scale = 0.0
	paused = true
	var exit_pixel_scale:float = ui._experience_pixel_scale()
	ui.begin_exit(0.42)
	check(not ui.is_exit_finished() and is_equal_approx(ui.modulate.a,1.0),"exit starts fully visible, not a hard cut")
	ui._exit_started_at -= 210
	ui._process(0.0)
	check(ui.modulate.a>0.1 and ui.modulate.a<0.9,"exit fades at zero game speed and while paused")
	check(ui._design.scale.x<ui._factor and ui._design.position.y>ui._rest_position.y,"panel recedes and moves down gently")
	check(is_equal_approx(exit_pixel_scale,ui._experience_pixel_scale()),"exit never stretches native Minecraft XP pixels")
	var original_exit_tick:int = ui._exit_started_at
	ui.begin_exit(0.42)
	check(ui._exit_started_at==original_exit_tick,"repeated completion cannot restart exit")
	ui._layout()
	check(ui.modulate.a<0.9 and ui._design.scale.x<ui._factor,"resizing preserves exit progress")
	ui._exit_started_at -= 250
	ui._process(0.0)
	check(ui.is_exit_finished() and ui.modulate.a==0.0,"exit reaches full transparency before removal")
	ui.configure_roster([record(0,"Team0")],"manual")
	check(not ui.is_exit_finished() and ui.modulate.a==1.0,"new roster resets exit state")
	ui.begin_exit(0.0)
	check(ui.is_exit_finished() and ui.modulate.a==0.0,"zero-duration deterministic test path remains immediate")
	Engine.time_scale = saved_time_scale
	paused = saved_pause
	ui.free()
	check(effect_reference.get_ref()==null,"cancel/free destroys the owned effect layer")
	await process_frame
	var audio_drain_until:int = Time.get_ticks_msec()+100
	while Time.get_ticks_msec()<audio_drain_until: await process_frame
	print("RANDOM_ROSTER_UI checks=",checks," failures=",failures)
	quit(1 if failures else 0)
