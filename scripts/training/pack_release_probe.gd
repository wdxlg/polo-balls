extends SceneTree
var files:Array[String] = []
var excluded:Array[String] = [".git",".performance_tools","rl_env","node_modules","venv",".venv","__pycache__","logs","recordings","checkpoints"]
var extensions:Array[String] = ["gd","gdshader","tscn","tres","res","scn","png","jpg","jpeg","webp","svg","wav","ogg","mp3","sfxr","ogv","ttf","otf","csv","translation","json","import","uid","cfg","gdextension"]
func _initialize() -> void:
	call_deferred("_run")
func gather(folder:String) -> void:
	for filename:String in DirAccess.get_files_at(folder):
		if filename.get_extension().to_lower() in extensions:
			files.append(folder.path_join(filename))
	for dirname:String in DirAccess.get_directories_at(folder):
		if dirname in excluded or dirname.begins_with("."):
			continue
		gather(folder.path_join(dirname))
func _run() -> void:
	ProjectSettings.set_setting("application/run/main_scene","res://scenes/training/release_benchmark_boot.tscn")
	var settings_file:String = "res://.performance_tools/project.binary"
	var error:int = ProjectSettings.save_custom(settings_file)
	if error != OK:
		push_error("Could not create diagnostic project settings")
		quit(1)
		return
	gather("res://")
	for filename:String in DirAccess.get_files_at("res://.godot/imported"):
		files.append("res://.godot/imported/"+filename)
	for filename:String in ["global_script_class_cache.cfg","uid_cache.bin","extension_list.cfg"]:
		var path:String = "res://.godot/"+filename
		if FileAccess.file_exists(path):
			files.append(path)
	var packer:PCKPacker = PCKPacker.new()
	error = packer.pck_start("res://.performance_tools/godot_release.pck")
	if error != OK:
		quit(2)
		return
	for path:String in files:
		if packer.add_file(path,path) != OK:
			push_error("Could not add "+path)
			quit(3)
			return
	packer.add_file("res://project.binary",settings_file)
	error = packer.flush()
	print("RELEASE_PACK_RESULT files=",files.size()," error=",error)
	quit(error)
