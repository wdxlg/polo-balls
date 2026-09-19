extends RefCounted
## V431 性能：Object.get_property_list() 会为每个属性构造一个 Dictionary（ball 有 300+ 属性）。
## 100 人混战时磁铁磁场、威胁分析器和各类 _has_property() 每帧要调用它数百次，
## 是脚本侧最大的单一热点（混合 100 人基准里 655 次/帧）。
##
## 项目里没有任何 _get_property_list() / _get() / _set() 动态属性覆写，因此
## “同一原生类 + 同一脚本”的属性名集合是固定的：按脚本缓存一次即可，判定结果与逐次
## 调用 get_property_list() 完全一致。
##
## 注意：metadata/* 与 instance_shader_parameters/* 是逐实例的，不在本缓存的保证范围内；
## 查询元数据请继续用 has_meta()。

static var _names_by_key:Dictionary = {}
# V432 性能：按 Script 实例 id（int）建二级缓存，热路径不再每次 get_class()+字符串拼接。
static var _names_by_script_id:Dictionary = {}


## 返回该对象全部属性名的只读集合 {name:true}。同脚本的对象共享同一份 Dictionary，调用方不得修改。
static func names(object:Object) -> Dictionary:
	if object == null or not is_instance_valid(object):
		return {}
	var script_value:Variant = object.get_script()
	if script_value is Script:
		var script_id:int = (script_value as Script).get_instance_id()
		var fast:Variant = _names_by_script_id.get(script_id)
		if fast is Dictionary:
			return fast
	var key:String = _cache_key(object)
	var cached:Variant = _names_by_key.get(key)
	if cached is Dictionary:
		if script_value is Script:
			_names_by_script_id[(script_value as Script).get_instance_id()] = cached
		return cached
	var result:Dictionary = {}
	for info:Dictionary in object.get_property_list():
		result[str(info.get("name",""))] = true
	result.make_read_only()
	_names_by_key[key] = result
	if script_value is Script:
		_names_by_script_id[(script_value as Script).get_instance_id()] = result
	return result


static func has_property(object:Object,property_name:String) -> bool:
	if object == null or not is_instance_valid(object):
		return false
	return names(object).has(property_name)


## 测试/热重载用：清空缓存。
static func clear_cache() -> void:
	_names_by_key.clear()
	_names_by_script_id.clear()


static func _cache_key(object:Object) -> String:
	var script_value:Variant = object.get_script()
	var script_id:int = (script_value as Script).get_instance_id() if script_value is Script else 0
	return object.get_class() + ":" + str(script_id)
