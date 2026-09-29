# Sans 待机晃动

- 使用已有原图的身体、脸、汗珠和眼部光晕分层，程序化模拟原作风格的轻微待机晃动；不是宣称新增了原作逐帧动画素材。
- 默认周期2秒，躯干上部左右约2个原图像素，脚底锚点固定；头部跟随脖子位置并轻微点头。不改变角色根节点、碰撞、攻击距离、伤害或整图缩放。
- `idle_sway_pixels` / `idle_sway_period` 可在Inspector调整；幅度0可关闭。
- 重力手势、闪避、最后审判及死亡演出优先，不叠加待机晃动。游戏暂停冻结表现。
- 汗珠每帧重新对齐头部，攻击眼光随头部一起位移，避免分层漂移。
- 新专项 `tests/test_sans_sway.gd` 12/12；已有 `tests/test_sans_final.gd` 58/58。GPU取帧脚本 `tests/preview_sans_sway.gd`，实际24帧截图 `tests/sans_sway_00.png` 至 `_23.png`。原有ObjectDB退出警告仍存在。
