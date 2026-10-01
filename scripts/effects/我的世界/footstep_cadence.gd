extends RefCounted
## 脚步节奏（我的世界角色自身脚步、苔藓/蛛网地形脚步共用）。
## 规则：以角色"当前实际移速"为基准，按走过的距离计步——每走完一个步幅就响一步。
##   步幅 = 基础速度 × 基础间隔。基础速度取角色默认 Speed（不含临时加速/减速）。
##   按基础速度移动时，间隔 = 基础间隔（保持原有手感）；
##   移动越快，走完一步越快，脚步越密；越慢越稀；停下就不响。
##   等价公式：间隔 = 基础间隔 × 基础速度 ÷ 当前移速。
## 下一步不等上一声播完：高速时间隔可以短于脚步音频本身，声音允许重叠。
const MIN_INTERVAL:float = 0.07 # 极高速（冲刺、被拖拽）时的最短间隔，避免连成一片噪音
const STILL_RESET:float = 0.25 # 停下超过这么久，下次起步立刻先响一步
var _progress:float = 1.0 # 走完一步 = 1.0；初始为 1.0，起步即响
var _since_step:float = INF
var _still:float = 0.0

## 角色的基础速度：默认属性里的 Speed（World 每帧把临时加/减速还原到它）。
static func base_speed(unit:Object) -> float:
	if unit == null: return 100.0
	var props:Variant = unit.get("default_properties")
	if props is Dictionary and props.has("Speed"): return maxf(float(props["Speed"]),1.0)
	var raw:Variant = unit.get("Speed")
	return maxf(float(raw),1.0) if raw != null else 100.0

## moved = 这段时间的真实位移（像素；没在走路时传 0）。返回 true 表示该响一步。
func tick(moved:float,delta:float,speed_base:float,interval_base:float) -> bool:
	return tick_stride(moved,delta,speed_base*interval_base)

## 直接给定步幅（像素）的版本。
func tick_stride(moved:float,delta:float,stride:float) -> bool:
	_since_step += maxf(delta,0.0)
	if moved <= 0.0:
		_still += maxf(delta,0.0)
		if _still >= STILL_RESET: _progress = 1.0
		return false
	_still = 0.0
	_progress += moved/maxf(stride,1.0)
	if _progress < 1.0 or _since_step < MIN_INTERVAL: return false
	_progress = minf(_progress-1.0,0.99) # 余下的进度带到下一步，但不会攒成连响
	_since_step = 0.0
	return true

## 立即允许下一次移动响一步（测试或特殊起步用）。
func ready_now() -> void:
	_progress = 1.0
	_since_step = INF
