# 水印设置入口移除（2026-09-23）

- 删除设置参数页的水印开关，不再创建或补回 `Show_Center_Watermark`；参数列表仍排除这个旧key，防止旧运行时字典把它自动生成成开关。
- 从默认Game_Settings移除该项；加载时忽略旧配置并清理旧内存key，保存时移除旧配置文件中的该key，保留其它设置和其它配置section。旧本地请求被忽略；旧联机key继续不接受、不广播。
- World水印不再受布尔设置控制，旧false值不能隐藏它。不改文字、透明度、位置、随地图缩放和中英文切换；无地图／特殊死档演出等原有展示逻辑保留。
- 无需为了关闭入口改动翻译目录；旧翻译key作为未使用兼容条目保留，不再产生任何设置控件。

## 验证

实际OpenGL运行 `test_watermark_required.gd` 23/23、`test_watermark_follow.gd` 43/43，共66项通过；引擎退出0，最终日志无SCRIPT ERROR / ERROR / FAIL。覆盖实际中文／英文设置页无该开关、其他参数仍在、旧false配置读写、旧请求、旧字典重建UI、网络快照排除、其他配置保留、水印布局与特殊演出恢复。三个生产脚本诊断0项。

日志：`tests/watermark_required_required.log`、`tests/watermark_follow_required.log`。持久化测试设置APPDATA为项目 `tests/_watermark_settings_userdata`，测试拒绝使用真实用户目录，未改写玩家真实settings.cfg。旧玩家配置在正常加载时忽略，下一次正常保存时清除旧key。

## 英文尺寸与透明度（2026-09-23）

- 透明度从 0.24 提高到 0.48。创作者行、点赞行和死档水印共用这个值。
- 中文宽度预算保持地图宽度的 0.30，不再和英文一起放大。英文单独使用 0.56，只放大 “Like and Subscribe!” 那一版。
