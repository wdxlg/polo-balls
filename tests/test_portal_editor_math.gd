extends SceneTree
# PortalEditMath 回归：画布手柄的位置 / 命中 / 滑动 / 缩放 / 最近边 / 自动对岸。
var failures:int = 0
var checks:int = 0
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func run() -> void:
	var math = load("res://addons/portal_map_editor/portal_edit_math.gd")
	var rect:Rect2 = Rect2(0,0,128,96)
	var inset:float = 7.0
	var h:Dictionary = math.handles(rect,1,0,96,inset)
	check(h["start"] == Vector2(121,0) and h["mid"] == Vector2(121,48) and h["end"] == Vector2(121,96),"handles sit just inside the edge")
	check(math.hit_test(rect,1,0,96,inset,h["mid"],10.0) == "mid","middle handle is grabbable")
	check(math.hit_test(rect,1,0,96,inset,h["start"],10.0) == "start","end handle is grabbable")
	check(math.hit_test(rect,1,0,96,inset,Vector2(60,48),10.0) == "","clicks away from handles do nothing")
	var slide:Dictionary = math.slide(rect,1,32,64,48.0,16.0,16.0)
	check(absf(float(slide["offset"]) - 32.0) < 0.01 and absf(float(slide["length"]) - 32.0) < 0.01,"slide keeps the length and snaps to blocks")
	check(bool(slide["whole_edge"]) == false,"a partial span is not the whole edge")
	check(bool(math.slide(rect,1,0,96,48.0,16.0,16.0)["whole_edge"]),"a span covering the edge becomes the whole edge")
	check(absf(float(math.slide(rect,1,32,64,-40.0,16.0,16.0)["offset"])) < 0.01,"slide clamps inside the island")
	var grow:Dictionary = math.resize(rect,1,32,64,"end",80.0,16.0,16.0)
	check(absf(float(grow["offset"]) - 32.0) < 0.01 and absf(float(grow["length"]) - 48.0) < 0.01,"dragging the end resizes the span")
	var shrink:Dictionary = math.resize(rect,1,32,64,"start",58.0,16.0,16.0)
	check(absf(float(shrink["offset"]) - 48.0) < 0.01 and absf(float(shrink["length"]) - 16.0) < 0.01,"dragging the start keeps the minimum length")
	var moved:Rect2 = Rect2(120,2203,128,96)
	var odd:Dictionary = math.slide(moved,2,136,184,176.0,16.0,16.0)
	check(fposmod(float(odd["offset"]),16.0) == 0.0 and float(odd["length"]) == 48.0,"odd tile count slides without half-tile offset on translated island")
	var moved_resize:Dictionary = math.resize(moved,1,2219,2251,"end",2274.0,16.0,16.0)
	check(fposmod(float(moved_resize["offset"]),16.0) == 0.0 and fposmod(float(moved_resize["length"]),16.0) == 0.0,"resize snaps relative to island origin, not world origin")
	var near:Dictionary = math.nearest_edge({"IslandA": rect},Vector2(140,60),24.0)
	check(not near.is_empty() and str(near["island"]) == "IslandA" and int(near["side"]) == 1,"nearest edge found by distance")
	check(math.nearest_edge({"IslandA": rect},Vector2(600,600),24.0).is_empty(),"far pointer has no edge")
	var rects:Dictionary = {"IslandA": rect,"IslandB": Rect2(208,0,128,96)}
	var target:Dictionary = math.auto_target(rects,"IslandA",1,0,96,32.0)
	check(not target.is_empty() and str(target["island"]) == "IslandB" and int(target["side"]) == 0,"new link auto-picks the facing edge (right -> left)")
	var rects2:Dictionary = {"IslandA": rect,"IslandC": Rect2(32,192,96,64)}
	var target2:Dictionary = math.auto_target(rects2,"IslandA",3,32,80,32.0)
	check(not target2.is_empty() and str(target2["island"]) == "IslandC" and int(target2["side"]) == 2,"new link auto-picks bottom -> top")
	print("EDITOR_MATH checks=",checks," failures=",failures)
	quit(1 if failures > 0 else 0)

