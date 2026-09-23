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
	return {"groups":groups, "settings":settings, "armor_test":world != null and world._armor_stand_test_hud_active}

static func t(key:String, locale:String) -> String:
	return Game._localization._t_for_locale(key, locale, false).replace("_", " ")

static func title(data:Dictionary, locale:String) -> String:
	var zh:bool = locale == "zh"
	var sides:PackedStringArray = []
	for group:Dictionary in data.groups:
		var names:PackedStringArray = []
		var random_count:int = 0
		for member:Dictionary in group.members:
			if bool(member.get("random_choice", false)): random_count += 1
			else: names.append(t(str(member.get("char", "")), locale))
		if random_count == group.members.size() and random_count > 0:
			if not str(group.team).is_empty() or random_count > 1:
				names.append(("%d人随机队伍" if zh else "%d-Person Random Team") % random_count)
			else: names.append("随机人物" if zh else "Random Character")
		elif random_count > 0:
			names.append(("%d个随机人物" if zh else "%d Random Characters") % random_count)
		sides.append(" + ".join(names))
	var matchup:String = " vs ".join(sides)
	if matchup.is_empty(): matchup = "自由对战" if zh else "Free Battle"
	var s:Dictionary = data.settings
	var prefix:String = ""
	if data.get("armor_test", false): prefix = "盔甲架测试" if zh else "Armor Stand Test"
	else:
		match str(s.get("Training_Mode_Type", "manual")):
			"rotation":
				prefix = ("逐个挑战" if zh else "Individual Challenge") if s.get("Rotation_Match_Type", "duel") == "challenge" else ("轮放对决" if zh else "Rotation Duel")
			"timed": prefix = ("计时%s秒" if zh else "Timed %ss") % String.num(float(s.get("Training_Timed_Duration", 60))).trim_suffix(".0")
			"boss": prefix = ("Boss车轮战" if zh else "Boss Wheel Battle") if s.get("Training_Boss_Wheel_Battle", false) else ("Boss模式" if zh else "Boss Battle")
			_:
				if s.get("Training_Mode", false): prefix = "手动训练" if zh else "Manual Training"
	if str(s.get("Training_Mode_Type", "")) == "boss": prefix += " x%s" % String.num(float(s.get("Training_Boss_Multiplier", 3))).trim_suffix(".0")
	return (prefix + "_" if not prefix.is_empty() else "") + matchup

static func filename(data:Dictionary, locale:String, stamp:String, root:String) -> String:
	var text:String = title(data, "zh")
	for invalid:String in ["<", ">", ":", '"', "/", "\\", "|", "?", "*", "\n", "\r", "\t"]: text = text.replace(invalid, "-")
	var prefix:String = "中文_" if locale == "zh" else "英文_"
	# Reserve room for .video.mp4 / .audio.f32 and keep Windows paths below MAX_PATH.
	var budget:int = mini(160, 238 - root.length() - prefix.length() - stamp.length() - 16)
	if budget < 12: return ""
	if text.length() > budget: text = text.left(budget - 9) + "~" + text.sha256_text().left(8)
	return prefix + text.strip_edges().trim_suffix(".") + "_" + stamp + ".mp4"
