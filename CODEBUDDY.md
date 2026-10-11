# Robinson 执行入口（Codex / CodeBuddy 共用）

## 开始任务

1. 读取 [AI_TEAM_RULES.md](AI_TEAM_RULES.md)（v0.3），再读取 [PROJECT_STATUS.md](PROJECT_STATUS.md)。
2. 核实工作目录、Git 根、分支、提交和未提交改动；保留已有用户改动。
3. 按 [工作流说明](workflow/README.md) 从本仓库固定版本的技能库中选取最小技能集合，再读取对应 `SKILL.md`。项目内版本优先于用户级旧副本。
4. 明确本次目标、改动范围、验收方式，再执行。最新用户授权优先于历史计划。

## 唯一工作区与工程

- **工作区 / Git 根**：本目录。可打开 `Robinson.code-workspace`。
- **Godot 工程根**：`game/`，入口 `game/project.godot`；游戏内 `res://` 对应 `game/`。
- **技能与工具**：`workflow/`；完整上游源码位于 `workflow/vendor/godot-game-dev-studio/`。
- 终端、编辑器及 Godot MCP 必须明确使用 `<仓库>/game` 作为工程路径。禁止在仓库根或技能库示例工程中运行游戏。
- `.mcp.json` 与 `workflow/local-settings.json` 是本机设置，不提交 Git。配置存在不代表应用内 MCP 已连接。
- `D:\Godot-AI-Lab` 仅保存历史资料与备份；不得恢复旧 `robinson` 为日常工程。

## 执行与收尾

- 同一文件只安排一个修改者；共享文件由集成负责人收口。
- 测试入口：`workflow/scripts/run-tests.ps1`；结构检查：`workflow/scripts/validate-workspace.py`。
- 游戏测试常驻 `game/tests/`，不能按旧历史说明删除。新日志独立保存，不覆盖历史证据。
- 收尾更新唯一当前状态页 `PROJECT_STATUS.md`，给出结果、证据、未解决项、已用技能及待批事项。
