extends RichTextEffect

# 死档 UI 专用：复刻“重女文字”的逐字抽帧颤抖。
# 每个 glyph 独立做像素级位移与轻微旋转；时间量化到约 0.15 秒一拍，
# 对应重女原实现的 0.12~0.18 秒离散更新节奏。
var bbcode:String = "heavy_girl_jitter"

func _hash01(seed:float) -> float:
	return fposmod(sin(seed * 12.9898 + 78.233) * 43758.5453,1.0)

func _process_custom_fx(char_fx:CharFXTransform) -> bool:
	var step_seconds:float = maxf(float(char_fx.env.get("step",0.15)),0.05)
	var shake_strength:float = maxf(float(char_fx.env.get("strength",0.72)),0.0)
	var rotation_strength:float = maxf(float(char_fx.env.get("rotation",5.0)),0.0)
	# 使用全局单调时间，而不是 char_fx.elapsed_time：死档的逐字打字机会频繁更新文本，
	# 不能让每次 text 变化都把颤抖相位重置到第 0 拍。
	var global_seconds:float = float(Time.get_ticks_msec()) / 1000.0
	var step_index:int = int(floor(global_seconds / step_seconds))
	var glyph_index:int = char_fx.relative_index
	var seed:float = float(step_index * 131 + glyph_index * 977 + 17)

	# 和重女文字一致：不少拍保持原位，其余拍只落在约 -1/0/1 像素。
	if _hash01(seed + 1.0) >= 0.42:
		var offset_x:float = roundf(lerpf(-shake_strength,shake_strength,_hash01(seed + 2.0)))
		var offset_y:float = roundf(lerpf(-shake_strength,shake_strength,_hash01(seed + 3.0)))
		char_fx.offset += Vector2(offset_x,offset_y)

	# 旋转独立更新，强度与重女文字默认 ±5° 对齐。
	if _hash01(seed + 4.0) >= 0.12:
		var angle_degrees:float = lerpf(-rotation_strength,rotation_strength,_hash01(seed + 5.0))
		angle_degrees = snappedf(angle_degrees,0.75)
		char_fx.transform = char_fx.transform.rotated_local(deg_to_rad(angle_degrees))
	return true
