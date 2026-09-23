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
    # Each soul-sand block is one equally sized square in a contiguous T.
    var bottom:Rect2 = wither.summon_sand_rect(0)
    var upper:Rect2 = wither.summon_sand_rect(1)
    var left:Rect2 = wither.summon_sand_rect(2)
    var right:Rect2 = wither.summon_sand_rect(3)
    for block:Rect2 in [bottom,upper,left,right]:
        assert(block.size == Vector2(30,30),"soul-sand blocks must use identical square tiles")
    assert(bottom.position.y == upper.end.y and left.end.x == upper.position.x and right.position.x == upper.end.x,"T-shaped construction blocks must touch without stretching")
    for i:int in range(3):
        var head:Rect2 = wither.summon_head_rect(i)
        assert(head.size == Vector2(26,26) and is_equal_approx(head.get_center().x,float(i-1)*30.0),"three skull blocks align with the same-size T-grid")
    var skull:Node2D = load("res://scripts/characters/我的世界/wither/skull.gd").new()
    skull.configure(wither,Vector2.RIGHT)
    assert(skull.SKULL_DIAMETER == 10.0 and skull.get_ai_hazard_info()["radius"] == 5.0,"small skull sprite and threat agree")
    for direction:Vector2 in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
        skull.configure(wither,direction)
        assert(skull.rotation == 0.0 and skull.heading == direction,"flying skull icon stays upright while collision/trajectory follows the real heading")
    skull.free()
    var rose:Node2D = load("res://scripts/characters/我的世界/wither/rose.gd").new()
    rose.configure(wither)
    rose.age = 0.6
    assert(rose.ROSE_DIAMETER == 20.0 and rose.get_ai_hazard_info()["radius"] == 11.0,"small rose and contact radius agree")
    assert(not rose.withered and rose.get_ai_hazard_info()["kind"] == "ordinary_rose" and rose.NORMAL_TEXTURE.resource_path.ends_with("poppy.png"),"spawned flower is the original Minecraft poppy, not a Wither rose")
    rose.become_wither()
    assert(rose.withered and rose.get_ai_hazard_info()["kind"] == "wither_rose","skull blast can convert a normal flower")
    rose.free()
    wither._show_explosion(Vector2.ZERO,64.0)
    var local_effect:Node = arena.get_node("MCLocalEffects").get_child(0)
    assert(local_effect.is_in_group("MCExplosion") and local_effect.radius == 64.0 and not local_effect.play_audio,"use shared Minecraft explosion visual without duplicate sound")
    wither._sync_event("awake",Vector2.ZERO)
    var awake_visual:Node = arena.get_node("MCLocalEffects").get_child(1)
    assert(awake_visual.is_in_group("MCExplosion") and awake_visual.radius == 110.0 and not awake_visual.play_audio,"networked awakening uses the shared effect at the original radius")
    wither._sync_event("skull_blast",Vector2.ZERO)
    var skull_visual:Node = arena.get_node("MCLocalEffects").get_child(2)
    assert(skull_visual.is_in_group("MCExplosion") and skull_visual.radius == 64.0 and not skull_visual.play_audio,"networked skull blast uses exactly the same shared effect")
    wither.summoned = true
    var rig:Node3D = wither._bedrock_model
    rig.animate(0.0,Vector2.DOWN,true,1.0,false,[Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT],1.0)
    assert(rig.bones["head1"].rotation.y > 0.4 and rig.bones["head3"].rotation.y < -0.4, "three heads must track distinct aim directions, not move in lockstep")
    assert(absf(absf(rig.rotation.y)-PI) < 0.01,"down-facing body shows its back")
    wither.set_character_visual_flip_h(true)
    assert(not wither.is_character_visual_flipped_h(),"3D yaw must not be reversed again by a 2D sprite mirror")
    var mouths:Array[Vector2] = []
    for i:int in range(3): mouths.append(wither.head_muzzle_world_position(i))
    assert(mouths[0].distance_to(mouths[1]) > 3.0 and mouths[0].distance_to(mouths[2]) > 3.0,"projected head mouths must be separated in the arena")
    rig.animate(0.0,Vector2.RIGHT,true,1.0,false,[Vector2.RIGHT,Vector2.RIGHT,Vector2.RIGHT],1.0)
    assert(absf(rig.rotation.y-PI*0.5) < 0.01,"body turns right in world-space, not merely changing eye angle")
    rig.animate(0.0,Vector2.UP,true,1.0,false,[Vector2.UP,Vector2.UP,Vector2.UP],1.0)
    assert(absf(rig.rotation.y) < 0.01,"body shows its original white-eyed front when moving up")
    rig.animate(0.0,Vector2.DOWN,true,1.0,false,[Vector2.DOWN,Vector2.DOWN,Vector2.DOWN],1.0)
    mouths.clear()
    for i:int in range(3): mouths.append(wither.head_muzzle_world_position(i))
    var target_point:Vector2 = wither.global_position+Vector2(210,70)
    for i:int in range(3):
        wither._fire_skull(target_point)
        var shots:Array[Node] = get_nodes_in_group("AI_Hazard")
        var shot:Node2D = shots.back() as Node2D
        assert(shot.global_position.distance_to(mouths[[0,2,1][i]]) < 0.5,"each skull must leave the live corresponding head mouth")
        assert(shot.heading.dot((target_point-mouths[[0,2,1][i]]).normalized()) > 0.999,"skull trajectory must be recomputed from its real head origin")
    assert(wither._next_shoot_head == 0,"center-left-right muzzle sequence must wrap")
    wither.health = 250
    wither.on_actual_health_damage_received(1.0,251.0)
    assert(wither.heart_dropped and is_instance_valid(wither.beacon), "first half-health crossing must create the heart")
    assert(wither.beacon.health == 180)
    var first:Node = wither.beacon
    wither.on_actual_health_damage_received(1.0,251.0)
    assert(wither.beacon == first, "heart must not be created twice")
    wither.apply_beacon_buff("haste")
    assert(wither._buff == "haste" and wither._buff_left == 6.0)
    print("WITHER BEHAVIOR: correct front/back yaw, upright skull, poppy-to-Wither-rose lifecycle, projected muzzles and shared effects pass")
    arena.queue_free()
    quit(0)
