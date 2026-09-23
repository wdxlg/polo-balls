extends SceneTree
## Dependency/scene smoke check. Run with godot --headless --script res://tests/test_wither.gd.
func _initialize() -> void:
    var names:Array[String] = ["wither", "skull", "rose", "status", "beacon"]
    var errors:int = 0
    for name:String in names:
        var path:String = "res://scripts/characters/我的世界/wither/%s.gd" % name
        var script:Script = load(path) as Script
        if script == null or not script.can_instantiate():
            push_error("WITHER SCRIPT FAILED: " + path)
            errors += 1
    for path:String in ["res://scenes/characters/我的世界/凋零.tscn", "res://scenes/creatures/我的世界/凋零信标.tscn"]:
        var scene:PackedScene = load(path) as PackedScene
        if scene == null or not scene.can_instantiate():
            push_error("WITHER SCENE FAILED: " + path)
            errors += 1
    if errors > 0:
        quit(1)
        return
    print("WITHER SMOKE: 7/7 resources loadable")
    call_deferred("_run_behaviors")

func _run_behaviors() -> void:
    var arena := Node2D.new()
    root.add_child(arena)
    current_scene = arena
    arena.process_mode = Node.PROCESS_MODE_DISABLED
    var wither:Node2D = load("res://scenes/characters/我的世界/凋零.tscn").instantiate()
    wither.Team = "WitherTeam"
    arena.add_child(wither)
    assert(wither.health == 500 and not wither.summoned)
    wither.take_damage(70.0)
    assert(wither.health == 500, "assembly must be immune to direct damage")
    wither.summon_time = 2.8
    assert(wither.get_ai_attack_threats(null).size() == 1, "summon explosion must declare its real radius")
    wither.summoned = true
    wither.health = 250
    wither.on_actual_health_damage_received(1.0,251.0)
    assert(wither.heart_dropped and is_instance_valid(wither.beacon), "first half-health crossing must create the heart")
    assert(wither.beacon.health == 180)
    var first:Node = wither.beacon
    wither.on_actual_health_damage_received(1.0,251.0)
    assert(wither.beacon == first, "heart must not be created twice")
    wither.apply_beacon_buff("haste")
    assert(wither._buff == "haste" and wither._buff_left == 6.0)
    print("WITHER BEHAVIOR: assembly immunity, threat, unique heart, beacon health and buff pass")
    arena.queue_free()
    quit(0)
