# 出界红色数字提示移除（2026-09-24）

## 范围

`scripts/world.gd` 不再创建、定位或更新角色离开地图后的红色数字 `Label`；仅删除该显示节点及其字号配置。`_out_of_bounds_states` 仍保存内部 elapsed 计时，`out_of_bounds_enabled`、可配的淘汰延迟（默认 3 秒）、返回地图后取消计时、角色逃逸豁免、防挤出和到时强制淘汰均保留。旧场景/脚本未发现对移除的字号导出字段的其他引用。

## 验证

- 离线引擎 `Godot.4.7.2.offline.exe --headless --path . -s res://tests/test_out_of_bounds_no_countdown.gd`：**11/11**，验证真正位于地图外的角色、不生成红色 Label、时间继续累计、回图取消、合法逃逸豁免、关闭规则清空计时，以及到 3 秒仍淘汰。
- 同一引擎真实 GPU 模式运行：**12/12**，另保存并查看截图 `E:\godot\polo-balls-agent-backup-20260924-082607-out-of-bounds-ui\out_of_bounds_no_text_gpu.png`；地图外侧没有红色数字，角色本体可能被既有外侧遮罩裁切。测试不修改玩家配置，并在退出前恢复临时设置。
- `get_diagnostics` 对 `scripts/world.gd` 与测试脚本均返回 0 项。运行日志仍可能有其他未导入的角色资源预热/加载错误；这些测试通过不代表全项目资源无误，也未验证双客户端联机。

## 回退

修改前的 `scripts/world.gd` 和 `MCP_CONTEXT.md` 逐文件备份在上述项目外目录；测试日志/截图也在该目录。主分支已有大量其他任务的未提交内容，只能按本次文件或局部 Git 检查点恢复，不可把它当成整库快照，更不能未经核对使用 `reset --hard` 或 `clean -fd`。
