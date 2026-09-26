extends SceneTree
## Pure naming + real filesystem checks; no encoder, user settings, or old videos touched.
var Naming:Script
var checks:int = 0
var failures:int = 0
var scratch:String

class SnapshotWorld extends Node:
	var _battle_setup:Array = []
	var _last_battle_setup:Array = []
	var _rotation_rosters:Dictionary = {"left":[],"right":[]}
	var _rotation_saved_rosters:Dictionary = {"left":[],"right":[]}
	var _armor_stand_test_hud_active:bool = false
	var _armor_stand_test_primary_identity:String = ""
	func _armor_stand_test_first_enemy() -> Node: return null
	var fallback:Dictionary = {"order":[],"members":{}}
	func return_battle_sides() -> Dictionary: return fallback

func _initialize() -> void:
	_run.call_deferred()

func check(ok:bool, label:String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)

func data_for(left:Array, right:Array = []) -> Dictionary:
	var groups:Array = []
	for members:Array in [left,right]:
		if not members.is_empty(): groups.append({"team":"Team%d" % groups.size(),"members":members.duplicate(true)})
	return {"groups":groups,"settings":{"Training_Mode_Type":"manual"},"armor_test":false}

func touch(name:String) -> void:
	var file:FileAccess = FileAccess.open(scratch.path_join(name), FileAccess.WRITE)
	check(file != null,"Windows creates safe filename: " + name)
	if file != null:
		file.store_string("owned naming fixture; preserve until cleanup")
		file.close()

