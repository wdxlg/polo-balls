# 虚无盔甲架与独立石头：接触规则

## 虚无盔甲架

- 仍可被角色 AI 索敌，普通近战接触仍成立；保持 75% 不透明度、隐藏血条和完全伤害免疫。
- **投射物穿透不是伤害为零**：不能触发命中、格挡反馈、爆炸、落地、反射、插入、消耗或命中计数；同一帧仍应继续检测后方的普通目标/地形。
- `scripts/projectile_contact.gd` 提供被动的 `ignores(target)` 判定，支持角色及其子碰撞体。不要用全局 `is_combat_targetable` 或 `U.enemy` 排除盔甲架，否则会破坏正常索敌/近战。
- 既有自定义投射物继续使用 `try_full_projectile_dodge` 的穿透契约。虚无盔甲架始终返回 true，但不会触发传送、消耗闪避次数或播放特效。
- 实体弹由盔甲架为已存在及新生成的 `PhysicsBody2D` 注册双向碰撞例外；节点离场时清理，重新入场及弹体复用后恢复（不能假设 `_ready` 会再执行）。新增实体弹必须纳入 `is_projectile` 分类。
- 有落地状态的企鹅石头在落地后调用 `refresh_body_exceptions`，恢复普通实体碰撞；它与手动放置的石头障碍物不是同一种对象。
- 追踪弹不能把位置钳在虚无目标中心。接触无效时继续飞行，不能因距离为零提前爆炸。

## 手动放置的石头

当前石头为独立 `StaticBody2D`，不继承 ball，不含队伍、血量、伤害、状态机、hitbox 或 hurtbox，不参加索敌、随机选人、计分或胜负统计。

保留原贴图与世界碰撞尺寸（23 × 25.5）、放置预览、右键删除、布阵记录、清场/重打及原场景路径。使用地形层 1、角色碰撞掩码 2，`PlaceableObstacle` 标识编辑对象，`BattleTransient` 负责清场生命周期；联机仅复制位置、旋转、缩放。

天堂弓将其当作真实地形：穿越消耗一次障碍穿透并生成裂隙，而不是角色命中。已有地图外箭矢显示规则不变。

## 回归入口

- `tests/test_void_projectile_contacts.gd`：实体弹、射线、距离/扫掠、追踪弹、反弹弹、命中反馈与地形边界。
- `tests/test_void_armor_stand.gd`：原有索敌、近战、透明度与完全伤害免疫。
- `tests/test_stone_obstacle.gd`：真实 World 放置、预览、删除、随机池、训练模式、重打及铁砧碰撞。
- `tests/test_stone_terrain_replication.gd`：两个仅绑定回环地址的真实 ENet peer，验证原生出生、变换同步与删除。
- `tests/test_heavenfall_contacts.gd`、`tests/test_heavenfall_wall_targeting.gd`、`tests/test_heavenfall_obstacle_visibility.gd`：天堂弓兼容性。可见性测试需要真实渲染窗口验证像素，不能只跑 headless。
