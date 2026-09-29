# 投射物类别交互协议

2026-09-26：修复类别已经登记、角色仍靠自己的名单或字段判定的问题。

## 唯一入口

`classes/projectile_interactions.gd` 负责类别/阶段、有效性、候选索引、运动、伤害载荷、来源/阵营、捕获能力、反射及格挡收尾。类别本身只读取 `combat_classification.gd`；不要在角色里再按资源目录、脚本名、特定作者分组或旧 ball 继承关系定义“投射物”。

- `is_projectile/live/supports`：分别表示类别、当前有效阶段和交互能力，不能互相混用。
- `candidates(tree)`：首次扫描、之后通过节点增删维护弱引用索引；每次查询重新判断阶段，不把落地石头永久缓存成弹体。
- `velocity_of/set_velocity/direction_of/speed_of`：统一运动操作。
- `source_of`：原生回调来源；`owner_of`：解析隔离返还/反射上下文后的实际归属。
- `team_of/hostile/bind_owner`：公共阵营/来源；捕获不偷友军。原生特殊弹体使用冻结来源上下文保留回调和攻击快照，上下文不能行动、碰撞、攻击或被选为目标。
- `damage_of/damage_kind_of`：单次转移载荷的数值与类型；不是从整个角色或 `damage_kinds` 摘要猜类型。已核实的旧火焰载荷在共享适配表显式声明；普通爆炸不因名字含火就自动变火焰。
- `capture_descriptor/reflect/retire/defense`：统一操作。权限在实际操作入口校验；离树对象可做描述查询，但不能实际捕获。

## 新对象接入一次即可，不修改角色名单

1. 在公共注册表登记实体及阶段；动态测试/外部对象可使用 `combat_classification` 元数据。新资源必须通过注册覆盖闸门。
2. 常规旧字段由共享兼容适配器读取，不再分散到角色。**特殊运动、所有权或载荷结构应实现下面的协议**，不能指望仅加类别标签便能猜出所有玩法。
3. 根据需要实现：
   - `get_projectile_velocity() -> Vector2`
   - `set_projectile_velocity(motion:Vector2)`
   - `get_projectile_source() -> Node`
   - `get_projectile_team() -> String`
   - `bind_projectile_owner(source:ball,team:String,target:ball)`
   - `get_projectile_damage() -> float`
   - `get_projectile_damage_kind() -> String`
   - `get_projectile_radius() -> float`
   - `projectile_supports(capability:String) -> bool`
   - `relaunch_projectile(point:Vector2,target:ball)`：重置碰撞句柄/出生位置等，保留原生玩法。
4. `projectile_capabilities` 元数据可显式关闭 capture/reflect/redirect 等能力；`projectile_damage_kind` 可显式声明转移载荷。原生返还保存这些协议元数据，不能丢失 fire 后退回普通伤害。
5. 缺少可写运动接口的对象不自动获得 reflect/redirect；不得通过角色私有脚本名单补洞。特殊弹道在自身协议或共享适配层实现一次。

## 公共接触入口

`ball._ready` 确保每棵 SceneTree 有一个 `scripts/projectile_interaction_driver.gd`，优先于普通物理更新工作。它使用当前速度扫掠，先截取地形/最近人物接触，再处理悦灵音符捕获、镜子/觉醒凋零反射、盾狗正面挡弹，避免 Area2D 弹体先结算并自毁。暂停、权限、磁铁收纳和羊毛控制状态均有门控。

它不预先抽取普通闪避概率，也不主动结算攻击伤害。原生弹体保留自己的碰撞、伤害及特殊轨迹；精确自定义接触应调用 `API.defense`，根据 dodge/reflect/block 结果决定跳过目标、保留弹体或结束，**不能反射后仍执行原生爆炸/销毁**。天陨主箭、改向后的落箭已接入。

预测扫掠使用当前速度和碰撞半径；复杂加速、曲线或特殊形状仍应在原生精确接触处接同一协议，不把这一预测层宣称为所有弹道的完美碰撞替代。

## 已迁移消费者

悦灵捕获/候选及原生返还；盾狗盾牌与铁丝网；磁铁吸排/收放；醉汉躲弹；末影人远程来源；镜子反射；凋零觉醒反射；羊毛识别/载荷；极速者威胁预测；寸头没事沙漠溜达猪登记/运动/阵营；剑客弹反收尾。

- 天陨落箭提供显式运动及重新发射钩子；被捕获/反射后可沿新方向飞行并保留落点范围伤害。正常未被改向时仍使用原来的重力下落。
- 天陨落箭钻地变为 visual；骷髅箭飞行/插墙/嵌入分别为 projectile/terrain/status；企鹅石头仍为飞行 projectile、落地 obstacle。
- 羊毛转移保留已声明的 fire 类型并通过分类伤害入口结算，不用普通伤害替代。
- 旧脚本专属回调、状态恢复和音效适配仍保留；这些不是类别白名单。`allay/extended_capture.gd` 的旧数组仅兼容历史检查工具，不再决定候选/捕获资格。
- 修正共享索引及 world 非 ball 朝向登记的延迟回调：传实例 ID，不将已释放对象继续作为 Node 参数。

## 验证与边界

见 `tests/CATEGORY_INTERACTIONS_20260926.md`。实际角色/原生弹体和全新无旧字段测试弹体均验证；没有完成真实双客户端对战、GPU 画面及全角色×全弹体穷举。不可把自动化断言数量当作完整游戏覆盖率。
