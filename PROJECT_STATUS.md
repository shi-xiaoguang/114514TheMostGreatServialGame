# Robinson 当前状态

更新日期：2026-10-11（Asia/Shanghai）。这是唯一当前状态入口；旧计划、规格和日志仅作为历史证据。

## 本次授权与工程

- 【事实】主创授权：最后整理与优化，完整接入 `bgrenat/godot-game-dev-studio`，兼容 Codex 和 CodeBuddy，将游戏本体与工作流分开，废除冗余与混乱。
- 【事实】工作区 / Git 根仍为 `D:\GitProjiect\Godot\114514TheMostGreatServialGame`；**Godot 工程根改为 `game/`**，入口 `game/project.godot`，主场景 `res://scenes/movement_test.tscn`。
- 【事实】技能与工具统一位于 `workflow/`。工作区入口为 `AGENTS.md` → `CODEBUDDY.md` → 当前守则 v0.3 与本页；初始化、启动、测试和校验统一在 `workflow/scripts/`。
- 【事实】原游戏 43 个文件整体迁移，保留原相对路径、UID 和用户未提交的配置序列化 / 玩家文件空行改动。逐文件指纹见 [搬迁清单](docs/validation/studio-integration/game-move-manifest.json)。本轮未改玩法或参数。

## 工作流整合

- 【事实】上游固定提交 `9e2b2beaf0bc7ba2e27a40326d058ff2c7a619a9`，完整 3124 个文件及许可证保存在 `workflow/vendor/godot-game-dev-studio/`。校验和锁定于 `workflow/upstream-lock.json`，没有嵌套 Git 仓库。
- 【事实】已建立覆盖 189 个技能的 `workflow/skills-index.json` 和轻量适配生成器。上游索引只有 96 条 / 95 个唯一名称，遗漏 94 个技能目录；一个源技能名称冲突在项目适配层修正，原文不改。
- 【事实】Codex `.agents/skills` 与 CodeBuddy `.codebuddy/skills` 通过初始化脚本共享同一份 `workflow/skills` 适配层；生成入口与本机设置不提交 Git，新检出后重建。
- 【事实】已合并重复工作流规则；原 v0.2.1 与 PLAYER 系统说明归入 `docs/history/`。旧“测试后删除 tests”要求已废止，正式回归保留在 `game/tests/`。
- 【事实】测试运行器改为每次独占日志目录，带进程超时与结果汇总。游戏示例资源和第三方参考代码没有混入 `game/`。
- 【事实】工作区与原生入口检查 6/6 通过；从 Git 暂存内容导出的全新副本也已完成适配生成、初始化和原生入口检查。当前工作流为已实现、已验证状态，详细证据与客户端边界见下方验证记录。

## 系统与验证

| 系统 / 检查 | 当前结论 |
| --- | --- |
| 物品 | ITEM-01：87/87 通过 |
| 背包数据 | INVENTORY-01：146/146 通过 |
| 拾取 | INTERACTION-01：72/72 通过 |
| 只读背包界面 | UI-01：66/66 通过 |
| 移动基线 | MOVEMENT-BASELINE：18/18 通过 |
| 整体回归 | 本次迁移至 `game/` 后实际运行，389/389 通过 |
| 场景加载 | 主场景 240 帧、基础世界 120 帧冒烟通过 |

【事实】本次运行使用 Godot `4.7.2.stable.steam.ed1daf0bf`，证据见 [运行汇总](docs/validation/studio-integration/runtime-verified/summary.json)。第一次沙箱运行因编辑器设置及用户目录写入受限而失败，原日志保留在 `docs/validation/studio-integration/runtime/`；取得本机权限后完整重跑通过，未改写失败记录。

【事实】完整整合检查、客户端加载边界和复跑说明见 [本轮验证记录](docs/validation/2026-10-11-studio-integration.md)。配置与链接可读性不等于当前聊天已刷新技能，也不等于应用内 MCP 已连接；新会话加载和真人体验验收单独确认。

## 已知游戏问题与待定参数

| 项目 | 当前边界 |
| --- | --- |
| 迈步中起跳 | 先前已复现剩余迈步轨迹压低跳跃，本轮整理不修改控制器，仍待修复 |
| 蹲伏过渡中离地 | 先前已复现空中姿态继续变化，本轮未修复 |
| 减速 / 迈步松键行为 | 当前指数减速、松键后继续完成迈步；是否改变体验需主创裁定 |
| 手感参数 | `walk_speed=3.2`、`run_speed=5.2`、`max_jump_height=0.915` 仍为回归基线，未定稿；配置值不等于实测高度 |
| 真人试玩 | 尚未进行手感与视觉验收；自动测试不替代此项 |

【事实】历史 PLAYER 的 `76/76`、`19/19`、`32/32` 记录保留在 [历史说明](docs/history/PLAYER_SYSTEMS.md)，相关旧探针没有保留，不作为当前完整可复跑测试套件。

## 历史与后续

- 旧 `D:\Godot-AI-Lab\robinson` 已在前轮迁移后清理；139 文件的完整 ZIP 与 SHA256 清单位于 `D:\Godot-AI-Lab\archive`。历史迁移证据见 [迁移记录](docs/validation/2026-10-11-migration.md)。
- 后续从本仓库根开始任务，运行 Godot 时明确指向 `game/`；维护技能时只改项目适配层或按固定提交更新上游快照。
- 本轮收尾方式：验证后保存为本地 Git 提交，不推送远端。
- 【待批】本轮工作流整理无。后续游戏手感参数、减速和迈步松键行为仍由主创决定。
