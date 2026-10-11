# 游戏目录整理与 Godot Game Dev Studio 整合验证

日期：2026-10-11（Asia/Shanghai）。任务范围由主创明确授权：整理项目与工作流、完整接入指定技能库、兼容 Codex 和 CodeBuddy，并区分游戏本体与工具。

## 结果

【事实】目录和适配已实现，下面列出的静态检查与游戏回归已验证。游戏规则、数值、手感与已知控制器缺陷不在本轮更改范围；自动验证不表示真人体验或发布验收。

| 验收项 | 结果与证据 |
| --- | --- |
| 游戏单独位于 `game/` | 43/43 文件搬迁前后字节一致，含两处任务前未提交改动；[清单](studio-integration/game-move-manifest.json) |
| 上游完整纳入 | 3124/3124 文件与锁文件 SHA256 一致，含许可证及一个上游自带 `.pyc`；[来源锁](../../workflow/upstream-lock.json) |
| 全量技能可寻址 | 从实际目录生成 189 个唯一适配器，修正上游索引遗漏与名称冲突；[本地完整索引](../../workflow/skills-index.json) |
| 两端共用技能 | 2 × 189 个原生文件路由及对应源文件解析通过；[工作区检查](studio-integration/workspace-check.json) |
| 游戏不依赖技能示例 | 静态资源引用与目录隔离检查通过；同上 |
| 不依赖本机旧缓存与文件 | 从暂存索引导出新检出副本，不包含本机设置、缓存和适配器，生成后 6/6 检查通过；[首次检出检查](studio-integration/fresh-checkout.json) |
| 新检出能重建两个入口 | 初始化和强制原生路由校验通过；[初始化输出](studio-integration/fresh-setup.log)、[新检出原生检查](studio-integration/fresh-native-check.json) |
| 重复初始化安全 | 正式仓库第二次执行更新 0 个适配文件，原有链接保持；新检出初始化日志也记录更新 0 个文件 |
| 适配工具自身行为 | 20/20，包括篡改识别、名称冲突、保护用户文件与拒绝覆盖证据；[自测证据](studio-integration/skill-tools-selftest.json) |
| 游戏回归 | 389/389，两个场景冒烟通过；[运行汇总](studio-integration/runtime-verified/summary.json) |

本轮起点为 `bd024efade01948fb18a344a5aff7296be951fbf`。验证针对工作区整理结果；运行汇总记录该起点、未提交状态、执行入口与工程路径。游戏代码由 43 文件搬迁清单绑定；上游内容由锁文件绑定。本记录随整合内容一并提交，不能把起点提交本身说成已经包含本轮改动。

## 上游适配缺陷与处理

原始来源：[bgrenat/godot-game-dev-studio](https://github.com/bgrenat/godot-game-dev-studio/tree/9e2b2beaf0bc7ba2e27a40326d058ff2c7a619a9)，提交 `9e2b2beaf0bc7ba2e27a40326d058ff2c7a619a9`，插件清单版本 0.2.0。所有上游文件保持原始字节，`.gitattributes` 禁止对该快照做换行转换。

- 源 `skills_index.json` 只有 96 条记录、95 个唯一名称，遗漏 94 个实际技能目录。项目生成完整 189 项索引。
- `godot-ai-navigation/SKILL.md` 错误声明为 `godot-navigation-pathfinding`，与另一个技能冲突。项目适配器以目录名作为唯一名称，同时记录原始声明。
- 这些缺陷通过项目适配层处理。结构检查中的三条上游警告说明保留的原始问题，不代表修复后的本地目录失败。
- 上游自带一个跟踪的 Python 字节码文件。为满足完整快照校验，Git 忽略规则对该上游路径例外；它没有被运行或作为游戏依赖加载。

## 游戏运行

实际工程：`D:/GitProjiect/Godot/114514TheMostGreatServialGame/game`。引擎：`4.7.2.stable.steam.ed1daf0bf`。

| 检查 | 结果 |
| --- | --- |
| ITEM-01 | 87/87 |
| INVENTORY-01 | 146/146 |
| INTERACTION-01 | 72/72 |
| UI-01 | 66/66 |
| MOVEMENT-BASELINE | 18/18 |
| 主场景 / 基础世界 | 240 / 120 帧，无项目脚本或场景加载错误 |

第一次运行因沙箱不允许写引擎自带的编辑器配置和用户目录而失败，完整失败输出保存在 [首次运行](studio-integration/runtime/summary.json)。随后取得本机执行权限，重新运行全套并通过；未忽略这些错误来制造通过结果，未覆盖失败证据。原测试运行器已有的“Windows 根证书存储读取失败”过滤保留，仅用于离线本地测试。

当前启动脚本的交互窗口行为只做参数与语法审查，本轮没有为验证额外启动可见编辑器。原根 `.godot/` 的 115 个缓存文件在新目录回归通过后清理，当前缓存只在 `game/.godot/`。

## 客户端兼容边界

- Codex 使用 `.agents/skills`，CodeBuddy 使用 `.codebuddy/skills`，两者链接到 `workflow/skills`。适配器保持原生 frontmatter，正文路由到唯一的源技能文件。
- 本轮并行复审代理的新会话已经实际收到 Codex 注入的 189 个项目技能列表；正式文件路由检查另有 JSON 证据。已有聊天的列表刷新时机仍由客户端控制。
- CodeBuddy 依据 [官方项目技能入口](https://www.codebuddy.cn/docs/ide/Features/Skills) 配置，并核实本机扩展 3.10.0 的 `scanSkillsDirectory` 支持链接与工作区优先。被检文件 SHA256 为 `D63BC6E35BF712E104F5A8C83437146B28F84E4177D320BCD8344E6B82D0D301`；没有复制或修改厂商实现。
- CodeBuddy 选择器中的实际调用、本机 MCP 连接、非 Windows 实机运行未测。本地链接、文件和官方入口验证不能冒充这些结果。Codex / CodeBuddy 新会话可读取同一份完整索引，不依赖 MCP。
- 动态 `res://` 路径与 `uid://` 由 Godot 导入和运行覆盖，静态检查不单独保证它们。第三方示例未全部编译，其正确性不属于游戏回归通过结论。

## 复跑

在仓库根执行：

```powershell
./workflow/scripts/setup-workspace.ps1 -GodotPath 'D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
python ./workflow/scripts/generate-skills.py --check
python ./workflow/scripts/validate-workspace.py --require-native-links
python -B ./workflow/scripts/test-skill-tools.py
./workflow/scripts/run-tests.ps1
```

保存新的验证报告时传 `--output <新文件>`；保存运行证据时传 `-LogRoot <新目录>`。两者均拒绝覆盖已有结果。历史日志和上游原始文件不做格式清洗；自有代码与文档的 Git 空白检查排除这两类原始内容。

使用技能：OpenAI Docs、`studio-producer`、`studio-godot-technical-director`、`studio-qa-playtest-lead`、`godot-project-foundations`、`godot-gdscript-mastery`。实际使用并行代理完成只读审查、兼容核实及工具实现；最终结论以以上证据为依据，角色数量不构成通过依据。

【待批】本轮整理与集成无；遗留游戏手感裁定仍见 `PROJECT_STATUS.md`。
