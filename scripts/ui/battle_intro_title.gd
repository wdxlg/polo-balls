extends CanvasLayer
## 开战大标题：开战钟声响起时，屏幕中上方砸出我的世界风格的「A VS B」立体字，停一会儿后上浮淡出。
## 玩家画面用当前语言；正在录制时，中文/英文两条录像各自的抓帧视口里同时放一份对应语言的（CanvasLayer 不会被共享 World2D 的录像拍到）。
## 不注册 class_name，用 load() 取脚本：BattleIntroTitle.present(host, {"zh":[行], "en":[行]}, locale)

const SELF_PATH:String = "res://scripts/ui/battle_intro_title.gd"
const TITLE_SCRIPT:String = "res://scripts/ui/mc_title_text.gd"
const GROUP:StringName = &"BattleIntroTitle"
const IN_SECONDS:float = 0.28
const HOLD_UNTIL:float = 1.85
const OUT_SECONDS:float = 0.4
## 录像抓帧视口：locale -> SubViewport（录制器建视口时登记；视口释放后自动失效）。
static var _captures:Dictionary = {}

var title:Control
## 按游戏帧累计（离线录制按模拟时间走帧；首帧建字的卡顿不吃掉砸入动画）。
var age:float = 0.0
var lines:Array = []

static func register_capture(viewport:Viewport, locale:String) -> void:
	_captures[locale] = viewport

static func present(host:Node, lines_by_locale:Dictionary, locale:String) -> Array:
	var tree:SceneTree = host.get_tree() if host != null else null
	if tree == null or lines_by_locale.is_empty(): return []
	for old:Node in tree.get_nodes_in_group(GROUP): old.queue_free()
	var shown:Array = []
	var targets:Array = [[tree.root,locale]]
	for capture_locale:String in _captures:
		var viewport:Viewport = _captures[capture_locale] as Viewport if is_instance_valid(_captures[capture_locale]) else null
		if viewport != null and viewport.is_inside_tree(): targets.append([viewport,capture_locale])
	for target:Array in targets:
		var picked:Array = lines_by_locale.get(target[1],lines_by_locale.get(locale,[]))
		if picked.is_empty(): continue
		var layer = (load(SELF_PATH) as GDScript).new()
		layer.lines = picked
		(target[0] as Node).add_child(layer)
		shown.append(layer)
	return shown

func _init() -> void:
	name = "BattleIntroTitle"
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)

func _ready() -> void:
	title = (load(TITLE_SCRIPT) as GDScript).new()
	title.setup(lines)
	add_child(title)
	_animate()

func _process(delta:float) -> void:
	age += minf(delta,1.0 / 30.0)
	_animate()

func elapsed() -> float:
	return age

func _animate() -> void:
	if not is_instance_valid(title): return
	var t:float = elapsed()
	if t >= HOLD_UNTIL + OUT_SECONDS:
		queue_free()
		return
	var screen:Vector2 = get_viewport().get_visible_rect().size
	title.size = screen * Vector2(0.9,0.34)
	title.pivot_offset = title.size * 0.5
	var y:float = screen.y * 0.36
	var scale_amount:float = 1.0
	var alpha:float = 1.0
	if t < IN_SECONDS:
		var p:float = t / IN_SECONDS
		# 从大往下砸，落地时略微回弹。
		scale_amount = lerpf(1.9,1.0,1.0 - pow(1.0 - p,3.0)) + sin(p * PI) * 0.06
		alpha = clampf(p * 2.5,0.0,1.0)
	elif t > HOLD_UNTIL:
		var q:float = (t - HOLD_UNTIL) / OUT_SECONDS
		y -= screen.y * 0.05 * q * q
		scale_amount = lerpf(1.0,0.92,q)
		alpha = 1.0 - q
	title.position = Vector2((screen.x - title.size.x) * 0.5,y - title.size.y * 0.5)
	title.scale = Vector2.ONE * scale_amount
	title.modulate.a = alpha

