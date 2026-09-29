# 设置参数页横向溢出修复（2026-09-26）

## 原因与修复
背景 OptionButton 默认 fit_to_longest_item；取景 OptionButton 同样按最长内容撑开，且未设置参数页 9px 字号。参数 VBox 的内容最小宽度向上经禁用横向滚动的 ScrollContainer 传递，撑宽上层 VBox 和同级分类按钮，而外框仍固定宽度。

背景/取景按钮关闭 fit_to_longest_item，并启用 clip_text 和省略号；取景按钮及说明改为参数页 9px 字号。分类按钮也允许裁剪长翻译。弹出选项保留全文，背景选中项提供全文 tooltip。保留七种背景和三种取景、信号与存储逻辑，不扩大外框、不缩放全局 UI、不隐藏滚动内容。

## 实测
- `tests/test_settings_width.gd`：D3D12 / RTX 4060 Laptop / Godot 4.7.2 离线引擎。
- 修改前：36 项中 8 项失败，进程退出 1。面板宽 786 屏幕坐标单位，参数页分类/滚动区域中文被撑至 801、英文 807；其它页为 762。
- 修改后：36/36，进程退出 0。中英文 training→parameters→recording→parameters，分类及滚动区宽度均 762，内容 750，均在 786 外框内；选项数保留。
- 已查看中文真实 GPU 截图，背景、取景、说明和分类按钮均在面板内。两份实现脚本编辑器诊断无错误/警告。
- 引擎仍有旧 shader UID/文件名大小写警告。未穷尽全部自定义窗口比例、系统 DPI、特效窗口尺寸和弹出列表交互；不声称整个 UI 所有布局均已验收。
- 日志/截图：`.git/settings-width-20260926/`（before.log、gpu.log、before-zh.jpg、zh.jpg、en.jpg）。

## 局部版本
main 修改前为 e3faf4226982a076d7ad6b3f3ce58dc3827112da；涉及文件修改前实际状态已保存为 b45527b78c25f44484ba575c88928115987bd451（checkpoints/settings-width-20260926）。功能提交保存在 updates/settings-width-20260926，隔离 Git index，不改 main、不动其他暂存区、不推送。只保证本次文件差异可回退，不是整个脏工作区快照。回退前备份最新工作，再对本次提交差异先做反向补丁检查，不能硬重置整个工作区。
