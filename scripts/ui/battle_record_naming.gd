extends RefCounted
## Snapshot the INITIAL matchup, never infer random selection from the sampled name.
static func snapshot(world:Node, simulated:bool) -> Dictionary:
	var groups:Array = []
	var settings:Dictionary = Game.Game_Settings.duplicate(true)
	var mode:String = str(settings.get("Training_Mode_Type", "manual"))
	if world != null:
		if mode == "rotation" or (mode == "boss" and settings.get("Training_Boss_Wheel_Battle", false)):
			var rosters:Dictionary = world._rotation_rosters
			if simulated and rosters.left.is_empty() and rosters.right.is_empty(): rosters = world._rotation_saved_rosters
			for side:String in ["left", "right"]:
				if not rosters[side].is_empty(): groups.append({"team":side, "members":rosters[side].duplicate(true)})
		else:
			var entries:Array = world._battle_setup
			if simulated and entries.is_empty(): entries = world._last_battle_setup
			var indices:Dictionary = {}
			for entry:Dictionary in entries:
				var team:String = str(entry.get("team", ""))
				var key:String = team if not team.is_empty() else "solo:%s" % str(entry.get("id", groups.size()))
				if not indices.has(key):
					indices[key] = groups.size()
					groups.append({"team":team, "members":[]})
				groups[indices[key]].members.append(entry.duplicate(true))
		if groups.is_empty():
			var sides:Dictionary = world.return_battle_sides()
			for side:String in sides.order:
				var entries:Array = []
				for name:String in sides.members[side]: entries.append({"char":name})
				groups.append({"team":side if side.begins_with("team:") else "", "members":entries})
	var armor_test:bool = world != null and bool(world.get("_armor_stand_test_hud_active"))
	var armor_role:String = ""
	if armor_test and world.has_method("_armor_stand_test_first_enemy"):
		# Reuse the introduction's primary-role lock; summons/death bridges must
		# not rename the recording, and the old saved matchup may contain dead foes.
		world.call("_armor_stand_test_first_enemy")
		var identity:Variant = world.get("_armor_stand_test_primary_identity")
		if identity != null: armor_role = str(identity)
	return {"groups":groups, "settings":settings, "armor_test":armor_test, "armor_role":armor_role}

static func t(key:String, locale:String) -> String:
	return Game._localization._t_for_locale(key, locale, false).replace("_", " ")

static func _quantity(name:String, count:int, zh:bool) -> String:
	if count <= 1: return name
	return ("%d个%s" % [count,name]) if zh else ("%s * %d" % [name,count])

static func title(data:Dictionary, locale:String) -> String:
	var zh:bool = locale == "zh"
	if bool(data.get("armor_test",false)):
		var role:String = str(data.get("armor_role","")).strip_edges()
		var role_name:String = t(role,locale) if not role.is_empty() else ("新角色" if zh else "New Character")
		return role_name
	var sides:PackedStringArray = []
	for group:Dictionary in data.groups:
		var counts:Dictionary = {} # Insertion order preserves the initial team/roster order.
		var random_count:int = 0
		for member:Dictionary in group.members:
			if bool(member.get("random_choice", false)): random_count += 1
			else:
				var key:String = str(member.get("char", ""))
				if not key.is_empty(): counts[key] = int(counts.get(key,0)) + 1
		var names:PackedStringArray = []
		for key:String in counts: names.append(_quantity(t(key,locale),int(counts[key]),zh))
		if random_count > 0:
			names.append(_quantity("随机人物" if zh else "Random Character",random_count,zh))
		if not names.is_empty(): sides.append(" + ".join(names))
	var matchup:String = " vs ".join(sides)
	if matchup.is_empty(): matchup = "自由对战" if zh else "Free Battle"
	# Mode, duration and boss HP multiplier are not part of a matchup/headcount.
	return matchup

static func _safe_stem(text:String) -> String:
	# Windows forbids ASCII ':' and '*'; keep their appearance in filenames.
	# title() remains untouched so MP4 metadata uses the exact requested spelling.
	text = text.replace(":","：").replace("*","＊")
	for invalid:String in ["<", ">", '"', "/", "\\", "|", "?"]: text = text.replace(invalid,"-")
	for code:int in range(1,32): text = text.replace(String.chr(code),"-")
	text = text.strip_edges()
	while text.ends_with("."): text = text.trim_suffix(".").strip_edges()
	var device:String = text.get_slice(".",0).to_upper()
	if device in ["CON","PRN","AUX","NUL"] or ((device.begins_with("COM") or device.begins_with("LPT")) and device.length() == 4 and device.right(1) in ["1","2","3","4","5","6","7","8","9","¹","²","³"]):
		text = "_" + text
	return text

static func _occupied(path:String) -> bool:
	var stem:String = path.get_basename()
	for candidate:String in [path,stem + ".video.mp4",stem + ".audio.f32",stem + "_frames"]:
		if FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(candidate): return true
	return false

static func filename(data:Dictionary, locale:String, _stamp:String, root:String) -> String:
	var text:String = _safe_stem(title(data,locale))
	# No timestamp/language/mode prefix. Reserve room for temporary encoder paths.
	var budget:int = mini(160,238 - root.length() - 16)
	var minimum:int = 12 # Keep role text plus the truncation hash, without branding prefixes.
	if budget < minimum: return ""
	var serial:int = 1
	while true:
		var suffix:String = "" if serial == 1 else " (%d)" % serial
		var limit:int = budget - suffix.length()
		if limit < minimum: return ""
		var stem:String = text if text.length() <= limit else text.left(limit - 9) + "~" + text.sha256_text().left(8)
		var candidate:String = stem + suffix + ".mp4"
		if not _occupied(root.path_join(candidate)): return candidate
		serial += 1
	return ""
