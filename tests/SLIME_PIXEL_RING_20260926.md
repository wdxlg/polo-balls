# 史莱姆 Minecraft 像素圈（2026-09-26）

- 普通落地和死亡冲击共用 slime_jump_fx.gd，去掉72段抗锯齿 Line2D，直接调用公共 pixel_arc.draw_ring；不复制光栅算法，不新增素材。
- 保留绿色、0.42地面椭圆、10×体型到原reach的缓出半径、0.5秒渐隐、身体下层；起跳仍只有原粒子，不新增圈。
- 保留三体型粒子40/27/17、起跳5/3/3、伤害/击退/分裂、普通特效暂停与死亡清理、终局死亡特效独立完成。

## 本轮验证
- Godot 4.7.2 Steam：test_slime_death_pulse.gd 80/80，退出码0；更新旧Line2D点数断言为脚本绘制环、投影和动画半径检查。
- D3D12 RTX4060：test_slime_death_visual.gd 9/9，退出码0。普通落地1342绿色变化像素，实战死亡1337，独立背景75。
- FX文件诊断0。原shader UID/大小写警告仍在；无头回归退出清理出现 texture_2d_initialize Parameter t is null（dummy纹理后端），不能称为零引擎错误。GPU回归未见该错误。
- 未做人工美术验收、双客户端及实际编码录制验证。

## 版本与回退
- 更新前 HEAD：79a38a16fbb714c0450a4a1dd4145cdd19058d5b。
- 修改前FX和已有脏MCP_CONTEXT备份：%TEMP%/slime_pixel_ring_before_20260926/。
- 本次只提交FX、对应行为测试、本说明及MCP索引新增行。其余大量已有修改和未跟踪资源不属于本提交，不是整个项目快照。
- 回退前检查备份当前修改，优先撤销本提交；不回退其他任务，不执行reset --hard/clean，不推送。
