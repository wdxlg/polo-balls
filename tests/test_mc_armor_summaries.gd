extends "res://tests/test_mc_bat_transform.gd"

func run() -> void:
	var center:Vector2 = await setup_world()
	create_timer(60.0).timeout.connect(func(): finish(2))
	var directory := DirAccess.open("res://scenes/characters/我的世界")
	check(directory != null,"Minecraft character directory exists")
	if directory == null:
		finish(1)
		return
	var files:PackedStringArray = directory.get_files()
	files.sort()
	var count:int = 0
	var number_pattern := RegEx.new()
	number_pattern.compile("[0-9０-９%％]")
	var saved_locale:String = game.current_locale
	game.current_locale = "zh"
	var required:Dictionary = {"山羊角": ["山羊", "屏幕外", "击退", "推撞", "穿墙"], "蝙蝠": ["吸附", "生命上限", "吸血鬼", "分裂", "护盾"], "唤魔者": ["尖牙", "恼鬼", "穿过内部墙体"], "末影人": ["闪避", "怒气", "背后"], "潜影贝": ["闭壳", "浮空", "战斗越久"], "女巫": ["误用", "凋零", "炼药间隔固定"], "烈焰人": ["灼烧", "火场", "烈焰棒"], "苦力怕": ["引信", "引雷", "头部"], "蠹虫": ["石砖", "孵化", "上限"], "重锤": ["生命伤害", "成倍增长", "重置"], "钻石剑": ["横扫剑气", "下界合金", "攻速"], "史莱姆": ["跳跃", "减速", "分裂"], "守卫者": ["激光", "尖刺", "受伤"], "恶魂": ["打回", "不分敌我", "地形"], "粘性活塞": ["眩晕", "黏住", "移动越来越慢"], "钓鱼竿": ["收钩", "猛拉", "共用冷却"], "骷髅": ["攻速", "斩杀", "药水"], "铁匠村民": ["锻造", "减伤", "永久"], "木矛": ["蓄速", "穿透", "格挡"], "蜘蛛": ["蛛丝", "蛛网", "扑击"], "溺尸": ["附魔", "落雷", "电网"], "悦灵": ["音符", "投射物", "召回"], "仙人掌": ["长高", "侧面", "反击"], "唱片机": ["声道", "连续命中", "衰减"], "苔藓": ["叠层", "回血", "钻地", "出口"], "木剑": ["蓄力", "耐久", "工作台", "重制"], "监守者": ["开局", "回响", "穿墙穿盾", "安静"], "矿车": ["动力轨", "余速", "制动"], "雾中人": ["迷雾", "潜行", "暴露", "狂暴"], "时钟": ["碰撞", "时间加速", "倒流", "残像"]}
	for file:String in files:
		if not file.ends_with(".tscn"): continue
		var unit:Node = load("res://scenes/characters/我的世界/"+file).instantiate()
		var role:String = file.get_basename()
		world._clear_armor_stand_test_primary_enemy()
		var summary:String = world._armor_test_special_effect_summary(unit,unit.Type_Tags)
		check(not summary.strip_edges().is_empty(),role+" resolves a nonempty armor-stand introduction")
		world._armor_stand_test_primary_script_path = unit.get_script().resource_path
		check(world._armor_test_special_effect_summary(unit,unit.Type_Tags) == summary,role+" keeps its introduction after role locking")
		check(required.has(role),role+" has an explicit mechanism coverage checklist")
		check(number_pattern.search(summary) == null,role+" introduction has no balance numbers")
		for filler:String in ["变红","变色","残影","颤抖","伪3D","发光"]:
			check(not summary.contains(filler),role+" omits cosmetic filler: "+filler)
		for keyword:String in required.get(role,[]):
			check(summary.contains(keyword),role+" documents "+keyword)
		game.current_locale = "en"
		var english_summary:String = world._armor_test_special_effect_summary(unit,unit.Type_Tags)
		check(not english_summary.strip_edges().is_empty() and number_pattern.search(english_summary) == null,role+" alternate locale has a number-free introduction")
		game.current_locale = "zh"
		unit.free()
		count += 1
	check(count == required.size(),"all current Minecraft character scenes were checked")
	world._clear_armor_stand_test_primary_enemy()
	var defaults:Node = BAT.new()
	check(defaults.vampire_damage == 10,"script default vampire damage is 10")
	defaults.free()
	var stand:Node2D = spawn("res://scenes/characters/默认/盔甲架.tscn",center+Vector2(0,200),"Team1")
	stand.state_machine.set_physics_process(false)
	var b:Node2D = spawn(BAT.SCENE_PATH,center)
	b.state_machine.set_physics_process(false)
	await physics_frame
	await process_frame
	pause_members(b)
	check(b.vampire_damage == 10 and b.bat_damage == 5 and totals(b) == Vector2i(250,250),"scene starts five 50-HP bats and only buffs vampire base damage")
	var summary:String = world._build_armor_stand_test_enemy_info()
	check(summary.contains("吸血鬼") and summary.contains("吸附") and number_pattern.search(summary.replace("[color=#F2F2F2]","")) == null,"actual armor-stand HUD displays the number-free bat introduction")
	settle_fusion(b)
	check(b.vampire and b.Damage == 10 and b.attack_damage() == 18.0,"undamaged 250-HP fusion deals 18 damage")
	check(world._build_armor_stand_test_enemy_info() == summary,"vampire form retains the complete bat introduction")
	for row:Vector2i in [Vector2i(29,10),Vector2i(30,11),Vector2i(60,12),Vector2i(150,15),Vector2i(300,20)]:
		b.assign_vitals(row.x,300)
		check(b.attack_damage() == float(row.y),"vampire damage at HP "+str(row.x)+" is "+str(row.y))
	b.assign_vitals(150,300)
	check(b.attack_damage(2.0) == 30.0,"attack multipliers still scale base and HP bonus together")
	b.assign_vitals(250,250)
	b.split_swarm()
	pause_members(b)
	check(world._build_armor_stand_test_enemy_info() == summary,"split swarm keeps its introduction")
	var inherited:bool = true
	for member:Node2D in b.living_members():
		inherited = inherited and member.vampire_damage == 10 and member.attack_damage() == 5.0
	check(inherited,"all split bats inherit vampire damage 10 without changing bat attack")
	settle_fusion(b)
	check(b.vampire and b.attack_damage() == 18.0,"second fusion retains the buff")
	game.current_locale = saved_locale
	finish(0 if failures == 0 else 1)
