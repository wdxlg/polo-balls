extends SceneTree
## Dependency/scene smoke check. Run with godot --headless --script res://tests/test_wither.gd.
func _initialize() -> void:
    var names:Array[String] = ["wither", "skull", "rose", "status", "beacon", "audio", "bedrock_rig"]
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
    for path:String in ["wither_front.png", "wither_assembling.png", "wither_skull.png", "beacon_front.png", "beacon_beam.png", "soul_sand.png", "wither_rose.png", "nether_star.png", "effect_0.png", "flash.png"]:
        var texture:Texture2D = load("res://Images/characters/我的世界/wither/" + path) as Texture2D
        if texture == null or texture.get_width() == 0:
            push_error("WITHER OFFICIAL TEXTURE FAILED: " + path)
            errors += 1
    for path:String in ["wither_boss.geo.json", "wither_boss.animation.json", "wither_boss.animation_controllers.json", "wither.png", "wither_invulnerable.png", "wither_armor_blue.png"]:
        assert(FileAccess.file_exists("res://Images/characters/我的世界/wither/bedrock/"+path), "missing official Bedrock Wither: "+path)
    if errors > 0:
        quit(1)
        return
    print("WITHER SMOKE: 9/9 scripts and scenes loadable")
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
    assert(wither._bedrock_viewport != null and wither.image.texture == wither._bedrock_viewport.get_texture(), "body must be a live 3D ViewportTexture, not a baked sprite")
    assert(wither._bedrock_model.bones.size() == 6, "real Mojang model has six independently movable bones")
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
