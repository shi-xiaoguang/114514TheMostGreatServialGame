extends Node
## Robinson —— 背包全局入口（任务编号 INVENTORY-01：最小背包系统）。
## 绑定对象：作为 Autoload 单例挂载，单例名 InventoryManager，
##          脚本路径 res://scripts/inventory/inventory_manager.gd（见 project.godot 的 [autoload] 段）。
## 职责：只做"全局访问入口"——持有一个玩家背包实例，并提供派生独立背包的方法，
##      供未来的拾取、制作、箱子 / NPC / 储物系统与界面统一取用同一个入口。
## 刻意不写 class_name：Godot 4 中 Autoload 单例名与同名 class_name 会冲突。
## 边界声明：本文件不承载任何业务逻辑——不做拾取判定、不做配方、不做装备、不做消耗、不做存档。
## 范围声明：本阶段不订阅任何输入、不创建界面，也不改动玩家移动系统（PLAYER-04.3 已冻结）。

# ==================== 状态 ====================

## 玩家背包：本项目唯一的玩家背包实例，任何系统都通过本单例访问它。
var inventory: Inventory = null

# ==================== 生命周期 ====================

## 单例入树后创建玩家背包：只创建一次，之后全程复用同一实例。
func _ready() -> void:
	# 用 Inventory 自身的默认容量创建玩家背包，容量数值不在这里重复配置。
	inventory = Inventory.new()

# ==================== 公共方法 ====================

## 派生一个与玩家背包同构的独立背包：供未来的箱子 / NPC / 储物容器复用同一套逻辑。
func create_inventory(capacity: int = Inventory.DEFAULT_CAPACITY) -> Inventory:
	# 每次调用都返回全新实例，各容器之间互不影响。
	var new_inventory: Inventory = Inventory.new()
	# 允许调用方指定格子容量，默认沿用 Inventory 的默认值。
	new_inventory.capacity = capacity
	# 返回新背包，调用方自行持有。
	return new_inventory
