extends SceneTree
var checks:int = 0
var failures:int = 0
var C:GDScript

func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func intervals(speed:float,speed_base:float,interval_base:float,seconds:float = 6.0) -> Array[float]:
	var dt:float = 1.0/120.0
	var cadence:RefCounted = C.new()
	var out:Array[float] = []
	var t:float = 0.0
	var last:float = -1.0
	while t < seconds:
		t += dt
		if cadence.tick(speed*dt,dt,speed_base,interval_base):
			if last >= 0.0: out.append(t-last)
			last = t
	return out

func avg(values:Array[float]) -> float:
	var total:float = 0.0
	for v:float in values: total += v
	return total/maxf(float(values.size()),1.0)

func _init() -> void:
	C = load("res://scripts/effects/我的世界/footstep_cadence.gd")
	var at_base:float = avg(intervals(100.0,100.0,0.6))
	check(absf(at_base-0.6) < 0.02,"base speed keeps the base interval (%.3f)" % at_base)
	var fast:float = avg(intervals(200.0,100.0,0.6))
	check(absf(fast-0.3) < 0.02,"double speed halves the interval (%.3f)" % fast)
	var slow:float = avg(intervals(50.0,100.0,0.6))
	check(absf(slow-1.2) < 0.03,"half speed doubles the interval (%.3f)" % slow)
	var sprint:float = avg(intervals(400.0,100.0,0.6))
	check(absf(sprint-0.15) < 0.02,"4x speed: 0.15s interval, shorter than a 0.35s clip, so steps overlap (%.3f)" % sprint)
	var capped:Array[float] = intervals(100000.0,100.0,0.6)
	check(not capped.is_empty() and capped.min() >= C.MIN_INTERVAL-0.0001,"extreme speed is capped at MIN_INTERVAL")
	var c:RefCounted = C.new()
	var any_step:bool = false
	for i:int in range(240): any_step = any_step or c.tick(0.0,1.0/120.0,100.0,0.6)
	check(not any_step,"standing still never steps")
	check(c.tick(1.0,1.0/120.0,100.0,0.6),"first movement steps immediately")
	check(not c.tick(1.0,1.0/120.0,100.0,0.6),"a tiny further move does not step again")
	c.tick(0.0,0.3,100.0,0.6)
	check(c.tick(1.0,1.0/120.0,100.0,0.6),"after stopping, walking again steps immediately")
	var probe:GDScript = GDScript.new()
	probe.source_code = "extends RefCounted\nvar Speed:float = 200.0\nvar default_properties:Dictionary = {\"Speed\":80.0}\n"
	probe.reload()
	check(is_equal_approx(C.base_speed(probe.new()),80.0),"base speed ignores temporary speed buffs")
	var boss:RefCounted = probe.new()
	boss.set_meta("training_boss_base_speed",8.0)
	check(is_equal_approx(C.base_speed(boss),8.0),"boss speed multiplier is not part of the base speed")
	var boss_fast:float = avg(intervals(80.0,C.base_speed(boss),0.3))
	check(absf(boss_fast-C.MIN_INTERVAL) < 0.02,"10x boss walks with 10x denser steps, capped at MIN_INTERVAL (%.3f)" % boss_fast)
	check(C.base_speed(null)==100.0,"missing source has a safe base-speed default")
	var removed:Node = Node.new()
	removed.free()
	check(C.base_speed(removed)==100.0,"freed source cannot cause stale-object property access")
	print("FOOTSTEP_CADENCE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
