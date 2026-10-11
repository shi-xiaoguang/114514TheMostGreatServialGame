# Robinson

第一人称生存游戏原型，已整合移动、观察、跳跃、蹲伏、自动迈步、物品拾取和只读背包界面。进度、已知问题与验证结论统一见 [当前状态](PROJECT_STATUS.md)。

## 目录

```text
game/                      Godot 游戏本体：project.godot、场景、资源、脚本、回归测试
workflow/                  Codex / CodeBuddy 共用技能、工具与上游来源记录
docs/validation/           可复查验证记录与原始证据
docs/history/              旧规格和规则原文（不作为当前指令）
Robinson.code-workspace    单一 Git 工作区
```

在 Codex 或 CodeBuddy 中打开本仓库根目录；CodeBuddy 也可打开 [Robinson.code-workspace](Robinson.code-workspace)。Godot 打开 **[game/project.godot](game/project.godot)**。`res://` 始终对应 `game/`，工具库中的示例工程不属于游戏。

AI 执行入口：[AGENTS.md](AGENTS.md) → [CODEBUDDY.md](CODEBUDDY.md) → [团队守则](AI_TEAM_RULES.md) → [当前状态](PROJECT_STATUS.md)。

## 首次设置与日常使用

需要 PowerShell 7.2+、Python 3.10+、Git 和 Godot。已验证引擎版本为 Godot 4.7.2.stable；项目使用 Forward Plus 和 Jolt Physics。

```powershell
# 新检出或迁移电脑后执行；按实际安装位置替换 Godot 路径。
./workflow/scripts/setup-workspace.ps1 -GodotPath 'D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'

# 打开游戏编辑器；加 -Run 直接运行游戏。
./workflow/scripts/open-game.ps1

# 重跑全部自动测试。
./workflow/scripts/run-tests.ps1

# 检查目录、上游完整性、技能适配与资源引用。
python ./workflow/scripts/validate-workspace.py --require-native-links
```

工作区任务菜单也提供设置、编辑器、运行、回归和结构检查。Godot 路径只保存于本机忽略文件；也可逐次传入 `-GodotPath` 或设置 `GODOT_PATH`。新建 Codex / CodeBuddy 会话后刷新技能目录。集成原理、按需选技能和更新方法见 [工作流说明](workflow/README.md)。

## 操作

| 操作 | 按键 |
| --- | --- |
| 移动 / 观察 | W、A、S、D / 鼠标 |
| 奔跑 | 按住 Shift |
| 跳跃 | Space，按住时间影响高度 |
| 蹲伏 | 按住 Ctrl，松开请求起身 |
| 捕获或释放鼠标 | Esc |
| 拾取最近物品 | E |
| 打开或关闭背包 | Tab |

出生点前方有木头和石头；靠近后 E 拾取、Tab 查看数量。背包放不下整份物品时物品留在地上，打开界面时游戏继续运行。
