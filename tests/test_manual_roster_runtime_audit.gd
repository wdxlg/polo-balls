extends SceneTree
## Dynamic census of every character, creature and shooter scene.
## No scene enters the tree; actions/opt-in here reflect PRE-_ready values only.
## The C selector and any conditional runtime actions are checked by the role tests.

var paths:Array[String] = []
var loaded:int = 0
var failed:int = 0
var missing_actions:int = 0
var primary_count:int = 0
var creature_count:int = 0
var eligible_creatures:int = 0

func _initialize() -> void:
	call_deferred("audit")

func collect_scenes(folder:String) -> void:
	var directory:DirAccess = DirAccess.open(folder)
	if directory == null:
		push_error("Cannot list " + folder)
		failed += 1
		return
	for item:String in directory.get_files():
		if item.ends_with(".tscn"):
			paths.append(folder.path_join(item))
	for subfolder:String in directory.get_directories():
		collect_scenes(folder.path_join(subfolder))

func audit() -> void:
	for directory:String in ["res://scenes/characters","res://scenes/creatures","res://scenes/shooter"]:
		collect_scenes(directory)
	paths.sort()
	for path:String in paths:
		var resource:Resource = load(path)
		if not resource is PackedScene:
			failed += 1
			print("ROSTER_LOAD_FAILED\t",path)
			continue
		var actor:Node = (resource as PackedScene).instantiate()
		if actor == null:
			failed += 1
			print("ROSTER_INSTANTIATE_FAILED\t",path)
			continue
		loaded += 1
		var category:String = "characters" if "/characters/" in path else "creatures" if "/creatures/" in path else "shooter"
		var methods:PackedStringArray = PackedStringArray()
		if actor.has_method("player_control_action_ids"):
			var actions:Variant = actor.call("player_control_action_ids")
			if actions is Array:
				for action:Variant in actions:
					methods.append(str(action))
		var mode:int = int(actor.get("Type")) if actor.has_method("can_player_control") else -1
		var opted:bool = bool(actor.get("manual_controllable_subentity")) if actor.has_method("can_player_control") else false
		if category == "characters" and mode == 0:
			primary_count += 1
			if methods.is_empty():
				missing_actions += 1
				print("ROSTER_NO_ACTION\t",path)
		elif mode == 3:
			creature_count += 1
			if opted: eligible_creatures += 1
		print("ROSTER_ENTRY\t",category,"\t",path,"\t",mode,"\t",str(opted),"\t",",".join(methods))
		actor.free()
	print("ROSTER_AUDIT_RESULT scenes=",paths.size()," loaded=",loaded," failed=",failed," primary=",primary_count," pre_ready_no_actions=",missing_actions," creatures=",creature_count," pre_ready_opted_in=",eligible_creatures)
	quit(0 if failed == 0 else 1)
