# 烈焰人原版受伤反馈音

## 目标

- 烈焰人的火焰弹直接命中敌人且真正扣生命时，播放原版 `entity.player.hurt`。
- 烈焰人留下的地面火场每一次有效伤害 tick 真正扣生命时，也播放同一原版受伤音。
- 音量按“实际生命损失”单调增加，而不是按未减免的 outgoing damage 或固定音量播放。
- 生命减伤、火焰抗性、护盾完全吸收、队伍过滤、免疫和完全闪避都不再产生假的受伤音。

## 实现

- `scripts/effects/我的世界/女巫药水伤害音效.gd`
  - 新增 `impact_volume(actual_health_damage)`：
    `2.0 - 26.0 / (1.0 + actual_health_damage / 50.0)`，沿用矿车/木剑实际伤害音量曲线，输出随后由 new5 音源限制在约 `[-24, 2] dB`。
  - 新增 `play_scaled(...)`，通过 `scripts/characters/我的世界/new5/audio.gd` 的官方 `entity.player.hurt` 事件随机播放项目内三张原版变体：
    `hit1.ogg`、`hit2.ogg`、`hit3.ogg`。
  - 输出节点保留 `MCNativeSFX`、`BattleTransient`、`mc_sound_event`，并记录 `mc_actual_damage`、伤害来源和伤害类型，便于后续诊断。
- `scripts/effects/我的世界/烈焰弹.gd`
  - 直接命中后记录命中前后生命差；只有 `actual_damage > 0` 才播 `blaze_fireball` 类型的原版受伤音。
  - 原有伤害、命中判定、燃烧附着和销毁行为不变。
- `scripts/effects/我的世界/烈焰火场.gd`
  - 地面火场每 0.5 秒逐个检测命中的目标；只有火场 tick 真正造成生命损失才播 `blaze_ground_fire` 类型的原版受伤音。
  - 声音定位在受害角色位置；火场范围、持续时长、tick 节奏、燃烧状态刷新、烟雾与原版火焰循环均不变。

## 验证

- `tests/test_mc_blaze_hurt_audio.gd`：22/22。
  - 覆盖直接火弹、地面火场、官方三张 hit 变体、音量随实际伤害单调增大、减伤后按实际生命损失计算、护盾完全吸收无声、有效火场 tick 重复反馈、队伍过滤和火焰免疫无声。
- `tests/test_mc_native_fire.gd`：18/18。
- `tests/test_mc_minecart_audio.gd`：42/42。
- `tests/test_mc_evoker_impact_audio.gd`：16/16。
- `tests/test_audio_pool.gd`：385 checks / 0 failures。
- `tests/test_mace_restore.gd`：153 checks / 0 failures。该测试完成结果后仍会扫描旧角色并打印既有资源瞬时加载报错；这些报错与本改动无关，专项自身全部通过。
- 修改的生产脚本和专项脚本生产诊断均为 0。

本改动按项目现有的本地/权威伤害路径验证；未声称已经完成双客户端听觉实测。
