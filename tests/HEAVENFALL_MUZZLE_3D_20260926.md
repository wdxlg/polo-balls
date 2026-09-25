# 天堂陨落长弓发射环：伪3D朝向纠正

2026-09-26，用户明确要求“这个圈应该是伪3d的。朝着弓头的方向”。本次将上版屏幕正圆改为**环面法线与出箭方向一致**的透视椭圆。

## 实现

- 仍在真实箭矢出生点发圈；`_spawn_shot_ring(point,shot_direction)` 可靠RPC同时传递出生点与当时方向，不用接收端当前位置/当前瞄准方向推导。
- 公共 `expanding_ring` 新增 `direction`（默认RIGHT，归一化，零向量回退RIGHT）、`depth_ratio`（默认1，限0.05–1）。长弓取0.35。
- 原重锤效果新增 `ring_axis/ring_depth_ratio`；对现有 `pixel_arc.draw_ring` 的整个环及笔画施加2D正交投影：沿法线压缩、垂直于法线的轴保持。向右射时环呈竖椭圆，向上射时呈横椭圆，斜射随之旋转。不是仅旋转一个正圆，也不将椭圆长轴错误地指向箭头。
- 环面法线、中心在发射时固定，后续转头、移动、后坐不带动旧圈；环内空心，保持青绿/浅青/银白三层色、半径8→24、0.38秒扩大渐隐及暂停冻结。
- 仍复用公共时序和像素扫描线，不增加3D资源、伤害、声音、碰撞、碎屑或地表采样。绘图变换在环绘制后立即复原，不影响射线和碎块。旧调用默认比例1、朝向RIGHT，原地面圆环保持原样。

## 验证

真实 Godot 4.7.2 offline 引擎，OpenGL Compatibility / NVIDIA RTX 4060 Laptop，6套重跑均退出0，**239项通过、0失败**：

- `test_heavenfall_muzzle_ring.gd`：41/41；GPU上/下/左/右/两种斜向的横轴长度明显大于法线轴、扩大渐隐、中心透明；手控/AI发射与出生朝向冻结、公共默认平面回归。
- `test_heavenfall_muzzle_network.gd`：17/17；单引擎进程内独立双 SceneMultiplayer + ENet + 实际Spawner。发射后刻意改变两端朝向与位置，远端仍使用包内出生坐标/法线；无重复/无伤害、暂停清理保持。
- 长弓 contacts 22/22、transit 53/53、arrow_pierce 71/71；硫方怪 polish 35/35，共享平面像素环/TNT与原版晶簇回归通过。

GPU时间0/0.19/0.34/0.38秒的可见像素120/360/180/0，峰值alpha约0.988/0.533/0.086/0。截图 `user://heavenfall_muzzle_3d_*.png`；已读回并查看斜向投影截图。日志 `tests/<测试名>_muzzle3d_final.log`。

未做双机器人工联机、弱网、压力测试或实际录制编码验收。原有shader UID/大小写警告、旧长弓夹具退出约186–190个ObjectDB实例泄漏仍在，新两套夹具无脚本错误。

## 版本/回退

开始前HEAD：`415ea276c435b242ab56ad82ab72e62c55feb1ab`。检查点：`E:/godot/polo-balls-tools/checkpoints/heavenfall-muzzle-3d-20260926-052722`，含原文件、索引与工作区补丁。

开始时其他唤魔者更改已在暂存区；验证期间另有唤魔者/美术提交推进HEAD。保留这些提交与其他工作，仅将本次参数、方向RPC、测试/说明提交在最新HEAD之后。提交前后ID见检查点 `commit_result.json`。

本次专用补丁：`tests/patches/heavenfall_muzzle_3d_20260926.patch`。关闭运行中的游戏，备份并检查后，使用 `git apply --reverse --check <补丁>`；检查通过才可去掉 `--check` 手动回退。只撤销本次伪3D方向增量，恢复上一版正圆，不删除上一版发射圆环；保留其他工作。已做反向检查，未实际执行回退，不使用整库reset。
