# Robinson

第一人称生存游戏原型。正式工程已整合玩家移动、观察、跳跃、蹲伏、自动迈步，以及物品、E 拾取和 Tab 背包界面。

## 开发入口

**CodeBuddy、Godot 和命令行都以此目录为正式工程根：**

```text
D:\GitProjiect\Godot\114514TheMostGreatServialGame
```

在 CodeBuddy 中打开本目录的 [Robinson.code-workspace](Robinson.code-workspace)，窗口标题为“Robinson 正式主线”，新终端默认进入本仓库。也可直接打开该文件夹。然后阅读 [CodeBuddy 入口](CODEBUDDY.md)、[团队守则](AI_TEAM_RULES.md) 和 [当前状态](PROJECT_STATUS.md)。新任务的编辑、运行、测试和 Git 操作都在此工程进行。

在新窗口开始后续对话；旧窗口中的已有对话仍属于旧工作区，切勿依赖它自动切换工程。首次打开若出现工作区信任或 Godot MCP 项目批准提示，核对正式仓库后在 CodeBuddy 内确认。本机 `.mcp.json` 已保留原 Godot 配置，未纳入 Git；复制配置不等于已确认连接成功。

`D:\Godot-AI-Lab` 保留历史资料和旧工程备份；唯一日常开发入口为本仓库。迁移与清理记录见 [验证记录](docs/validation/2026-10-11-migration.md)。

## 运行

1. 使用已记录的验证版本 **Godot 4.7.2.stable** 打开本目录的 `project.godot`；项目配置为 Godot 4.7、Forward Plus、Jolt Physics。
2. 运行项目（F6 只运行当前场景，完整工程使用 F5）。主场景为 `res://scenes/movement_test.tscn`。
3. 在移动测试场地检查平地、台阶、坡道和跳跃；已知问题与验证边界见 [当前状态](PROJECT_STATUS.md)。

| 操作 | 按键 |
| --- | --- |
| 移动 | W / A / S / D |
| 奔跑 | 按住 Shift |
| 跳跃 | Space，按住时间影响高度 |
| 蹲伏 | 按住 Ctrl，松开请求起身 |
| 观察 | 鼠标移动 |
| 捕获／释放鼠标 | Esc |
| 拾取范围内最近物品 | E |
| 打开／关闭背包 | Tab |

出生点前方有两份木头和一份石头示例。靠近后按 E 拾取，Tab 查看数量；背包放不下整份物品时，物品留在地上。背包目前只读，打开时游戏继续运行。

## 自动验证

```powershell
./tools/run-tests.ps1 -GodotPath 'D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
```

按本机安装位置替换 Godot 路径。默认运行物品、背包、拾取、界面和移动基线五组测试，当前共 389 项断言通过；原始证据、边界及分组复跑方式见 [验证记录](docs/validation/2026-10-11-migration.md)。自动验证不代表真人手感验收，已知玩家问题仍见状态页。

## 文档分工

| 文件 | 用途 |
| --- | --- |
| [CODEBUDDY.md](CODEBUDDY.md) | 执行入口与工作区定位 |
| [AI_TEAM_RULES.md](AI_TEAM_RULES.md) | 正式团队规则与决策权限 |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | 当前任务、已知问题、证据和下一步 |
| [PLAYER_SYSTEMS.md](PLAYER_SYSTEMS.md) | PLAYER-04.3 系统说明与历史记录；最新状态以状态页为准 |

