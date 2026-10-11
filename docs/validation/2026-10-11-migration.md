# 旧工程分批迁移验证

日期：2026-10-11。唯一正式工程为本仓库。引擎：Godot 4.7.2.stable.steam.ed1daf0bf；场景测试使用 60Hz。

迁移前完整备份位于 `D:/Godot-AI-Lab/archive/2026-10-11-robinson-before-integration.zip`，139 个文件逐项 SHA256 验证一致；清单位于同名 `.manifest.json`。旧玩家控制器不覆盖当前 PLAYER-04.3。

## 第一批：物品与背包

- 迁入四个物品定义、ItemStack、Inventory、InventoryManager 及测试，配置 Autoload。
- 修复非法请求和库存快照可改写原数据的问题；增加无副作用容量预检，供整批拾取使用。
- 实际执行 ITEM-01：87 PASS / 0 FAIL；INVENTORY-01：146 PASS / 0 FAIL。
- 原始输出见 `migration/items.log`、`migration/inventory.log`、`migration/data-import.log`。
- 运行器要求退出码、完整汇总和无项目错误同时通过，缺失汇总也算失败；Windows 根证书存储访问提示独立于离线游戏测试。

复跑第一批：

```powershell
./tools/run-tests.ps1 -GodotPath 'D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -Suite data
```

每次运行先导入，输出保存在 `.godot/test-results`。Godot 安装位置不同则替换 `-GodotPath`。

## 第二批：拾取

- 数据批提交：`b81287d`。
- 将三件示例物作为可复用 PickupDemo 接入正式主场景和基础世界；保留原有地形和玩家控制器，仅加入玩家分组与 E 绑定。
- 修复极近距离的优先次序及容量不足时库存堆分布被改变的问题。失败拾取不改数量、顺序，不发布 changed。
- 正式主场景实际输入测试 INTERACTION-01：72 PASS / 0 FAIL，覆盖等距、近似等距、两堆满包、恰好容纳、重复输入和范围退出。
- 原始输出：`migration/interaction.log`。复跑命令同上，使用 `-Suite interaction`。

## 第三批：背包界面与组合回归

- 拾取批提交：`a64610b`。
- 原只读背包界面接入两个世界场景，Tab 切换显示。UI-01：66 PASS / 0 FAIL，覆盖满 20 格的文本和布局边界、E 拾取后的实时显示、Tab 重复与释放输入。
- 新增可复跑移动基线：18 PASS / 0 FAIL，验证真实主场景中的走、跑、满跳、蹲伏和 0.15m 迈步。原玩家脚本与参数保留。
- 最终五组一起运行：87 + 146 + 72 + 66 + 18 = **389 PASS / 0 FAIL**。各进程退出码均为 0，汇总完整，无项目脚本或资源错误。
- 正式默认入口 240 帧、基础世界 120 帧启动检查均正常退出，无项目错误，见 `migration/main-smoke.log` 与 `migration/world-smoke.log`。
- 原始输出：`migration/items.log`、`inventory.log`、`interaction.log`、`ui.log`、`movement.log`，导入为 `final-import.log`，均位于相同目录。
- 复跑所有测试省略 `-Suite`，或使用 `-Suite all`；分组可选 data / interaction / ui / movement。
- 自动检查不等于真人手感和视觉验收。此前确认的迈步中跳跃、空中蹲伏过渡问题未修复，不属于 18 项移动基线的通过范围。

## 清理闸门

清理仅针对 `D:/Godot-AI-Lab/robinson`，保留 Lab 中的历史计划、交接文件和完整 ZIP。提交全部功能后，再复核备份和旧目录文件清单，确认无未迁移的独有源文件才执行清理。

独有文件盘点：139 个文件中有 98 个 `.godot` 缓存；其余 41 个均在正式仓库有对应路径，27 个逐字相同、14 个经核对修改或由正式版本取代。逐项源与目标 SHA256 见 `migration/source-file-audit.json`。

14 个差异的处理：Git 属性和忽略规则沿用正式仓库；旧 PLAYER-01 由 PLAYER-04.3 取代；工程配置选择性合入 Autoload/E/Tab；玩家场景加入分组；旧世界示例抽为可复用场景接入两个世界；库存和拾取按本记录修复；UI 脚本只更新入口说明；库存、拾取及 UI 测试保留并扩展，两份测试场景改用正式主入口。没有遗漏独有源资产。
