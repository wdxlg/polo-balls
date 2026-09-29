# 唱片机扩展为六首 / 退盘替代声

用户确认新增3首（总计6首），并明确同意使用原版发射器click作为退盘替代声。没有把它冒充唱片机专用退盘声。

## 曲目
保留Pigstep、Otherside、Cat；新增：
- Creator，176.389秒，519音乐事件，铜金/淡紫机械齿纹。
- Precipice，299.313秒，1283音乐事件，淡紫/冰青折线纹。
- Relic，218.967秒，688音乐事件，青绿/砂金像素点。

选曲参考玩家讨论口碑，非官方或严格实时热度排名：
https://www.reddit.com/r/Minecraft/comments/1f1j9pv/which_one_of_the_modern_music_discs_are_your/
https://www.reddit.com/r/Minecraft/comments/1ko0d49/now_that_we_have_a_lot_of_them_which_is_your/

原版Java1.21.1 OGG与唱片纹理，音频从Mojang资源服务器取得并SHA1校验，来源见sources.json；PNG从已校验的官方client.jar提取。Creator作者Lena Raine，Precipice/Relic作者Aaron Cherof。素材并非免版权，遵守原作品及Minecraft相关条款。

三首新增原版文件也均为单声道，所以当前六首左右同峰等强；不伪造原曲声道偏移。三首均完成离线低/中/高频瞬态、混音主导音高、延音与拍点显著度分析，见analysis_report.json；保持既有识别局限，非精确分轨。
Precipice首个阈值内音乐峰在7.54秒，不为测试或填空而往安静开头硬塞攻击。

## 实现
- TRACKS/MUSIC/DISCS扩为6，随机初曲和循环边界使用数组长度，不再写死3。
- 新分析分成features_creator/precipice/relic.gd，由extra_library.gd组合并入既有峰表；旧三曲分析未重新改动。
- 六套独立颜色和装饰，发射时固定主题索引，换曲不会把在飞的波误换色。
- 退盘瞬间播放一次block.dispenser.dispense对应random/click.ogg，-3dB，原速。重复finished不会再播放。进入插盘或播放阶段不触发退盘声。
- 原有原速/插盘/抛物线掉出地图后换盘、20次成长、每秒5层衰减、命中止衰减、单侧180°、响度影响大小与伤害、五项音乐机制都保留。仙人掌本轮未修改。

## 验证
- GPU test_mc_music6.gd：639/0，exit0，cmd_1789689087502_527。
- 实战 test_mc_music6_live.gd：38/0，exit0，cmd_1789689139307_528。三首新增曲实际播放、产生分析驱动攻击、seek近末尾后真实EOF信号弹盘、单次退盘声、正确下一张均验证。
- 模块diagnostics0；既有ObjectDB121–153退出警告保留。未完整主观试听三首、未双客户端实测。
- preview_mc_music6.gd是GPU安排的静态主题对比（仅画右波），不是自然战斗录像；配原版新唱片图。
- 通用test_mc_cactus_note.gd及live同步本轮版本。
