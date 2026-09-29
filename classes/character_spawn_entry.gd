@tool
class_name CharacterSpawnEntry
extends Resource
## 在生成图层的角色表中新增资源，将人物 .tscn 拖到 Character。权重只相对于同表其它条目。
@export var character:PackedScene
@export_range(0.0,10000.0,0.1,"or_greater") var weight:float = 1.0
@export var enabled:bool = true
