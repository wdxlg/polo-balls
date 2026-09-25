# 唤魔者图腾平滑与抬手复位（2026-09-26）

## 图腾
参考 Minecraft Java GameRenderer.renderItemActivationAnimation：40 tick / 20 Hz = 2秒；相位 p=π(10.25t⁵−24.95t⁴+25.5t³−13.8t²+4t)，Y转角为900°|sin(p)|，尺寸包络为50+175sin(p)。核对入口：https://github.com/mahtomedi/minecraft/blob/main/src/main/java/net/minecraft/client/renderer/GameRenderer.java 。这是代码参考，不新增/分发原版素材。
本项目保留原版已有图腾图片，二维战场用余弦投影模拟前后翻面，保持20像素最大宽度；不是把原版第一人称全屏动画直接覆盖战场。出场飞升0.32秒使用五次平滑曲线，末段透明淡出；取消侧面最小宽度正负跳变、开头预跳25毫秒。持续金绿粒子沿用此前实现，均匀发射延长至2秒，尾迹最多1.1秒。

## 手臂
根因：_victory_cheered一旦置真，动画选择永久celebrate；战斗门关闭时提前return还能冻结未结束的cast计时。
修正：保留胜利音效一次标记，但庆祝动画独立限时1.6秒；没有目标也能结束0.85秒施法，战斗门关闭后允许未完成手势收尾，眩晕清除施法姿势。新施法覆盖旧庆祝；暂停仍冻结动作。客户端抬手姿势采用0.6秒续期，避免丢失终止包后永久举手；未做真实双客户端验证，仅有本地客户端状态夹具。
没有更改技能伤害、手控绑定、图腾复活及音效素材，也没有重新烘焙角色图片。

## 验证
Steam Godot 4.7.2：
- test_evoker_smooth_and_reset.gd：17/17，包括战斗门真实关闭夹具、暂停、施法/庆祝收手、客户端超期和连续曲线。
- test_totem_continuous_particles.gd：13/13；test_evoker_totem.gd：41/41。
- test_evoker_totem_visual.gd：D3D12 RTX4060真实GPU 16/16，正面/侧面/背面像素215/0/320；检查峰值大小、跟随、后段可见、原版金绿粒子与尾迹。真实截图user://evoker_totem_visual/native_peak.png已读取检查；未做人工连续视频流畅度验收。
- test_evoker_arms.gd：6/6；test_mc_native_animation.gd：691帧、2160断言、0失败。
- 既有shader UID/路径大小写与夹具退出对象泄漏警告仍存在，不宣称整个项目无警告；未验双客户端、完整双语录制编码。

## 版本与边界
任务开始HEAD为adf633d60e4314de7daea33f9720108f69c0da05；收尾时另一任务提交19ad00f96559b12428405f3ca07dc2feb4800b37（地图墙），已核对不涉及本次代码。最终提交以19ad00f为父提交，只纳入本次差异。
唤魔者、公共动画、公共动画测试已有未提交工作：修改前备份在tools/checkpoints/evoker_smooth_20260926/，本次只暂存各自相关行，不把这些文件的其他角色/手控改动一并提交。工作区仍有其他未提交文件，不是整个项目快照。回退先备份当前工作，优先git revert本次提交，勿reset --hard。
