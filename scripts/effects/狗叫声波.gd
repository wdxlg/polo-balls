extends Node2D

# 狗叫声波视觉管理器：同一只狗的多个白色描边圆可同时扩散；所有圆由一个 Node2D 统一绘制，减少节点数量。
var _waves:Array[Dictionary] = []
var _idle_elapsed:float = 0.0


# 加入一枚新的白色声波；前一枚未消失时不会删除，所以攻击期间会形成连续向外扩散的多圈波纹。
func emit_wave(world_origin:Vector2,radius:float,small_variant:bool) -> void:
    var local_origin:Vector2 = to_local(world_origin)
    _waves.append({
        "origin":local_origin,
        "radius":maxf(radius,8.0),
        "elapsed":0.0,
        "lifetime":0.72 if small_variant else 0.92,
        "small":small_variant,
    }) # 每个声波独立记录寿命，因此多个白圈可以真正重叠存在。
    _idle_elapsed = 0.0
    set_process(true)
    queue_redraw()


# 每帧推进所有仍存活的声波，并在最后一个白圈消失后自动释放管理器。
func _process(delta:float) -> void:
    for index:int in range(_waves.size() - 1,-1,-1):
        var wave:Dictionary = _waves[index]
        wave["elapsed"] = float(wave.get("elapsed",0.0)) + delta
        if float(wave["elapsed"]) >= float(wave.get("lifetime",0.8)):
            _waves.remove_at(index)
        else:
            _waves[index] = wave

    if _waves.is_empty():
        _idle_elapsed += delta
        if _idle_elapsed >= 0.05:
            queue_free()
            return
    else:
        _idle_elapsed = 0.0

    queue_redraw()


# 一次绘制全部白色描边圆；只有单层白线和透明渐隐，不增加发光层、内圈或彩色装饰。
func _draw() -> void:
    for wave:Dictionary in _waves:
        var lifetime:float = maxf(float(wave.get("lifetime",0.8)),0.05)
        var t:float = clampf(float(wave.get("elapsed",0.0)) / lifetime,0.0,1.0)
        var eased:float = 1.0 - pow(1.0 - t,2.1)
        var radius:float = float(wave.get("radius",100.0))
        var current_radius:float = lerpf(radius * 0.06,radius,eased)
        var alpha:float = 0.92 * pow(1.0 - t,1.35)
        var small_variant:bool = bool(wave.get("small",false))
        var line_width:float = 1.15 if small_variant else 1.75
        var segments:int = 22 if small_variant else 30
        draw_arc(
            wave.get("origin",Vector2.ZERO) as Vector2,
            current_radius,
            0.0,
            TAU,
            segments,
            Color(1.0,1.0,1.0,alpha),
            line_width,
            true
        ) # 白圈只负责视觉；真实伤害继续由狗叫机制的 DamageArea 结算。
