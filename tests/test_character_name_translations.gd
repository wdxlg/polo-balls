extends SceneTree
const CATALOG = preload("res://global/translation_catalog.gd")
const RECOVERED_NAMES:Dictionary = {
	"史莱姆": "Slime",
	"守卫者": "Guardian",
	"恶魂": "Ghast",
	"粘性活塞": "Sticky Piston",
	"钓鱼竿": "Fishing Rod",
	"史莱姆_中": "Medium Slime",
	"史莱姆_小": "Small Slime",
	"恶魂火焰弹": "Ghast Fireball",
	"天堂陨落长弓": "Longbow of the Heavens",
	"木船": "Oak Boat",
	"天陨箭": "Heaven Arrow",
	"铁砧": "Anvil",
	"铜剑": "Copper Sword",
	"鞘翅重锤": "Elytra Mace",
	"鞘翅长矛": "Elytra Spear",
	"铁傀儡": "Iron Golem",
	"铁傀儡村民": "Golem Villager"
}
var failures:int = 0
var checks:int = 0
var scenes:Array[String] = []
var game:Node
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func scan(path:String) -> void:
	var dir := DirAccess.open(path)
	check(dir != null,"Cannot scan "+path)
	if dir == null: return
	for sub:String in dir.get_directories(): scan(path.path_join(sub))
	for file:String in dir.get_files():
		if file.ends_with(".tscn"): scenes.append(path.path_join(file))
func verify_names(stage:String) -> void:
	for path:String in scenes:
		var key:String = path.get_file().get_basename()
		var en:String = game.t(key)
		check(not en.is_empty() and not game._contains_cjk(en),stage+" untranslated: "+key)
		check(en == CATALOG.TABLE.en.get(key,""),stage+" wrong catalog result: "+key)
		check(game.t(key+"（2）") == en,stage+" copy suffix: "+key)
		check(game.ui_t(key) == en,stage+" selector name: "+key)
		check(game.translate_game_text(key) == en,stage+" battle name: "+key)
func verify_recovered_names(stage:String) -> void:
	# Exercise the actual selector refresh method without starting a battle.
	var selector:Node = load("res://ui/control.gd").new()
	for key:String in RECOVERED_NAMES:
		var expected:String = RECOVERED_NAMES[key]
		check(game.t(key) == expected,stage+" recovered name: "+key)
		var button := Button.new()
		button.text = key
		button.set_meta("choice_value",key)
		selector._refresh_static_ui_texts(button)
		check(button.text == expected,stage+" real selector refresh: "+key)
		check(button.get_meta("choice_value") == key,stage+" resource identity preserved: "+key)
		var combined:String = game.translate_ui_text("当前角色："+key)
		# Prefix aliases may have different wording/spacing; assert the character name.
		check(combined.ends_with(expected) and not combined.contains(key),stage+" combined toolbar name: "+key+" -> "+combined)
		button.free()
	selector.free()
func run() -> void:
	game = root.get_node("Game")
	var old_locale:String = game.current_locale
	var old_only:bool = game.Game_Settings.get("Only_In_Game_Translation",false)
	var csv := FileAccess.open("res://translations.csv",FileAccess.READ)
	check(csv != null,"CSV must exist for source validation")
	if csv == null: quit(1); return
	var header:PackedStringArray = csv.get_csv_line()
	check(header == PackedStringArray(["keys","zh","en"]),"CSV header")
	var source:Dictionary = {}
	while not csv.eof_reached():
		var row:PackedStringArray = csv.get_csv_line()
		if row.size() == 1 and row[0].is_empty(): continue
		check(row.size() == 3,"Malformed CSV row")
		if row.size() != 3: continue
		check(not source.has(row[0]),"Duplicate translation key "+row[0])
		source[row[0]] = [row[1],row[2]]
		check(CATALOG.TABLE.zh.get(row[0]) == row[1] and CATALOG.TABLE.en.get(row[0]) == row[2],"CSV/catalog mismatch "+row[0])
	csv.close()
	check(source.size() == CATALOG.TABLE.en.size() and source.size() == CATALOG.TABLE.zh.size(),"No orphan compiled-only keys")
	scan("res://scenes/characters")
	game.current_locale = "en"
	game.Game_Settings.Only_In_Game_Translation = false
	game._apply_translation_server_locale()
	check(game.load_runtime_translations(),"explicit runtime CSV reload")
	verify_names("runtime CSV")
	verify_recovered_names("runtime CSV")
	for key:String in ["木矛","唤魔者","末影人","潜影贝","磐灯守卫","霆针游侠","时砂司祭","疲倦的人_悲伤形态","疲倦的人_愤怒形态"]:
		check(game.ui_t(key) == game.t(key),"UI and battle agree: "+key)
		check(game.translate_game_text(key) == game.t(key),"combined game translation: "+key)
	# 模拟导出包没有原CSV：直接装载编译镜像后再核对整份角色目录。
	check(game._load_compiled_translation_catalog(),"compiled fallback load")
	verify_names("compiled fallback")
	verify_recovered_names("compiled fallback")
	game.Game_Settings.Only_In_Game_Translation = true
	game._apply_translation_server_locale()
	check(game.ui_t("木矛") == "木矛" and game.t("木矛") == "Wooden Spear","in-game-only setting remains respected")
	game.current_locale = "zh"
	game.Game_Settings.Only_In_Game_Translation = false
	game._apply_translation_server_locale()
	check(game.t("木矛") == "木矛" and game.t("末影人") == "末影人","Chinese restored")
	for key:String in RECOVERED_NAMES:
		check(game.ui_t(key) == key and game.t(key) == key,"Recovered Chinese name restored: "+key)
	game.current_locale = old_locale
	game.Game_Settings.Only_In_Game_Translation = old_only
	game._apply_translation_server_locale()
	print("CHARACTER_NAME_TRANSLATIONS scenes=",scenes.size()," keys=",source.size()," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
