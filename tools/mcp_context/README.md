# MCP 项目说明自动附带

## 工作方式

项目根目录的 `MCP_CONTEXT.md` 是唯一的当前规则正文。Bridge 为每个新 MCP 会话创建服务时读取它，并附到 `initialize.result.instructions`。另外，在 `tools/list` 返回的 `read_files.description` 中附带相同正文，作为不向模型展示初始化说明的客户端的兼容入口。

每次新建会话/列举工具都读取磁盘最新内容，附 SHA-256；无需把规则写死到客户端或让用户每次额外发送提示。旧会话已经取得的说明不会自动替换，需重新连接或重新列举工具。

读取仅限当前本地工作区根目录的固定文件，阻止符号链接指向工作区之外，单文件最多 64 KiB，最多四个工作区。文件过大时明确提示读取剩余内容。不要放入凭据或秘密，连接此 MCP 的客户端将能看到正文。

`AGENTS.md` 是其他支持该文件的客户端的简短补充入口，不宣称仅凭文件存在就会自动生效。

## 一次安装

```powershell
python tools/mcp_context/install.py --extension E:/ShunCode/resources/app/extensions/shuncode
```

安装器检查现有代码结构，备份原文件，更新 Bridge 的源文件与已编译扩展入口，并安装 `runtime/project-context.cjs`。失败会恢复原文件；不会改动隧道地址、访问令牌或凭据。

如果安装目录拒绝写入，需要通过 Windows UAC 授权一次管理员安装；项目附带 `install-admin.ps1`，只能在管理员 PowerShell 中运行。安装过程输出到本目录的 `install-admin.log` 与 `install-status.json`，这两个机器状态文件不提交 Git。也可以先执行 `python tools/mcp_context/install.py --verify-plan`，仅在临时副本中验证补丁，不改动应用安装目录。

**首次安装后需保存工作并重载窗口或重启 ShunCode 一次。** 不会擅自关闭用户编辑器。当前已加载进内存的 Bridge 代码不会因磁盘文件变更而立刻替换；不能把离线验证说成当前公网连接已验证生效。Cloudflare Quick Tunnel 重启后地址可能变化，使用 Bridge 页面显示的新 URL。

这一回重载后，后续每次 AI 正常接入并读取 MCP 初始化/工具列表，就会取得项目说明，不需要额外口头提醒。客户端若既不提供服务说明又丢弃工具描述，服务端无法强制模型看到它。

## 自检

```powershell
node tools/mcp_context/test-context.cjs
python tools/mcp_context/install.py --check
```

- 读取器测试：缺失文件、UTF-8/BOM、中文、摘要、动态刷新、远程 URI、超长文件和非文件路径。
- 安装检查：实际编译入口语法检查，并对安装文件中的 `createSession` 方法进行离线模拟，确认完整项目正文出现在初始化说明与工具描述中。
- 重载后的线上验证：新建 MCP 会话，检查 `initialize.result.instructions` 和 `tools/list` 的 `read_files.description` 是否包含 `# polo-balls 项目规则与接入说明` 及最新 SHA-256。

## 恢复与升级

安装器在项目旁 `polo-balls-checkpoints/mcp_context_bridge_时间/` 保存扩展原文件与哈希清单。恢复该目录中的 `src/bridge-server.ts`、`dist/extension.js` 到清单指向的扩展目录；若 `helper_existed` 为 false，移除新增 `runtime/project-context.cjs`，然后重载窗口。

ShunCode 升级可能覆盖安装目录补丁。项目中的规则、安装器与测试纳入 Git；升级后可运行 `install.py --check`，必要时重新安装。安装器若遇到不同结构会停止，不盲目修改新版代码。

项目规则的回退与编辑器扩展的回退是两件事：Git 保存项目文件；编辑器安装目录的修改使用上述独立备份。未经核对不要整体回退工作区中其他任务的改动。
