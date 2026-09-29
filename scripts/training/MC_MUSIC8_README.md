# 唱片机本体随音乐非等比缩放

已部署到生产 `scripts/characters/我的世界/cactus_note/note_block.gd`。

- 唱片机仍由实时20毫秒RMS峰值驱动；每个音乐事件设置`pulse`，静音/休止后自然回落。
- 本体只做视觉squash/stretch：响度越高纵向伸长越明显，同时横向收窄；低频强拍叠加额外弹性形变。
- 这不是等比缩放：X、Y使用不同系数；碰撞体、伤害、半径、移动、攻击角度与插盘/退盘逻辑均不变。
- 通过补偿Sprite2D offset锚定视觉底边中点，任何响度或节拍形变都不会让底部中心漂移。
- 联机端继续复用现有`pulse/body_punch`状态同步，不新增网络字段；客户端由同一本地公式重算视觉。

验证：
- GPU专项 `scripts/training/test_mc_music8.gd`：`MUSIC8_RESULT checks=687 failures=0`，exit 0（cmd_1789690516489_536）。
- 覆盖响度递增、非等比缩放、底边中点锚定、碰撞尺寸不变、静音恢复原状。
- 通用 `scripts/training/test_mc_cactus_note.gd` 已同步。
- 模块 GDScript diagnostics：0。
- 旧的ObjectDB退出提示仍存在（121左右），与本轮无关。
- `preview.jpg`为4倍近景静态对比；不是录像或主观动画验收。
