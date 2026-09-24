extends "res://tests/test_mc_bat_transform.gd"

# Each formerly missing role must have its own mechanism, not a generic fallback.
const NEW_ROLE_KEYWORDS:Dictionary = {
	"蝙蝠":"吸附", "唤魔者":"尖牙", "末影人":"怒气", "潜影贝":"闭壳",
	"史莱姆":"分裂", "守卫者":"激光", "恶魂":"不分敌我", "粘性活塞":"黏住",
	"钓鱼竿":"收回", "蜘蛛":"蛛网", "溺尸":"电网", "悦灵":"音符",
	"仙人掌":"长高", "唱片机":"声道", "凋零":"信标", "羊":"吃草",
	"木船":"载人", "弓":"箭速", "天堂陨落长弓":"裂隙", "钻石长矛":"虚影",
	"铁傀儡":"村民", "硫方怪":"TNT", "鞘翅重锤":"连砸",
	"鞘翅长矛":"贯穿", "鞘翅重锤长矛":"连砸",
}

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var directory := DirAccess.open("res://scenes/characters/我的世界")
	check(directory != null,"Minecraft roster directory exists")
	if directory == null:
		finish(1)
		return
	var previous_locale:String = game.current_locale
	game.current_locale = "zh"
	var files:PackedStringArray = directory.get_files()
	files.sort()
	var roles_checked:int = 0
	var new_roles_checked:int = 0
	var summaries:Dictionary = world.get_script().get_script_constant_map().get("ARMOR_TEST_ROLE_SUMMARIES",{})
	var number_pattern := RegEx.new()
	number_pattern.compile("[0-9０-９%％]")
	for filename:String in files:
		if not filename.ends_with(".tscn"): continue
		var role:String = filename.get_basename()
		# Read the real scene's root script path without loading every large model.
		var scene_text:String = FileAccess.get_file_as_string("res://scenes/characters/我的世界/"+filename)
		var script_path:String = ""
		for line:String in scene_text.split("\n"):
			if line.begins_with("[ext_resource type=\"Script\"") and line.contains("path=\"res://scripts/characters/我的世界/"):
				script_path = line.get_slice("path=\"",1).get_slice("\"",0)
				break
		check(not script_path.is_empty(),role+" scene has a Minecraft role script")
		if script_path.is_empty(): continue
		var summary:String = str(summaries.get(script_path,"")).strip_edges()
		var has_custom:bool = false
		if summary.is_empty():
			has_custom = FileAccess.get_file_as_string(script_path).contains("func get_armor_test_effect_summary(")
		check(not summary.is_empty() or has_custom,role+" has an armor-stand introduction")
		if NEW_ROLE_KEYWORDS.has(role):
			new_roles_checked += 1
			check(summary.contains(str(NEW_ROLE_KEYWORDS[role])),role+" introduces its own mechanic")
			check(summary.length() <= 90 and number_pattern.search(summary) == null,role+" introduction is concise and number-free")
		roles_checked += 1
	check(roles_checked >= 42,"all current roster scenes are checked")
	check(new_roles_checked == NEW_ROLE_KEYWORDS.size(),"all formerly missing roles are present")
	world._clear_armor_stand_test_primary_enemy()
	var stand:Node2D = spawn("res://scenes/characters/默认/盔甲架.tscn",center+Vector2(0,100),"Team1")
	stand.state_machine.set_physics_process(false)
	var bow:Node2D = spawn("res://scenes/characters/我的世界/弓.tscn",center,"Team0")
	bow.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	var hud_text:String = world._build_armor_stand_test_enemy_info()
	check(hud_text.contains("蓄力") and hud_text.contains("箭速"),"actual armor-stand HUD shows the new introduction")
	game.current_locale = previous_locale
	finish(0 if failures == 0 else 1)
