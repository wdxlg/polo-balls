extends SceneTree
## 2026-09-29 凋零计时回归：等级变化不重置 1 秒扣血时钟（公共 wither/status.gd，
## 凋灵头颅/女巫药水/凋灵骷髅等所有来源共用同一状态节点）。旧实现每次升级都把时钟
## 重新设为 1 秒，凋灵骷髅两轮砍击间隔 0.97 秒，贴身连砍期间凋零一次都不结算。
var EFFECTS:Script
var checks:int = 0
var failures:int = 0
var arena:Node2D
const DT:float = 1.0/60.0

func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("WITHER_TICK_PASS: "+label)
	else:
		failures += 1
		push_error("WITHER_TICK_FAIL: "+label)

func dummy(label:String,point:Vector2,team:String = "B") -> Node2D:
	var target:Node2D = load("res://scenes/ball.tscn").instantiate()
	target.name = label
	target.Team = team
	target.Max_health = 10000
	target.Has_Collision_Damage = false
	target.position = point
	target.get_node("CharacterAutoFit").enabled = false
	var shape := CircleShape2D.new()
	shape.radius = 9.0
	target.get_node("hurtbox/CollisionShape2D").shape = shape
	target.get_node("CollisionShape2D").disabled = true
	target.get_node("hitbox/CollisionShape2D").disabled = true
	arena.add_child(target,true)
	target.set_physics_process(false)
	target.state_machine.set_physics_process(false)
	target.set_process(false)
	target.health = 10000
	target.block = 0
	return target

## Steps a manually driven status and returns [[time, loss, level], ...].
func drive(victim:Node2D,status:Node,frames:int,on_frame:Callable) -> Array:
	var pulses:Array = []
	var previous:float = float(victim.health)
	for frame:int in range(frames):
		on_frame.call(frame)
		status._physics_process(DT)
		var loss:float = previous-float(victim.health)
		if loss > 0.0: pulses.append([float(frame+1)*DT,loss,EFFECTS.level_of(victim,"wither")])
		previous = float(victim.health)
	return pulses

func run() -> void:
	EFFECTS = load("res://scripts/effects/我的世界/mc_status_effects.gd")
	create_timer(90.0,true,false,true).timeout.connect(func(): print("WITHER_TICK_TIMEOUT"); quit(2))
	root.get_node("Game").now_stop_state = false
	AudioServer.set_bus_mute(0,true)
	arena = Node2D.new()
	arena.name = "WitherTickPhaseTest"
	root.add_child(arena)
	current_scene = arena
	var source:Node2D = dummy("Source",Vector2(-600,-600),"A")
	var other:Node2D = dummy("OtherSource",Vector2(-700,-600),"A")
	await process_frame

	# --- A: upgrades every 0.5 s (faster than the 1 s period) still pulse once per second ---
	var a:Node2D = dummy("VictimA",Vector2(100,100))
	EFFECTS.apply_effect(a,"wither",1,3.0,source)
	var status:Node = EFFECTS.current(a,"wither")
	status.set_physics_process(false)
	check(is_equal_approx(status.tick_left,1.0),"first application arms a 1 s clock (no instant damage)")
	var level:Array[int] = [1]
	var pulses:Array = drive(a,status,60*4,func(frame:int) -> void:
		if frame > 0 and frame % 30 == 0 and level[0] < 8:
			level[0] += 1
			EFFECTS.apply_effect(a,"wither",level[0],3.0,source))
	print("A pulses: ",pulses)
	check(pulses.size() == 4,"4 pulses in 4 s while the level rises every 0.5 s (old reset: 0)")
	var times_ok:bool = pulses.size() == 4
	var losses:Array = []
	for i:int in range(pulses.size()):
		times_ok = times_ok and absf(float(pulses[i][0])-float(i+1)) < 0.02
		losses.append(int(pulses[i][1]))
	check(times_ok,"pulses stay on the original 1/2/3/4 s clock")
	check(losses == [200,400,600,800],"each pulse settles the level current at that moment (II/IV/VI/VIII of 10000 max HP)")

	# --- B: same-level refresh does not shift the phase either ---
	var b:Node2D = dummy("VictimB",Vector2(200,100))
	EFFECTS.apply_effect(b,"wither",2,3.0,source)
	status = EFFECTS.current(b,"wither")
	status.set_physics_process(false)
	pulses = drive(b,status,60,func(frame:int) -> void:
		if frame == 36: EFFECTS.apply_effect(b,"wither",2,3.0,source))
	check(pulses.size() == 1 and absf(float(pulses[0][0])-1.0) < 0.02 and int(pulses[0][1]) == 200,"same-level refresh at 0.6 s keeps the 1.0 s pulse")
	check(is_equal_approx(status.remaining,3.0-0.4+DT) or absf(status.remaining-2.6) < 0.05,"refresh still renews this source's 3 s lifetime")

	# --- C: level drop when a stronger source expires keeps the clock ---
	var c:Node2D = dummy("VictimC",Vector2(300,100))
	EFFECTS.apply_effect(c,"wither",1,10.0,source)
	status = EFFECTS.current(c,"wither")
	status.set_physics_process(false)
	pulses = drive(c,status,60*3,func(frame:int) -> void:
		if frame == 30: EFFECTS.apply_effect(c,"wither",5,1.2,other))
	print("C pulses: ",pulses)
	var c_losses:Array = []
	for p:Array in pulses: c_losses.append(int(p[1]))
	check(pulses.size() == 3 and c_losses == [500,100,100],"V overlay pulses at 1 s; after it expires (1.7 s) I pulses at 2 s and 3 s")

	# --- D: real Wither Skeleton continuous contact now drains during contact ---
	var actor:Node2D = load("res://scenes/characters/我的世界/凋灵骷髅.tscn").instantiate()
	actor.Team = "A"
	actor.position = Vector2(400,300)
	arena.add_child(actor)
	actor.set_physics_process(false)
	actor.state_machine.set_physics_process(false)
	actor.set_process(false)
	var d:Node2D = dummy("VictimD",Vector2(435,300))
	await process_frame
	actor.health = actor.Max_health
	check(actor.Max_health == 700 and actor.health == 700,"Wither Skeleton health is 700 (2026-09-29)")
	var sword:float = 0.0
	var wither:float = 0.0
	var wither_pulses:int = 0
	var previous_hp:float = float(d.health)
	var previous_hits:int = 0
	for frame:int in range(60*6):
		await physics_frame
		actor.step_mob(DT)
		var loss:float = previous_hp-float(d.health)
		var new_hits:int = int(actor.hits_landed)-previous_hits
		var slash:float = 20.0*float(new_hits)
		if loss-slash > 0.5:
			wither += loss-slash
			wither_pulses += 1
		sword += minf(loss,slash)
		previous_hp = float(d.health)
		previous_hits = int(actor.hits_landed)
	var lvl:int = EFFECTS.level_of(d,"wither")
	print("D contact 6 s: hits=%d sword=%d wither=%d pulses=%d level=%d" % [actor.hits_landed,int(sword),int(wither),wither_pulses,lvl])
	check(int(actor.hits_landed) >= 9,"skeleton kept slashing through the 6 s contact")
	check(wither_pulses >= 5,"Wither pulses every second during continuous slashing (old reset: 0)")
	check(wither > 0.0 and lvl >= 9,"stacked levels drain while still in contact")
	actor.queue_free()
	for n:Node in [a,b,c,d,source,other]: n.queue_free()
	await process_frame
	print("WITHER_TICK_RESULT checks=%d failures=%d" % [checks,failures])
	arena.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
