extends SceneTree
## 编译检查：加载本轮性能改动涉及的所有脚本，任何解析错误都会让 can_instantiate() 为 false。
const SCRIPTS:Array[String] = [
	"res://classes/property_index.gd",
	"res://scripts/characters/磁铁.gd",
	"res://scripts/training/combat_threat_analyzer.gd",
	"res://scripts/characters/鼓手.gd",
	"res://scripts/characters/投稿角色工具.gd",
	"res://scripts/characters/醉汉.gd",
	"res://scripts/characters/极速者.gd",
	"res://scripts/characters/meme/菊花茶.gd",
	"res://scripts/training/manual_training_controller.gd",
	"res://scripts/training/special_character_threat_overlay.gd",
	"res://scripts/training/training_stats_hud.gd",
	"res://scripts/training/speedster_rl_world_controller.gd",
	"res://scripts/characters/动物/九头蛇_头.gd",
	"res://scripts/characters/智者_布局点.gd",
	"res://scripts/characters/乐队/薇欧拉.gd",
	"res://scripts/effects/菊花茶重力视觉.gd",
	"res://global/audios.gd",
	"res://global/game.gd",
	"res://global/game_room_discovery.gd",
	"res://scripts/effects/hit_burst_effect.gd",
	"res://classes/ball.gd",
	"res://scripts/world.gd",
	"res://scripts/shooter/knife.gd",
]
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var failures:int = 0
	for path:String in SCRIPTS:
		var script_res:Script = load(path)
		var ok:bool = script_res != null and script_res.can_instantiate()
		if not ok:
			failures += 1
			push_error("COMPILE FAILED: " + path)
	print("COMPILE_RESULT ",JSON.stringify({"scripts":SCRIPTS.size(),"failures":failures}))
	await process_frame
	quit(0 if failures == 0 else 1)
