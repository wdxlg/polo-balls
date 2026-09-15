extends "res://scripts/training/live_sans_final.gd"
# 短 GPU 画面检查；完整 46.148 秒物理回归由 live_sans_final 独立执行。
func _process(delta:float) -> bool:
	var result:bool = super._process(delta)
	if started and elapsed > 19.0:
		finish(0)
	return result
