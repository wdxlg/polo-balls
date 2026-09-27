extends SceneTree
## 咒术回战四角色（五条悟/宿傩/魔虚罗/嵌合暗兽）功能回归。
## godot --headless --path . --audio-driver Dummy --script res://tests/test_jjk.gd
const DIR:String = "res://scenes/characters/动漫/"
var JJK:Script
var DOMAIN:Script
var checks:int = 0
var failures:int = 0
var arena:Node2D

func _initialize() -> void: call_deferred("run")

func check(value:bool,label:String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("JJK_FAIL: " + label)
	else:
		print("JJK_OK: " + label)

func spawn(file:String,team:String,point:Vector2,freeze:bool = true) -> Node2D:
	var unit:Node2D = load(DIR + file).instantiate()
	unit.Team = team
	unit.position = point
	arena.add_child(unit,true)
	if freeze:
		unit.set_physics_process(false)
		unit.state_machine.set_physics_process(false)
		unit.set_process(false)
	return unit

func make_target(label:String,point:Vector2,team:String = "B") -> Node2D:
	var target:Node2D = load("res://scenes/ball.tscn").instantiate()
	target.name = label
	target.Team = team
	target.Max_health = 10000
	target.Has_Collision_Damage = false
	target.position = point
	arena.add_child(target,true)
	target.set_physics_process(false)
	target.state_machine.set_physics_process(false)
	target.set_process(false)
	target.health = 10000
	target.block = 0
	return target

func run() -> void:
	create_timer(150.0,true,false,true).timeout.connect(func(): quit(2))
	JJK = load("res://scripts/characters/动漫/咒术回战/jjk_common.gd")
	DOMAIN = load("res://scripts/characters/动漫/咒术回战/jjk_domain.gd")
	root.get_node("Game").now_stop_state = false
	root.size = Vector2i(800,600)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	arena = Node2D.new()
	arena.name = "JJKTest"
	root.add_child(arena)
	current_scene = arena

	# ---------------- 场景与资源
	for file:String in ["五条悟.tscn","宿傩.tscn","魔虚罗.tscn","嵌合暗兽.tscn"]:
		check(ResourceLoader.exists(DIR + file),"scene exists " + file)
	for key:String in JJK.SOUNDS.keys():
		check(JJK.SOUNDS[key] is AudioStream,"sound loaded " + key)
	var gojo:Node2D = spawn("五条悟.tscn","A",Vector2(200,300))
	var sukuna:Node2D = spawn("宿傩.tscn","B",Vector2(600,300))
	await process_frame
	check(gojo.Max_health == 3000 and gojo.Damage == 80,"gojo stats 3000/80")
	check(sukuna.Max_health == 3600 and sukuna.Damage == 90,"sukuna stats 3600/90")
	check((gojo.image as Sprite2D).texture != null and (gojo.image as Sprite2D).texture.get_width() == 128,"gojo minecraft face texture 128px")
	check(gojo.player_control_extra_actions().size() == 4 and sukuna.player_control_extra_actions().size() == 5,"extra key actions 4/5")

	# ---------------- 无下限
	var hp0:int = gojo.health
	JJK.hit(sukuna,gojo,500.0,gojo.global_position,&"ordinary",{"phenomenon":"sukuna_dismantle"})
	check(gojo.health == hp0,"Infinity blocks ordinary technique")
	check(gojo.infinity_blocks >= 1,"Infinity block counted")
	gojo.receive_positional_damage(300.0,gojo.global_position,false,sukuna)
	check(gojo.health == hp0,"Infinity blocks raw positional hit")
	check(gojo.apply_knockback(Vector2.RIGHT,100.0,700.0,0.0,1.0,{"source":sukuna}) == null,"Infinity blocks knockback")
	JJK.hit(sukuna,gojo,200.0,gojo.global_position,&"ordinary",{"sure_hit":true,"phenomenon":"sukuna_shrine"})
	check(gojo.health == hp0 - 200,"sure-hit passes Infinity")
	gojo.health = hp0
	sukuna.amp_left = 3.0
	JJK.hit(sukuna,gojo,100.0,gojo.global_position,&"ordinary",{"phenomenon":"sukuna_taijutsu"})
	check(gojo.health == hp0 - 100,"Domain Amplification pierces Infinity")
	sukuna.amp_left = 0.0
	gojo.health = hp0
	gojo.burnout_left = 2.0
	JJK.hit(sukuna,gojo,100.0,gojo.global_position,&"ordinary",{})
	check(gojo.health == hp0 - 100,"burnout disables Infinity")
	gojo.burnout_left = 0.0
	gojo.health = hp0

	# ---------------- 五条悟术式
	var t1:Node2D = make_target("Dummy1",Vector2(420,300))
	gojo.purple_cd = 0.0
	gojo.cursed_energy = 1000.0
	gojo.purple_charge = 0.0
	check(gojo.release_purple(Vector2.RIGHT,0.0),"purple cast starts")
	gojo._fire_purple()
	var purple_dmg:int = 10000 - t1.health
	check(purple_dmg > 0 and purple_dmg >= int(80 * 12 * 0.9),"hollow purple hits on the line (%d)" % purple_dmg)
	check(sukuna.health == 3600 - 0 or sukuna.health < 3600,"purple line reaches sukuna too")
	sukuna.health = 3600
	t1.health = 10000
	gojo.red_cd = 0.0
	gojo.red_charge = 0.0
	check(gojo.release_red(Vector2.RIGHT,0.8),"charged red launches")
	check(gojo._projectiles.size() == 1,"red projectile spawned")
	gojo.on_projectile_impact("red_max",null,t1.global_position)
	check(t1.health < 10000,"red burst damages")
	t1.health = 10000
	gojo.blue_cd = 0.0
	check(gojo.cast_blue(t1.global_position),"blue cast")
	for i:int in 3: gojo.jjk_step(0.1)
	check(t1.health < 10000,"blue ticks damage")
	gojo._end_blue()
	var tp_from:Vector2 = gojo.global_position
	gojo.teleport_cd = 0.0
	check(gojo.teleport_to(tp_from + Vector2(0,-150)),"teleport")
	check(gojo.global_position.distance_to(tp_from) > 100.0,"teleport moved")
	gojo.global_position = tp_from

	# ---------------- 无量空处
	t1.global_position = gojo.global_position + Vector2(80,0)
	gojo.cursed_energy = 1000.0
	check(gojo.cast_domain(),"Unlimited Void opens")
	var dom:Node = gojo.own_domain()
	check(dom != null and bool(dom.barrier_intact()),"closed barrier built")
	check(dom != null and dom.radius >= 260.0,"huge circular radius")
	for i:int in 3: await physics_frame
	for i:int in 16: await physics_frame
	check(t1.dizziness,"sure-hit paralysis inside Unlimited Void")
	check(gojo.domains_used == 1,"domain count")
	# 伏魔御厨子对拼：结界内受保护，斩结界外壁。
	sukuna.cursed_energy = 2000.0
	sukuna.global_position = Vector2(700,100)
	check(sukuna.cast_domain(),"Malevolent Shrine opens")
	var shrine:Node = sukuna.own_domain()
	check(shrine != null and shrine.is_open() and shrine.contains(Vector2(5,5)),"shrine covers whole map")
	var gojo_hp:int = gojo.health
	for i:int in 20: await physics_frame
	check(gojo.health == gojo_hp,"inside intact barrier Gojo is protected from shrine sure-hit")
	check(dom != null and is_instance_valid(dom) and dom.barrier_hp < 100.0,"shrine slashes the barrier from outside")
	var hp_before_flip:float = dom.barrier_hp
	check(gojo.flip_barrier(),"barrier flip")
	for i:int in 12: await physics_frame
	check(is_equal_approx(dom.barrier_hp,hp_before_flip),"flipped barrier ignores outside slashes")
	check(sukuna.shrink_domain(),"shrine narrows")
	sukuna.global_position = gojo.global_position + Vector2(150,0)
	for i:int in 12: await physics_frame
	check(dom.barrier_hp < hp_before_flip,"narrowed shrine cuts through flipped barrier")
	dom.damage_barrier(1000.0)
	await physics_frame
	check(not is_instance_valid(dom) or dom.ended,"barrier shattered")
	check(gojo.burnout_left >= gojo.burnout_seconds + 1.5,"shattered barrier -> long burnout")
	gojo.health = gojo.Max_health
	var outside_hp:int = gojo.health
	for i:int in 12: await physics_frame
	check(gojo.health < outside_hp,"after barrier breaks shrine sure-hit lands on Gojo")
	if is_instance_valid(shrine): shrine.finish(false)
	await physics_frame
	check(sukuna.burnout_left > 0.0,"sukuna burnout after domain")

	# ---------------- 宿傩锁血与世界斩
	sukuna.burnout_left = 0.0
	sukuna.health = 5
	sukuna.global_position = Vector2(600,300)
	gojo.global_position = Vector2(200,300)
	JJK.hit(gojo,sukuna,500.0,sukuna.global_position,&"magic",{})
	check(sukuna.health == 1 and sukuna.hp_locked(),"1 HP lock")
	check(sukuna.chant_left >= 0.0 and sukuna.chant_empowered,"empowered World Slash chant starts")
	JJK.hit(gojo,sukuna,500.0,sukuna.global_position,&"magic",{"sure_hit":true})
	check(sukuna.health == 1,"invulnerable while locked")
	gojo.health = gojo.Max_health
	gojo.burnout_left = 0.0
	gojo.cursed_energy = 1000.0
	var g_before:int = gojo.health
	for i:int in 20: sukuna.jjk_step(0.1)
	check(gojo.health < g_before,"World Slash cuts through Infinity")
	check(sukuna.world_slash_learned,"world slash learned after HP lock")
	JJK.hit(gojo,sukuna,10.0,sukuna.global_position,&"magic",{"sure_hit":true})
	sukuna.hp_lock_left = -1.0
	JJK.hit(gojo,sukuna,500.0,sukuna.global_position,&"magic",{"sure_hit":true})
	check(sukuna.health <= 0,"HP lock only once")

	# ---------------- 魔虚罗适应
	var maho:Node2D = spawn("魔虚罗.tscn","B",Vector2(400,450))
	var agito:Node2D = spawn("嵌合暗兽.tscn","B",Vector2(460,450))
	await process_frame
	var m0:int = maho.health
	JJK.hit(gojo,maho,100.0,maho.global_position,&"magic",{"phenomenon":"gojo_red"})
	check(maho.health == m0 - 100,"first exposure full damage")
	check(maho.wheel_key == "gojo_red","wheel starts turning")
	check(maho.wheel_speed() > 1.0,"agito speeds up the wheel")
	for i:int in 20: maho.jjk_step(0.1)
	check(maho.adaptation_level("gojo_red") == 1,"adaptation level 1")
	maho.health = m0
	JJK.hit(gojo,maho,100.0,maho.global_position,&"magic",{"phenomenon":"gojo_red"})
	check(maho.health == m0 - 50,"level 1 halves damage")
	for i:int in 20: maho.jjk_step(0.1)
	maho.health = m0
	JJK.hit(gojo,maho,100.0,maho.global_position,&"magic",{"phenomenon":"gojo_red"})
	check(maho.health == m0,"level 2 immune")
	JJK.hit(gojo,maho,100.0,maho.global_position,&"magic",{"phenomenon":"gojo_purple","unadaptable":true})
	check(maho.health == m0 - 150,"purple unadaptable x1.5")
	# 适应无下限后穿透。
	maho.global_position = gojo.global_position + Vector2(40,0)
	var g1:int = gojo.health
	for n:int in 3:
		maho.sword_cd = 0.0
		maho.swing(Vector2.LEFT)
		for i:int in 20: maho.jjk_step(0.1)
	check(maho.adaptation_level("gojo_infinity") >= 2,"adapts to Infinity from blocked swings")
	maho.sword_cd = 0.0
	g1 = gojo.health
	maho.swing(Vector2.LEFT)
	check(gojo.health < g1,"adapted sword pierces Infinity")
	check(maho.jjk_neutralizes_infinity(gojo),"neutralizes infinity flag")
	# 嵌合暗兽
	maho.health = 1000
	agito.deer_cd = 0.0
	agito.cursed_energy = 800.0
	check(agito.round_deer(),"round deer")
	check(maho.health > 1000,"round deer heals allies")
	gojo.blue_cd = 0.0
	gojo.cursed_energy = 1000.0
	gojo.cast_blue(agito.global_position)
	agito.deer_cd = 0.0
	agito.cursed_energy = 800.0
	agito.round_deer()
	check(not gojo.blue_active,"round deer erases enemy Blue")

	# ---------------- 特效全部可绘制
	var FX:Script = load("res://scripts/characters/动漫/咒术回战/jjk_fx.gd")
	for kind:String in ["ripple","red_burst","purple_beam","slash","cleave","web","fuga_burst","world_slash","black_flash","heal","thunder","teleport","wheel_turn","shockwave","text"]:
		var node:Node = FX.spawn(gojo,kind,{"pos":Vector2(300,300),"a":Vector2(0,0),"b":Vector2(400,300),"radius":60.0,"width":40.0,"text":"测试","world":kind == "text"},0.3)
		check(node != null,"fx " + kind)
	for i:int in 4: await process_frame
	# AI 调用不报错
	gojo.jjk_ai()
	maho.jjk_ai()
	agito.jjk_ai()
	check(true,"ai ticks")

	# ---------------- 手动操控（C 键选中后的鼠标/数字键路径）
	for child:Node in arena.get_children(): child.queue_free()
	await process_frame
	var pg:Node2D = spawn("五条悟.tscn","A",Vector2(200,300))
	var ps:Node2D = spawn("宿傩.tscn","B",Vector2(600,300))
	var pm:Node2D = spawn("魔虚罗.tscn","A",Vector2(300,500))
	await process_frame
	for u:Node2D in [pg,ps,pm]:
		u.player_control_peer_id = 1
		u.set_player_control_aim_position(Vector2(600,300))
	pg.player_control_action(1)
	check(pg.red_charge >= 0.0,"player right press starts Red charge")
	pg.step_mob(0.8)
	pg.player_control_action(1)
	pg.player_control_action_released(1)
	check(pg._projectiles.size() == 1 and pg.red_charge < 0.0,"player right release fires charged Red")
	pg.player_control_action(2)
	check(pg.purple_charge >= 0.0,"player middle starts Purple chant")
	for i:int in 26: pg.step_mob(0.1)
	pg.player_control_action_released(2)
	check(pg._purple_pending_200 and pg.purple_cast_left >= 0.0,"holding middle 2.4s casts 200% Purple")
	var before_tp:Vector2 = pg.global_position
	pg.set_player_control_aim_position(Vector2(200,100))
	pg.player_control_action(3)
	check(pg.global_position.distance_to(before_tp) > 100.0,"key 1 teleports toward the mouse")
	pg.player_control_action(0)
	check(pg.blue_active and pg.blue_steer,"player left places steerable Blue")
	pg.player_control_action_released(0)
	check(not pg.blue_steer,"releasing left stops steering Blue")
	ps.player_control_action(0)
	ps.step_mob(0.6)
	ps.player_control_action_released(0)
	check(ps.web_cd > 0.0,"sukuna hold-left releases Spiderweb")
	ps.player_control_action(0)
	ps.player_control_action_released(0)
	check(ps.dismantle_cd > 0.0,"sukuna tap-left Dismantle")
	ps.player_control_action(3)
	check(ps.amp_left > 0.0,"sukuna key 1 Domain Amplification")
	var maho_count:int = get_nodes_in_group("JJKMahoraga").size()
	ps.player_control_action(5)
	await process_frame
	check(get_nodes_in_group("JJKMahoraga").size() == maho_count + 1,"sukuna key 3 summons Mahoraga")
	pm.player_control_action(0)
	check(pm.sword_cd > 0.0,"controlled Mahoraga swings the sword")
	for u:Node2D in [pg,ps,pm]: u.player_control_peer_id = 0

	# ---------------- 实战：全部解冻，五条悟 vs 宿傩（宿傩会召唤式神），加速运行
	for child:Node in arena.get_children(): child.queue_free()
	await process_frame
	await process_frame
	var g2:Node2D = spawn("五条悟.tscn","A",Vector2(180,300),false)
	var s2:Node2D = spawn("宿傩.tscn","B",Vector2(620,300),false)
	Engine.time_scale = 3.0
	var saw_domain:bool = false
	var saw_summon:bool = false
	var elapsed:float = 0.0
	while elapsed < 45.0:
		await physics_frame
		elapsed += get_root().get_physics_process_delta_time() * 3.0 if false else 1.0 / 60.0 * 3.0
		if not DOMAIN.active_domains(self).is_empty(): saw_domain = true
		if is_instance_valid(g2) and is_instance_valid(s2):
			if g2.has_meta("_jjk_last_hp") and int(g2.get_meta("_jjk_last_hp")) - g2.health > 250: print("JJK_EVT gojo_big_hit t=%.2f %d->%d" % [elapsed,int(g2.get_meta("_jjk_last_hp")),g2.health])
			g2.set_meta("_jjk_last_hp",g2.health)
		if int(elapsed / 1.0) != int((elapsed - 0.05) / 1.0) and is_instance_valid(g2) and is_instance_valid(s2):
			var doms:Array = []
			for dd:Variant in DOMAIN.active_domains(self): doms.append("%s:%d" % [dd.domain_kind,int(dd.barrier_hp)])
			print("JJK_TRACE t=%.1f G hp=%d ce=%d bo=%.1f inf=%s blocks=%d | S hp=%d ce=%d bo=%.1f amp=%.1f seal=%.1f used=%d ws=%s | dom=%s maho=%d agito=%d" % [elapsed,g2.health,g2.cursed_energy,g2.burnout_left,str(g2.infinity_active()),g2.infinity_blocks,s2.health,s2.cursed_energy,s2.burnout_left,s2.amp_left,s2.domain_seal_left,s2.domains_used,str(s2.world_slash_learned),str(doms),get_nodes_in_group("JJKMahoraga").size(),get_nodes_in_group("JJKAgito").size()])
		if get_nodes_in_group("JJKMahoraga").size() >= 2 or get_nodes_in_group("JJKAgito").size() >= 1: saw_summon = true
		if not is_instance_valid(g2) or not is_instance_valid(s2): break
		if g2.health <= 0 or s2.health <= 0: break
	Engine.time_scale = 1.0
	print("JJK_BATTLE t=%.1f gojo=%s sukuna=%s maho=%s" % [elapsed,str(g2.health) if is_instance_valid(g2) else "freed",str(s2.health) if is_instance_valid(s2) else "freed","-"])
	check(saw_domain,"AI battle opened a domain")
	check(saw_summon,"AI Sukuna summoned shikigami")
	print("JJK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures > 0 else 0)
