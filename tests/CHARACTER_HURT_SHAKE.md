# 溺尸雷击平衡与通用受伤抖动

日期：2026-09-22。

## 行为

- 溺尸周期落雷倍率 2.0 → 1.4，命中追加雷倍率 1.0 → 0.7。默认攻击力 34、无减伤目标，实际向上取整伤害分别由 68 → 48、34 → 24。
- 三叉戟直击 0.5、电网 0.7、伤害半径、警告时间、攻击间隔和眩晕时长不变。
- 所有 Ball / Creature 通过通用实际扣血反馈获得短促抖动。治疗、免伤、护盾完全吸收、投射物不触发角色受伤抖动。
- 强度按实际损失 HP 增长，而非攻击面板：`1.8 + 16.2 * sqrt(d / (d + 60))` 世界单位；最大 18（本次为上一版的 2.4 倍、初版的 6 倍）。时长约 0.16–0.28 秒，1.5 次幂衰减，避免强反馈过快消失。连续伤害复用同一个组件，合并有界强度/时长，不叠加位移，不反复重启振荡相位。
- 可通过角色 Inspector 的 `hurt_shake_enabled` 关闭；不受镜头抖动开关或粒子预算影响。

## 屏幕抖动同步增强

- `scripts/world.gd`：伤害镜头强度 1.0 → 1.6；每轴幅度上限 10 → 32 视口像素。48 点伤害的峰值由约 8.66 → 13.86 像素，256 点及以上可达新上限。
- 旧技能通道 `max_shake_amount` 100 → 320；`scenes/world.tscn` 的 `shake_rate` 0.03 → 0.1，消除场景层的额外缩小。技能峰值现可达到 32 像素。
- 场景 `default_shake_restore` 50 → 160，随上限同比提高回落速度，保留约 2 秒以内的旧技能峰值恢复时间，而不是因提高上限拖出约 6 秒长尾。实际伤害通道仍独立使用 0.10–0.28 秒包络。
- 保留镜头抖动开关、缩放补偿、同帧群攻合并上限、弱 DOT 不续强冲击、不将两通道相加、相位持续推进及不消耗战斗 RNG。

## 技术边界

`classes/ball.gd` 在已有实际扣血反馈及其 RPC 路径接入 `scripts/effects/character_hurt_shake.gd`。只在 `RenderingServer.frame_pre_draw` 合成 CanvasItem 渲染变换，不修改角色根节点、Graphics 节点属性、速度、碰撞框或武器发射坐标；不增加网络消息、不消耗战斗全局 RNG。

每帧使用当前动画/眩晕姿态，不缓存旧基线。通过 `affine_inverse().basis_xform()` 转换世界偏移，正确处理角色缩放；不能用只适用于正交归一基的 `basis_xform_inv()`。

角色可用 `register_hurt_shake_visual()` 注册独立视觉层；动态部件可覆盖 `_get_hurt_shake_visual_parts()`。溺尸手持三叉戟、附魔遮罩和杆上电弧一起抖；离手/返航/插墙后的真实武器和电光不跟随。动态退出的部件恢复其当前真实姿态。

暂停、死亡、释放和效果到期都会清除渲染覆盖，停止处理并断开绘制回调。组件惰性创建，空闲时不处理。

## 验证

Steam Godot 4.7.2；GPU 项使用 D3D12 / RTX 4060 Laptop。

| 测试 | 检查项 |
| --- | ---: |
| `test_character_hurt_shake.gd`（GPU） | 70 |
| `test_mc16_charged_impact.gd`（GPU） | 41 |
| `test_mc16_enchantment.gd`（GPU） | 45 |
| `test_drowned_damage_audio.gd` | 24 |

初版四组回归合计 157 项检查通过；上一版受伤抖动 GPU 回归为 49 项。本轮扩展为角色与镜头联合 GPU 回归（70 项），不将历史测试计入本轮重跑数。雷击、附魔、音效逻辑未改。

新增测试覆盖真实 48/24 雷击结算、减伤、护盾、治疗、幅度单调有界、连续受击复用、碰撞/锚点不变、召唤物、真实眩晕并存、暂停/死亡/销毁，以及 GPU 像素位移、缩放修正、动画更新、动态脱离、归零。镜头新增真实 Camera2D 位移验证、普通与重击强度、同帧大量命中上限、弱 DOT、两通道不叠加、技能回落时长、连续命中双向振荡和 RNG 保持；GPU 在 1 倍和非均匀缩放下逐像素检查 32 像素峰值与关闭后的复位。

更新了旧回归测试的伤害期待，并让其手动推进已经存在的投掷前摇；手持镜像验证改为变换行列式与当前武器姿态一致性，避免把正常握持旋转误判成没有镜像。没有为迁就测试改动生产投掷时序或镜像逻辑。

联机覆盖是 authority/replica 调用路径和重复反馈检查，**不是双客户端端到端网络验收**。工程诊断无 error，修改范围 `git diff --check` 通过。测试环境仍有 shader UID/文件名大小写警告，旧回归夹具退出时可能输出 ObjectDB 清理警告；headless 附魔测试偶发 DummyRenderer 空纹理报错，因此视觉相关测试应优先用 GPU 模式。

运行方式（在项目根目录，使用 Godot 编辑器可执行文件）：

```text
godot --path . --audio-driver Dummy --script res://tests/test_character_hurt_shake.gd
godot --path . --audio-driver Dummy --script res://tests/test_mc16_charged_impact.gd
godot --path . --audio-driver Dummy --script res://tests/test_mc16_enchantment.gd
godot --headless --path . --script res://tests/test_drowned_damage_audio.gd
```
