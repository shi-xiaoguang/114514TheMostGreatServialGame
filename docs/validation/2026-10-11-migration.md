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

## 后续批次

拾取与背包界面正在迁移，尚未验证。旧工程清理必须在全量回归和分批 Git 提交完成后执行。
