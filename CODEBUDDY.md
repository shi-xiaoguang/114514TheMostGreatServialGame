# Robinson 执行入口

本文件是本仓库的 CodeBuddy 规则入口。2026-10-11，主创已授权统一执行入口、规则入口和 Git 工程位置，随后授权将旧工程成果分批迁入、验证、提交 Git，再清理旧工程。

## 正式工作区

- 本机正式仓库：`D:\GitProjiect\Godot\114514TheMostGreatServialGame`。
- 在 CodeBuddy 中打开本目录，或本目录的 `Robinson.code-workspace`；工作区只包含此仓库。
- `D:\Godot-AI-Lab` 保存历史资料；其中 `robinson` 是旧工程及待移植成果来源，不作为日常开发、运行或提交目录。
- 若从旧目录进入，直接切换到正式仓库并读取本入口；不要重新询问已经确定的主线。后续明确授权的独立工作树按当次任务记录执行。

## 每次任务开始

1. 读取根目录 `AI_TEAM_RULES.md`（现行 v0.2.1，正式生效）。规则正文只在该文件维护；本入口不复制审批、岗位和验证条文。
2. 读取 `PROJECT_STATUS.md`，按需读取 `README.md`、对应系统规格和历史决定。
3. 核实实际目录、Git 根、分支、提交和未提交改动。可用 `Get-Location`、`git rev-parse --show-toplevel`、`git branch --show-current`、`git log -1 --oneline`、`git status --short`。现有用户改动必须保留。
4. 开始实现前明确本任务目标、改动范围及验收方式。历史计划中的路径、待办状态、阶段限制必须结合当前授权和代码核对，不能直接当作最新任务。

## 执行和收尾

- 编辑、终端、Godot 运行及测试都以当前正式仓库为工程根。调用 Godot 命令或 MCP 时显式指定本仓库路径；不能因旧工程同名而选错。
- CodeBuddy 的 Godot MCP 使用本机根目录 `.mcp.json`；它是本机配置，不纳入 Git。既有岗位技能在用户级 `C:\Users\Lenovo\.codebuddy\skills`，按守则按需读取。
- `project.godot`、主场景和玩家脚本的并行修改由一个集成负责人协调；不要从旧工程整文件覆盖这些文件。保存场景前确认编辑器实际打开的工程，避免旧窗口覆盖新文件。
- 任务完成后运行与改动相匹配的检查，记录实际工程、代码版本、测试入口、结果及证据位置；常驻回归脚本保留在仓库中，不再用后删除。
- 依据结果更新 `PROJECT_STATUS.md` 的相关条目。已实现、已验证、已验收分别记录；历史测试数字不能代替当前版本的验证。
- 开始时说明实际读到的守则版本；收尾按守则报告结果、未解决项、已使用技能和待批事项。已在当前任务获准的事项无需反复确认。

## 历史来源

- `D:\Godot-AI-Lab\.codebuddy\plans`：历史计划。
- `D:\Godot-AI-Lab\Robinson_Project_Advisor_Handoff_v1.0.md`：交接快照，其过时结论以当前代码、有效决定和验证记录校正。
- `D:\Godot-AI-Lab\archive\2026-10-11-workspace-entry`：入口统一前的规则及 CodeBuddy 入口原文。

历史文件保持原貌；涉及当前状态的更新统一写入正式仓库。