func _run() -> void:
	create_timer(25.0,true,false,true).timeout.connect(func(): print("NAMING_TIMEOUT"); quit(2))
	Naming = load("res://scripts/ui/battle_record_naming.gd")
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	var locale:String = game.current_locale
	var server_locale:String = TranslationServer.get_locale()
	scratch = ProjectSettings.globalize_path("user://recording_naming_%d" % Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(scratch) == OK,"isolated writable test directory")
	var diamond:Dictionary = {"char":"钻石剑"}
	var wood:Dictionary = {"char":"木剑"}
	var cow:Dictionary = {"char":"牛"}
	var pair:Dictionary = data_for([diamond],[wood])
	check(Naming.title(pair,"zh") == "Mc小球:钻石剑 vs 木剑","Chinese exact requested title")
	check(Naming.title(pair,"en") == "Diamond Sword vs Wooden Sword","English uses translated names without a prefix")
	var counted:Dictionary = data_for([diamond,diamond,diamond],[wood,wood])
	check(Naming.title(counted,"zh") == "Mc小球:3个钻石剑 vs 2个木剑","Chinese number-before-name quantities")
	check(Naming.title(counted,"en") == "Diamond Sword * 3 vs Wooden Sword * 2","English name-star-number quantities")
	var mixed:Dictionary = data_for([cow,diamond,cow,cow],[wood,cow])
	check(Naming.title(mixed,"zh") == "Mc小球:3个牛 + 钻石剑 vs 木剑 + 牛","mixed team aggregates only duplicate names, preserving order")
	check(Naming.title(mixed,"en") == "Cow * 3 + Diamond Sword vs Wooden Sword + Cow","English mixed team retains single names without times one")
	check(Naming.title(data_for([cow],[cow]),"zh") == "Mc小球:牛 vs 牛","opposing sides never merged together")
	var large:Array = []
	for i:int in range(100): large.append(cow)
	check(Naming.title(data_for(large,[wood]),"zh") == "Mc小球:100个牛 vs 木剑","large Chinese count remains compact")
	check(Naming.title(data_for(large,[wood]),"en") == "Cow * 100 vs Wooden Sword","large English count remains compact")
	var random:Dictionary = {"char":"牛","random_choice":true}
	var randoms:Dictionary = data_for([random,random,random],[random,random])
	check(Naming.title(randoms,"zh") == "Mc小球:3个随机人物 vs 2个随机人物","random provenance retained with Chinese quantities")
	check(Naming.title(randoms,"en") == "Random Character * 3 vs Random Character * 2","random provenance retained with English quantities")
	check(Naming.title(data_for([cow,random,random],[wood]),"zh") == "Mc小球:牛 + 2个随机人物 vs 木剑","manual and random choices remain distinct")
	check(Naming.title(data_for([random],[wood]),"en") == "Random Character vs Wooden Sword","single random choice has no redundant count")
	for mode:String in ["manual","rotation","timed","boss"]:
		var special:Dictionary = pair.duplicate(true)
		special.settings = {"Training_Mode_Type":mode,"Training_Mode":true,"Rotation_Match_Type":"challenge","Training_Timed_Duration":60,"Training_Boss_Wheel_Battle":true,"Training_Boss_Multiplier":3}
		check(Naming.title(special,"zh") == "Mc小球:钻石剑 vs 木剑" and Naming.title(special,"en") == "Diamond Sword vs Wooden Sword","mode does not add a prefix or turn boss HP multiplier into headcount: " + mode)
	var armor:Dictionary = pair.duplicate(true)
	armor.armor_test = true
	armor.armor_role = "烈焰人"
	check(Naming.title(armor,"zh") == "Mc小球新角色:烈焰人","armor introduction Chinese title uses selected new-role name only")
	check(Naming.title(armor,"en") == "Blaze","armor English title is just the translated role name")
	check(Naming.filename(armor,"zh","STAMP",scratch)=="Mc小球新角色：烈焰人.mp4","armor Windows filename keeps the new-role prefix and safe colon")
	check(Naming.filename(armor,"en","STAMP",scratch)=="Blaze.mp4","armor English filename has no Chinese prefix or dummy matchup")
	var saved_armor:String = JSON.stringify(armor)
	Naming.title(armor,"en")
	check(JSON.stringify(armor)==saved_armor,"armor formatting does not mutate the frozen selection")
	touch("Blaze.mp4")
	check(Naming.filename(armor,"en","STAMP",scratch)=="Blaze (2).mp4","armor recordings never overwrite an earlier role video")
	var long_armor:Dictionary = armor.duplicate(true)
	long_armor.armor_role = "Role".repeat(60)
	var short_root:String = "C:/"+"a".repeat(199)
	check(Naming.filename(long_armor,"zh","STAMP",short_root).begins_with("Mc小球新角色："),"tight paths preserve the entire longer introduction prefix")
	check(Naming.filename(long_armor,"zh","STAMP","C:/"+"a".repeat(205)).is_empty(),"reject path budget too short to retain new-role prefix and identity hash")
	var empty_armor:Dictionary = armor.duplicate(true)
	empty_armor.armor_role = ""
	check(Naming.title(empty_armor,"en")=="New Character","missing selected role never promotes the armor stand to the new character")

	check(Naming.title(data_for([]),"zh") == "Mc小球:自由对战" and Naming.title(data_for([]),"en") == "Free Battle","empty matchup has localized fallback")
	var empty_group:Dictionary = data_for([])
	empty_group.groups = [{"team":"","members":[]}]
	check(Naming.title(empty_group,"en") == "Free Battle","empty group does not create a dangling separator")
	var armor_world := SnapshotWorld.new()
	armor_world._armor_stand_test_hud_active = true
	armor_world._armor_stand_test_primary_identity = "烈焰人"
	armor_world._battle_setup = [{"char":"木剑","team":"Team0"},{"char":"不死盔甲架","team":"Team1"},{"char":"烈焰人","team":"Team0","random_choice":true}]
	var demo:Dictionary = Naming.snapshot(armor_world,false)
	check(demo.armor_role=="烈焰人" and Naming.title(demo,"en")=="Blaze","armor snapshot uses the shared role lock, not dead foes, dummies, or random provenance")
	armor_world._armor_stand_test_primary_identity = "牛"
	check(Naming.title(demo,"en")=="Blaze","later role changes do not rename a recording already started")
	armor_world.free()
	var immutable:String = JSON.stringify(counted)
	Naming.title(counted,"zh")
	Naming.title(counted,"en")
	check(JSON.stringify(counted) == immutable,"formatting never modifies the snapshot")
	var zh:String = Naming.filename(counted,"zh","STAMP",scratch)
	var en:String = Naming.filename(counted,"en","STAMP",scratch)
	check(zh == "Mc小球：3个钻石剑 vs 2个木剑.mp4","Chinese filename uses Windows-safe colon without timestamp")
	check(en == "Diamond Sword ＊ 3 vs Wooden Sword ＊ 2.mp4","English filename uses Windows-safe stars without timestamp")
	check(Naming.title(counted,"en").contains(" * ") and Naming.title(counted,"zh").begins_with("Mc小球:"),"embedded media title retains the exact ASCII punctuation")
	touch(zh)
	touch(en)
	var existing:String = FileAccess.get_file_as_string(scratch.path_join(en))
	check(Naming.filename(counted,"zh","OTHER",scratch) == "Mc小球：3个钻石剑 vs 2个木剑 (2).mp4","duplicate Chinese recording uses a collision-only number")
	check(Naming.filename(counted,"en","OTHER",scratch) == "Diamond Sword ＊ 3 vs Wooden Sword ＊ 2 (2).mp4","duplicate English recording uses a collision-only number")
	check(FileAccess.get_file_as_string(scratch.path_join(en)) == existing,"old recording is never overwritten by name selection")
	for suffix:String in [".video.mp4",".audio.f32"]:
		var pending:String = "Diamond Sword vs Wooden Sword" + suffix
		touch(pending)
		check(Naming.filename(pair,"en","STAMP",scratch) == "Diamond Sword vs Wooden Sword (2).mp4","pending encoder/audio output reserves the basename: " + suffix)
		DirAccess.remove_absolute(scratch.path_join(pending))
	var frames:String = scratch.path_join("Diamond Sword vs Wooden Sword_frames")
	DirAccess.make_dir_absolute(frames)
	check(Naming.filename(pair,"en","STAMP",scratch) == "Diamond Sword vs Wooden Sword (2).mp4","PNG fallback directory reserves the basename")
	DirAccess.remove_absolute(frames)
	touch("Diamond Sword vs Wooden Sword.mp4")
	touch("Diamond Sword vs Wooden Sword (2).mp4")
	check(Naming.filename(pair,"en","STAMP",scratch) == "Diamond Sword vs Wooden Sword (3).mp4","multiple old captures remain distinct")
	var unsafe:Dictionary = data_for([{"char":"A:B/Bad*Name?\"<>|\\\n\r\t"}],[wood])
	var safe:String = Naming.filename(unsafe,"en","STAMP",scratch)
	var valid:bool = safe.is_valid_filename()
	for invalid:String in ["<",">",":",'"',"/","\\","|","?","*","\n","\r","\t"]: valid = valid and not safe.contains(invalid)
	check(valid,"illegal filename characters sanitized without discarding safe Unicode")
	for reserved:String in ["CON","NUL","PRN","AUX","COM1","LPT9"]:
		check(Naming.filename(data_for([{"char":reserved}]),"en","STAMP",scratch) == "_" + reserved + ".mp4","prefix-free English names cannot become Windows devices: " + reserved)
	var long_data:Dictionary = data_for([{"char":"VeryLongName".repeat(40)}],[wood])
	var long_name:String = Naming.filename(long_data,"en","STAMP",scratch)
	check(long_name.length() <= 164 and long_name.contains("~") and long_name.ends_with(".mp4"),"long name retains bounded hash suffix")
	var other_long:Dictionary = long_data.duplicate(true)
	other_long.groups[0].members[0].char += "Different"
	check(Naming.filename(other_long,"en","STAMP",scratch) != long_name,"different truncated matchups keep different hashes")
	check(Naming.filename(pair,"en","STAMP","C:/" + "a".repeat(225)).is_empty(),"overlong output directory fails safely")
	check(Naming.filename(pair,"zh","STAMP","C:/" + "a".repeat(206)).is_empty(),"Chinese path budget cannot truncate the required Mc prefix")
	check(Naming.filename(pair,"zh","STAMP","C:/" + "a".repeat(205)).begins_with("Mc小球："),"tight but valid Chinese path retains the complete prefix")
	# Exercise snapshot source selection and deep copies, not just made-up title data.
	var fake := SnapshotWorld.new()
	game.Game_Settings.Training_Mode_Type = "manual"
	fake._battle_setup = [{"id":1,"team":"A","char":"牛"},{"id":2,"team":"A","char":"牛"},{"id":3,"team":"B","char":"木剑"}]
	var initial:Dictionary = Naming.snapshot(fake,false)
	check(Naming.title(initial,"zh") == "Mc小球:2个牛 vs 木剑","initial real schema is counted by team")
	fake._battle_setup[0].char = "钻石剑"
	check(Naming.title(initial,"zh") == "Mc小球:2个牛 vs 木剑","later lineup changes do not rename the frozen recording")
	fake._last_battle_setup = fake._battle_setup.duplicate(true)
	fake._battle_setup.clear()
	check(Naming.title(Naming.snapshot(fake,true),"en") == "Diamond Sword + Cow vs Wooden Sword","simulated fallback uses the initial saved setup")
	fake._last_battle_setup.clear()
	fake.fallback = {"order":["team:A","team:B"],"members":{"team:A":["牛","牛"],"team:B":["木剑"]}}
	check(Naming.title(Naming.snapshot(fake,false),"en") == "Cow * 2 vs Wooden Sword","live-world fallback retains team quantities")
	game.Game_Settings.Training_Mode_Type = "rotation"
	fake._rotation_rosters = {"left":[cow,cow],"right":[wood]}
	check(Naming.title(Naming.snapshot(fake,false),"zh") == "Mc小球:2个牛 vs 木剑","rotation roster uses the same count syntax")
	fake._rotation_saved_rosters = fake._rotation_rosters.duplicate(true)
	fake._rotation_rosters = {"left":[],"right":[]}
	check(Naming.title(Naming.snapshot(fake,true),"en") == "Cow * 2 vs Wooden Sword","saved rotation roster uses translated count syntax")
	game.Game_Settings = saved
	fake.free()
	check(game.current_locale == locale and TranslationServer.get_locale() == server_locale,"both localized names leave user language unchanged")
	for file:String in DirAccess.get_files_at(scratch): DirAccess.remove_absolute(scratch.path_join(file))
	DirAccess.remove_absolute(scratch)
	print("RECORDING_ARMOR_NAMING: %d checks / %d failures" % [checks,failures])
	quit(1 if failures else 0)
