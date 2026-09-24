extends ball
## Test-only ball with thirteen distinct actions and release hooks.

var called:Array[int] = []
var released:Array[int] = []
var cancelled:Array[int] = []

func _ready() -> void:
	Can_Attack = false
	Can_Skill = false
	Has_Collision_Damage = false
	super._ready()

func controlled_attack_action() -> void: called.append(0)
func controlled_skill_action() -> void: called.append(1)
func controlled_middle_action() -> void: called.append(2)

func player_control_extra_actions() -> Array[StringName]:
	return [&"extra_1",&"extra_2",&"extra_3",&"extra_4",&"extra_5",&"extra_6",&"extra_7",&"extra_8",&"extra_9",&"extra_0"]

func extra_1() -> void: called.append(3)
func extra_2() -> void: called.append(4)
func extra_3() -> void: called.append(5)
func extra_4() -> void: called.append(6)
func extra_5() -> void: called.append(7)
func extra_6() -> void: called.append(8)
func extra_7() -> void: called.append(9)
func extra_8() -> void: called.append(10)
func extra_9() -> void: called.append(11)
func extra_0() -> void: called.append(12)

func player_control_action_released(index:int) -> void:
	released.append(index)

func player_control_action_cancelled(index:int) -> void:
	cancelled.append(index)
