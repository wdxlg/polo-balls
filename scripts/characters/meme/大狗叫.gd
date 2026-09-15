extends ball

# 大狗叫（Dog barking）：只有真实碰撞才播放短叫并增加蓄力进度，累计足够多次后进入持续犬吠并连续发出伤害声波。
const VISUAL_IDLE:Texture2D = preload("res://Images/characters/meme/大狗叫/大狗.png")
const VISUAL_MOVE:Texture2D = preload("res://Images/characters/meme/大狗叫/大狗.png")
const VISUAL_BARK:Texture2D = preload("res://Images/characters/meme/大狗叫/大狗叫.png")

@export_category("大狗叫 - 视觉")
@export_range(60.0,420.0,5.0) var visual_max_local_size:float = 155.0

@onready var bark_mechanic:Node2D = $BarkMechanic
@onready var puppy:ball = $小狗叫 as ball

var _last_visual:Texture2D = null


# 初始化大狗：关闭普通攻击/技能状态机出手，所有伤害由狗叫机制的真实 DamageArea 负责。
func _ready() -> void:
    Has_Collision_Damage = false
    Can_Attack = false
    Can_Skill = false
    Health_Restore = 0
    super._ready()
    image_color = Color.WHITE
    image_color_mix = 0.0
    set_image_color()
    if bark_mechanic != null and bark_mechanic.has_method("setup"):
        bark_mechanic.call("setup",self,self,Team,false)
    _set_dog_visual(VISUAL_IDLE)


# 角色选择预览直接使用用户提供的新大狗图片。
func get_preview_texture() -> Texture2D:
    return VISUAL_IDLE


# 大狗没有普通攻击，避免状态机进入空 Attack 动作。
func Attack() -> void:
    Attacking = false


# 狗叫是自动机制而不是手动技能键，因此不进入 Skill 状态。
func Skill() -> void:
    Using_Skill = false


# 继续使用 ball 通用移动/控制；根据移动与持续犬吠状态切换现有狗图片。
func tick_physics(state:State,delta:float) -> void:
    super.tick_physics(state,delta)

    # ball 根身体的真实碰撞也会推进狗叫进度；ContactArea 继续作为补充，两路共用碰撞冷却避免重复计数。
    if bark_mechanic != null and bark_mechanic.has_method("notify_collision"):
        for i:int in range(get_slide_collision_count()):
            var collision:KinematicCollision2D = get_slide_collision(i)
            if collision == null:
                continue
            var collider:Object = collision.get_collider()
            if collider != null:
                bark_mechanic.call("notify_collision",collider)

    var howling:bool = bark_mechanic != null and bark_mechanic.has_method("is_howling") and bool(bark_mechanic.call("is_howling"))
    if howling:
        _set_dog_visual(VISUAL_BARK)
    elif direction.length_squared() > 0.0025 or velocity.length_squared() > 16.0:
        _set_dog_visual(VISUAL_MOVE)
    else:
        _set_dog_visual(VISUAL_IDLE)


# 把大狗视觉限制到固定本地尺寸；ball.tscn 根缩放会进一步映射到世界尺寸。
func _set_dog_visual(texture:Texture2D) -> void:
    if not image is Sprite2D or texture == null or texture == _last_visual:
        return
    _last_visual = texture
    var sprite:Sprite2D = image as Sprite2D
    sprite.texture = texture
    sprite.offset = Vector2.ZERO
    sprite.visible = true
    var size:Vector2 = texture.get_size()
    var longest:float = maxf(maxf(size.x,size.y),1.0)
    var fit:float = maxf(visual_max_local_size,1.0) / longest
    sprite.scale = Vector2.ONE * fit


# AI 威胁调试不需要角色半径兜底：大狗和小狗的狗叫机制都作为 AI_Hazard 挂了真实圆形 DamageArea。
func get_ai_attack_threats(_receiver:ball) -> Array:
    return []
