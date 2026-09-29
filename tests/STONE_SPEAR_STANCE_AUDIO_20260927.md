# 石矛架势切换音效（2026-09-27）

用户要求切换架势加音效。本轮只接入声音，不修改三种架势、切换冷却/动画、成长、伤害或残影。

## 实现与复用

- `set_formation`成功改变架势后触发一次`stone_spear.formation`，三种架势、右键手控与5秒自动换阵共用入口。出生与同步姿态恢复不播放；同阵、非法目标、冷却中、暂停、眩晕、死亡、禁攻/禁技及非权威端的失败操作不产生切换音。
- 复用`new5/audio.gd`已有Minecraft `entity.player.attack.sweep`的7个短促原版挥动变体，与原伸刺音、命中音及格挡音区分。不下载/复制/合成音频，不修改公共音库。现有七个资源文件的SHA-1与其已有哈希文件名全部匹配。
- 权威端用独立`_sfx_rng`选一次变体，经既有`authority/call_local/reliable`音频RPC让双方播放同一音源；不消费玩法随机数，不在复制属性或逐帧绘制中重播。未新增架势音序号协议，使用既有可靠有序RPC传输。
- 基础音量0dB、音高1、发声位置为本体；不叠加原Minecraft事件条目的0.7音量。继续经过`mc_native_audio.queue_stream`安全队列、GameplayRecord总线及全局24声部预算。换阵声为非伤害优先级，不挤占关键伤害/格挡反馈；源在延后播放前删除会取消。已有伸刺、格挡和伤害音的策略不变。

## 实测结果

- 新`test_stone_spear_stance_audio.gd`：headless 45/45；GPU+真实音频48/48。包括三阵切换各一次、发声位置/音量/音高/总线、玩法随机不变、失败静音、手控/自动换阵、姿态重复不重播、七变体、源删除取消和24声部预算。
- GPU测试由实际`set_formation`触发，GameplayRecord捕获7680帧非零PCM，peak=0.512385。证明生产切换事件实际输出音频；未声称主观试听评价或玩家前台鼠标操作验收。
- 真实双ENet 63/63（此前57+新增6）：同一次切换主客各一个播放器、相同权威变体及0dB增益、重复目标/客机越权/重复姿态不增加播放器。其余复制、伤害、格挡、残影和完全重合验证保留。
- 回归：出生展开72/72、完全重合103/103、核心132/132、平滑89/89、格挡150/150、伤害70/70、转向34/34、残影119/119。各测试进程退出0；石矛diagnostics=0。
- 既有shader UID/大小写警告保留。格挡headless退出仍报1个资源在使用（150断言全通过、exit0），延续前几轮已知边界，未将该告警说成已修复。本轮无新增生产脚本，未重跑分类登记。

## 范围与回退

仅石矛脚本、新音频专项、ENet专项增补、MCP石矛条目与本报告。未改公共音频实现、共享素材、其他角色或场景。

备份和本轮所有日志：`E:/godot/polo-balls-checkpoints/stone_spear_stance_audio_20260927/`。独立归档父为上一轮`616c4d1250c9598fe6e9d84e487ffcbc70d0e024`；引用`checkpoints/stone-spear-stance-audio-20260927`→`updates/stone-spear-stance-audio-20260927`。主HEAD/共享index不移动、不推送；共享MCP只归档本轮自有条目补充，保留并行修改。

回退先备份，查看`commit_ids.json`，对`owned_update_minimal.patch`执行`git apply -R --check --unidiff-zero <补丁路径>`，通过后才定向撤销，不用reset --hard或clean。
