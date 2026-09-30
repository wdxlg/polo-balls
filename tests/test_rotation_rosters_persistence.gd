extends SceneTree
var checks:int=0
var failures:int=0
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+label)
func run() -> void:
	var game:Node=root.get_node("Game")
	var phase:String=OS.get_cmdline_user_args()[0]
	if phase=="write":
		game.Game_Settings.Rotation_Blue_Count=7;game.Game_Settings.Rotation_Red_Count=9
		game.Game_Settings.Rotation_Multi_Characters=true;game.Game_Settings.Training_Wheel_Battle=true;game.Game_Settings.Rotation_Match_Type="challenge"
		game.save_persistent_settings()
		check(FileAccess.file_exists(game.SETTINGS_PATH),"settings written to isolated user data")
	else:
		game.load_persistent_settings()
		check(game.rotation_team_count("left")==7 and game.rotation_team_count("right")==9,"both quantities loaded by a fresh process")
		check(game.rotation_multi_enabled(),"multi-character preference loaded by a fresh process")
		check(game.is_rotation_wheel_enabled(),"independent wheel preference loaded")
		if phase=="read":
			check(game.Game_Settings.Rotation_Match_Type=="challenge","challenge selection survives restart with wheel on")
			game.set_runtime_game_setting("Training_Wheel_Battle",false,false)
			check(game.get_rotation_match_type()=="challenge","real runtime setter restores challenge when wheel is disabled")
			game.set_runtime_game_setting("Training_Wheel_Battle",true,false)
			game.set_runtime_game_setting("Rotation_Match_Type","duel",false)
			check(game.is_rotation_wheel_enabled(),"changing normal/challenge does not unset the wheel switch")
			var config:=ConfigFile.new();config.load(game.SETTINGS_PATH);config.set_value("game_settings","Rotation_Match_Type","wheel");config.save(game.SETTINGS_PATH)
		else:
			check(game.Game_Settings.Rotation_Match_Type=="duel" and game.is_rotation_wheel_enabled(),"legacy mutually exclusive wheel choice migrates into the independent checkbox")
	print("ROSTER_PERSIST phase=%s checks=%d failures=%d"%[phase,checks,failures]);quit(1 if failures else 0)
