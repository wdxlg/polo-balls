extends SceneTree
## 我的世界烟花：形状粒子数、火箭飞行、拖尾/渐变、闪光、屏幕底部庆祝、比赛结束挂钩。
var checks:int = 0
var failures:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("MC_FIREWORK FAIL: "+label)
func run() -> void:
	create_timer(90.0,true,false,true).timeout.connect(func(): print("MC_FIREWORK TIMEOUT"); quit(2))
	var FW:GDScript = load("res://scripts/effects/我的世界/mc_firework.gd")
	var host := Node2D.new()
	root.add_child(host)
	# 直接炸开：每种形状按 Java 生成循环的粒子数。
	var expected:Dictionary = {"small_ball":98,"large_ball":386,"star":121,"creeper":265,"burst":70}
	for shape:String in expected.keys():
		var fw = FW.burst(host,Vector2(100,100),{"shape":shape,"colors":["red"],"trail":false,"twinkle":false,"sound":false,"seed":7})
		fw.set_process(false)
		fw.step_ticks(1)
		check(fw.sparks.count() == int(expected[shape]) and fw.rockets.is_empty(),"%s burst spawns %d sparks (got %d)" % [shape,expected[shape],fw.sparks.count()])
		fw.free()
	var ball = FW.burst(host,Vector2(0,0),{"shape":"large_ball","colors":["light_blue"],"fade_colors":["yellow"],"trail":true,"twinkle":true,"sound":false,"seed":3})
	ball.set_process(false)
	ball.step_ticks(1)
	check(ball.flashes.size() == 1 and (ball.flashes[0].color as Color).is_equal_approx(FW.DYE_COLORS.light_blue),"explosion flash uses the first explosion color")
	var radius_start:float = 0.0
	for i:int in range(ball.sparks.count()): radius_start = maxf(radius_start,Vector2(ball.sparks.x[i],ball.sparks.y[i]).length())
	ball.step_ticks(10)
	var radius_later:float = 0.0
	for i:int in range(ball.sparks.count()): radius_later = maxf(radius_later,Vector2(ball.sparks.x[i],ball.sparks.y[i]).length())
	check(ball.flashes.is_empty(),"flash lasts four ticks")
	check(radius_later > radius_start * 3.0 and radius_later < 6.0,"large ball expands to about 5 blocks: %.2f" % radius_later)
	check(ball.trail_sparks.count() > 0,"trail sparks leave static children")
	ball.step_ticks(30)
	var faded:bool = ball.sparks.count() > 0 and absf(ball.sparks.b[0] - (FW.DYE_COLORS.yellow as Color).b) < 0.05
	check(faded,"fade color takes over after half the spark life")
	ball.step_ticks(80)
	check(ball.is_finished(),"every spark expires (MC lifetime 48-59 ticks)")
	ball.free()
	# 火箭：按 Java 规则加速上升，飞行时间 10*(flight+1)+rand(6)+rand(7) tick，到时炸开。
	var rocket = FW.launch(host,Vector2(0,0),{"flight":1,"shape":"star","colors":["lime"],"sound":false,"seed":11})
	rocket.set_process(false)
	var lifetime:int = int(rocket.rockets[0].lifetime)
	check(lifetime >= 20 and lifetime <= 31,"flight 1 lifetime in Java range: %d" % lifetime)
	rocket.step_ticks(5)
	check(rocket.rockets.size() == 1 and float(rocket.rockets[0].y) > 0.5 and rocket.sparks.count() == 5,"rocket rises and drops one white spark per tick")
	rocket.step_ticks(lifetime - 4)
	var height:float = 0.05 * (lifetime + 1) + 0.02 * (lifetime + 1) * (lifetime + 2)
	check(rocket.rockets.is_empty() and rocket.flashes.size() == 1 and absf(float(rocket.flashes[0].y) - height) < 0.01,"rocket explodes at Java height %.1f blocks" % height)
	rocket.free()
	# 多个爆炸隔 2 tick 依次炸开。
	var multi = FW.burst(host,Vector2.ZERO,{"explosions":[{"shape":"small_ball","colors":["red"]},{"shape":"burst","colors":["blue"]}],"sound":false,"seed":5})
	multi.set_process(false)
	multi.step_ticks(1)
	var first_count:int = multi.sparks.count()
	multi.step_ticks(2)
	check(first_count == 98 and multi.sparks.count() == 98 + 70,"second explosion follows two ticks later")
	multi.free()
	# 屏幕底部庆祝：所有火箭从底部出发，炸点都在屏幕里。
	var show = FW.celebrate(host,{"count":12,"duration":2.6,"sound":false,"seed":21})
	show.set_process(false)
	var view:Vector2 = show.get_viewport_rect().size
	var launched_from_bottom:bool = true
	var exploded_on_screen:bool = true
	var explosions:int = 0
	for t:int in range(200):
		show.step_ticks(1)
		for r:Dictionary in show.rockets:
			if int(r.life) == 1: launched_from_bottom = launched_from_bottom and show.to_local_px(Vector2(r.ox,r.oy)).y >= view.y
		for f:Dictionary in show.flashes:
			if int(f.age) == 1:
				explosions += 1
				var p:Vector2 = show.to_local_px(Vector2(f.x,f.y))
				exploded_on_screen = exploded_on_screen and p.y > view.y * 0.05 and p.y < view.y * 0.85 and p.x > 0.0 and p.x < view.x
	check(show.screen_space and is_equal_approx(show.unit,view.y / 40.0),"show is screen-space and scales with screen height")
	check(launched_from_bottom and explosions == 12,"all 12 rockets launch from the bottom edge and explode (%d)" % explosions)
	check(exploded_on_screen,"every explosion happens inside the screen")
	show.step_ticks(120)
	check(show.is_finished(),"show finishes and can free itself")
	show.free()
	host.free()
	# 比赛结束挂钩：普通模式结算放烟花；重置会停掉。
	var game:Node = root.get_node("Game")
	var saved:Dictionary = game.Game_Settings.duplicate(true)
	game.Game_Settings.Training_Mode = false
	game.Game_Settings.Training_Mode_Type = "manual"
	game.Game_Settings.Training_Boss_Intro = false
	var world:Node = load("res://scenes/world.tscn").instantiate()
	world.tree_entered.connect(func(): current_scene = world,CONNECT_ONE_SHOT)
	root.add_child(world)
	if is_instance_valid(world._mc_prewarmer): world._mc_prewarmer.free()
	await process_frame
	await process_frame
	world._trigger_victory_bell()
	check(is_instance_valid(world._match_fireworks) and world._match_fireworks.get_parent() == world,"normal match end launches fireworks in the world canvas")
	var first_show:Node = world._match_fireworks
	world._trigger_victory_bell()
	check(world._match_fireworks == first_show,"one show per finished match")
	world.reset()
	await process_frame
	check(not is_instance_valid(first_show) and world._match_fireworks == null,"reset stops the fireworks")
	game.Game_Settings = saved
	world.queue_free()
	await process_frame
	print("MC_FIREWORK_RESULT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

