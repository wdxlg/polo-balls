# 兼容清理文件：上一版补丁误把全局 ball 类放到了 res://scripts/ball.gd。
# 项目真正的 ball 类位于 res://classes/ball.gd。
# 本文件故意不声明 class_name，避免与全局 ball 类型重复注册。
# 确认项目正常后，可以直接删除 res://scripts/ball.gd。
extends RefCounted
