# Robinson 工作流

本目录承载开发工具和技能，游戏仅位于 `../game/`。上游示例、插件和脚本是参考资料，不自动装入游戏、注册 Autoload 或运行安装器。

## 单份来源与完整适配

完整上游保存在 `vendor/godot-game-dev-studio/`，来源为 [bgrenat/godot-game-dev-studio](https://github.com/bgrenat/godot-game-dev-studio)，固定提交 `9e2b2beaf0bc7ba2e27a40326d058ff2c7a619a9`。原始许可证、NOTICE、插件清单、参考文档、脚本和素材全部保留；文件列表与逐文件 SHA256 见 `upstream-lock.json`。上游 Git 元数据不嵌入本仓库。

上游 `skills_index.json` 有遗漏及重名，不能直接作为完整目录。项目使用 [skills-index.json](skills-index.json)：从实际 189 个技能目录生成，目录名为唯一 ID，记录原始 `declared_name`。其中 `godot-ai-navigation` 的原始声明与 `godot-navigation-pathfinding` 冲突，由适配层正名；上游文件保持原样。

```text
vendor/godot-game-dev-studio/skills/     原始正文与参考资料（唯一来源，跟踪 Git）
skills-index.json                       完整索引（生成后跟踪 Git）
skills/<技能名>/SKILL.md                轻量适配入口（本机生成，忽略 Git）
../.agents/skills                       Codex 入口链接 → workflow/skills
../.codebuddy/skills                    CodeBuddy 入口链接 → workflow/skills
```

本机 Windows 使用目录联接，其他平台使用符号链接；两端共享同一套生成入口，没有两份技能正文。初始化脚本保护已有非托管目录和手动修改过的适配器；不会改用户级技能。完整目录均可通过根入口按需读取，不依赖当前聊天是否已经刷新原生技能选择器。

## 选技能与执行

1. 先读根 `CODEBUDDY.md`、`AI_TEAM_RULES.md` 和 `PROJECT_STATUS.md`。
2. 从 `skills-index.json` 选择最小集合；广泛任务先读 `studio-router`，实现按领域选技能。
3. 打开 `vendor/godot-game-dev-studio/skills/<id>/SKILL.md`。技能引用的 `scripts/`、`references/`、`assets/` 一律相对于**该源技能目录**解析。
4. 根规则和当前用户授权约束技能使用；技能示例不是游戏规格。涉及引擎 API 时核实项目实际版本，不因技能版本声明升级引擎。
5. 修改后运行对应检查；更新根状态页。不会因“载入技能成功”就声称功能已经验收。

| 任务 | 首选技能 |
| --- | --- |
| 范围与排序 | `studio-producer` |
| 工程结构与集成 | `studio-godot-technical-director` |
| 脚本实现 | `godot-gdscript-mastery` |
| 玩法 / 数值 | `studio-gameplay-lead` / `studio-systems-designer` |
| 测试与验收 | `studio-qa-playtest-lead` |
| 关卡 / UI / 叙事 | 从完整索引选择对应 `studio-*` 与专门技能 |

## 安装与验证

在仓库根执行（PowerShell 7.2+ / Python 3.10+）：

```powershell
./workflow/scripts/setup-workspace.ps1 -GodotPath '你的 Godot 可执行文件路径'
python ./workflow/scripts/generate-skills.py --check
python ./workflow/scripts/validate-workspace.py --require-native-links
./workflow/scripts/run-tests.ps1
```

设置脚本可重复运行，先生成并校验适配器，再建立 `.agents/skills` 和 `.codebuddy/skills`。两个链接以及 `local-settings.json` 不提交 Git；新检出后重建。移动整个工作区后，若旧联接仍指向原位置，脚本会拒绝覆盖并给出具体路径，确认后只移除旧联接再重新设置。

修改适配生成或校验工具后，执行 `python -B workflow/scripts/test-skill-tools.py` 重放工具自身的边界检查；普通游戏修改不必重复这组工具测试。

测试默认将每次日志写入 `game/.godot/test-results/<运行 ID>/`。需要保留为正式证据时，使用 `-LogRoot 'docs/validation/<新目录>'`，已有目录会被拒绝，避免覆盖历史。`-Suite data|interaction|ui|movement|all` 可选择范围，每个引擎进程都有可调超时。

CodeBuddy 的现有 `.mcp.json` 为本机配置，调用 Godot MCP 的 `projectPath` 必须指向 `<仓库>/game`。Codex 可直接使用上述终端入口；本集成不依赖 MCP 连接或额外全局插件。

## 来源更新

上游源码是带校验的固定快照，不自动追踪 `main`。更新时：

1. 在临时目录检出明确的上游提交，检查变更、许可证与技能接口。
2. 使用该提交的原始文件替换 `vendor/godot-game-dev-studio/`，保留全部文件但排除 `.git`。同步记录仓库 URL、提交、版本、文件清单和 SHA256 到 `upstream-lock.json`；不要手改上游文件来修补项目适配。
3. 审查项目生成器对新目录和名称的适配，执行 `generate-skills.py`，检查完整索引的差异。
4. 运行结构与原生入口校验；工具或游戏边界受影响时运行相应回归。源码、锁文件、完整索引和证据一起提交。

本仓库 `.gitattributes` 对上游关闭文本转换，确保 Windows 和其他平台检出后校验值一致。库内所有许可证与署名保留在其原路径；不将该库的许可证声明冒用为游戏自有内容许可证。

## 兼容依据与边界

- [OpenAI 官方技能说明](https://learn.chatgpt.com/docs/build-skills)：项目 `.agents/skills`、延迟加载和符号链接支持；技能选择器可能缩短或省略超出上下文预算的元数据，完整本地索引仍可读取。
- [CodeBuddy 官方技能说明](https://www.codebuddy.cn/docs/ide/Features/Skills)：项目 `.codebuddy/skills/<name>/SKILL.md` 入口。已检查本机 3.10.0 扩展的 `scanSkillsDirectory`：支持链接目录，并优先加载工作区技能。
- 文件校验、生成器检查和链接可读性是静态验证；客户端新会话的自动发现与应用内 MCP 连接需分开记录，不能由文件存在直接推定。
