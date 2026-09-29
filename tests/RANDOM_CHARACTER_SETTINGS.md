# 随机人物设置与排除名单

## 行为

- 删除“人物方式”后独立的 5px 占位；自定义模式隐藏随机区域后，两行仅保留 VBox 的 2px 常规间距。
- 分类开关与排除名单是独立的持久配置，不属于人物方式切换的临时界面状态。切换随机/自定义、切分类、搜索、关闭重开、世界重置及读取设置都不会清空它们。
- 随机模式的人物按钮是独立多选开关：**按下（暖红色）＝排除，不会被抽到；再次点击＝恢复参与**。自定义模式仍按原方式选择单个人物，不更改排除名单。
- 随机模式保持搜索可用。搜索到的跨分类人物同样可以排除，按钮重建后从配置恢复。
- `Random_Character_Excluded` 存储 `分类/内部人物名`，不使用翻译后的按钮文字。当前分类优先的搜索规则与原选择器一致，同名但不同分类的角色互不影响。
- 排除项参与权威抽取池缓存的键，改动立即生效。类别关闭时其排除偏好仍保留；启用分类后继续应用。所有人物被排除时禁止放置/开始空池抽取，不偷偷回退到全集。
- 障碍物本来就不进入人物抽取池，随机模式下其按钮禁用并给出说明。
- 接入现有配置文件与共享设置同步机制；受限房客不能修改排除名单，界面及点击处理均做权限检查。

## 验证

- `test_random_character_settings.gd`：**45 checks / 0 failures**，真实 GPU 渲染和鼠标按下/松开输入。
- 覆盖紧凑间距、多选/恢复、模式往返、保持自定义人物选择、跨分类搜索、同名分类隔离、列表重建、分类开关、语言切换、配置保存及重新加载、同步字段、错误输入归一化、受限房客、空池禁止与实际生成结果。
- `test_random_character_draft.gd`：**66 checks / 0 failures**，原四种玩法、暂停恢复、取消、结束退场流程保持正常。
- 测试只在隔离 APPDATA 下写真实配置，不改用户现有设置。双客户端端到端联机未执行，使用原共享设置通路并测试其快照字段和本地权限保护。
- GPU 截图：`random_settings_compact.jpg`、`random_settings_excluded.jpg`、`random_settings_saved.jpg`，位于 `tests/`。角色索引使用小型测试夹具，不加载整个人物库。

PowerShell（在项目根目录，`$godot` 指向项目使用的 Godot 编辑器）：

```powershell
$oldAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path (Get-Location) "tests/_random_settings_userdata"
    New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
    [IO.File]::WriteAllText((Join-Path $env:APPDATA ".gdignore"), "")
    & $godot --path . --resolution 540x960 --audio-driver Dummy --script res://tests/test_random_character_settings.gd -- --visual
} finally {
    $env:APPDATA = $oldAppData
}
```
