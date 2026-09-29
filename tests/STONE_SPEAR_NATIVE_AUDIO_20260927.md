# 石矛：指定Minecraft长矛原版音效（2026-09-27）

用户明确要求：换阵用`minecraft:item.spear.use`，刺形态出刺用`minecraft:item.spear.attack`，低于50伤害命中用`minecraft:item.spear.hit`。本轮取代此前挥动声/机械click的选型，仅调整石矛的音效，不改玩法、伤害公式或其他角色。

## 事件和触发

|时机|实际音效事件|资源|
|---|---|---|
|成功切换架势，手控/自动一致|`minecraft:item.spear.use`|`item/spear/use.ogg`|
|STAB成功开始出刺（包括刺空）|`minecraft:item.spear.attack`|`item/spear/attack1..3.ogg`|
|本体或四分身矛头造成实际扣血`0 < damage < 50`|`minecraft:item.spear.hit`|`item/spear/hit1..3.ogg`|
|恰好50实际扣血|保留`entity.player.hurt`|既有普通命中音|
|大于50实际扣血|保留`entity.player.attack.crit`|既有暴击命中音|

依据防御、伤害限制和剩余血量结算后的实际扣血选择命中事件，而不是面板/理论伤害。三种架势、本体及四分身共用真实矛尖命中入口；零伤害不播命中声。回收/待机不另发出刺声；换阵失败、重复姿态和冷却不重播。

变体只在权威端由独立音效RNG选择，原可靠`call_local`音频RPC把事件/变体/接触位置/增益同步到双方，不改玩法随机数。原格挡声保持。继续复用`mc_native_audio.queue_stream`安全队列、GameplayRecord、24声部预算；use/attack基准0dB、自然音高1，hit保留原按实际扣血计算的增益及伤害优先级。

## 素材与来源

从Mojang官方Minecraft Java1.21.11版本元数据定位官方asset index及`sounds.json`；均验证SHA-1，再按确切三个`item.spear`事件取得七个原音。这里不是`item.spear_wood`，不再使用木矛attack或替代click。项目既有音频中未检出这七个相同哈希文件，因此新增到`audio/characters/我的世界/stone_spear/`，每个Ogg核对官方大小/SHA-1，保持原始字节。完整索引URL/hash、事件映射、CDN地址及权利说明在该目录`SOURCE.json`。共享原素材不删除，不授予额外分发许可。

原版use长度约1.148271秒，不为满足此前“短click”的旧测试而裁剪指定原音。原版事件映射均为默认增益/音高；attack和hit各三个变体。

## 验证

- 新原音专项：headless128/128，GPU+PCM132/132。校验七个非木矛资源路径、真实换阵/出刺、出刺去重、回收不重播、全部attack/hit变体、优先级与增益、0伤害静音、49.999/50/50.001严格边界。
- 真实碰撞：三种架势×本体/四分身×49/50/51伤害，45组真实扫掠分别核对实际扣血和所选事件，不只直接调用音效模拟阈值。
- 换阵音专项33/33、GPU36/36；真实双ENet77/77，含出刺同变体、49/50/51事件与增益、每端一次以及此前换阵/格挡/姿态/残影同步验证。修正测试连续51→80都是crit时仅等事件名、未等新增益的异步等待竞争，生产同步未为测试修改。
- 三个实际音频事件均在GameplayRecord抓到非零PCM，各7680帧：use peak0.312722、attack0.308876、hit0.693671。use/attack由真实动作入口触发；PCM hit用伤害反馈入口，真实碰撞另按上一条验证。未声称主观试听/玩家前台鼠标操作验收。
- 回归：出生展开72、完全重合103、核心132、平滑89、格挡150、伤害70、转向34、残影119，全部断言通过，各运行测试退出0；石矛diagnostics=0。
- 导入边界：普通headless编辑器`--import --quit`已完成七资源导入及布局加载，但退出码3221225477（0xC0000005）；未定位编辑器退出异常。之后`--recovery-mode --import --quit`退出0，七资源可加载、游戏/GPU测试正常；不以恢复模式通过声称普通模式崩溃已修复。两份导入日志保留。既有shader UID/大小写警告及格挡测试退出1个资源告警仍保留。未新增生产脚本，未重跑脚本分类登记。

## 范围和恢复

修改石矛脚本、既有换阵音/ENet专项和MCP石矛条目；新增原音专项、七个Ogg及导入配置/来源、本报告。历史报告和共享音频库不改。

checkpoint：`E:/godot/polo-balls-checkpoints/stone_spear_native_audio_20260927/`，含修改前备份、全部日志、commit_ids.json及最小自有补丁。独立父为`4539bf5e32eba6aa401237dac17b0d19f7325f5a`；引用`checkpoints/stone-spear-native-audio-20260927`→`updates/stone-spear-native-audio-20260927`。主HEAD/index不移动、不推送，共享MCP按最新内容只反向剥离本轮自有修改构建before，保留并行编辑。

回退前备份，执行`git apply -R --check --unidiff-zero <owned_update_minimal.patch>`，通过后定向撤销；不要reset --hard/clean。
