extends RefCounted
class_name ItemStack
## Robinson —— 物品堆（任务编号 INVENTORY-01：最小背包系统）。
## 绑定对象：由 Inventory 内部创建与持有，不挂在任何场景节点上。
## 职责：只保存"某个物品定义 + 若干数量"，也就是背包里的一格。
##      不承担查找、容量管理与增删策略——那三种职责全部属于 Inventory。
## 封装约定：数量保存在私有字段 _count 中，只能经 add() / remove() / create() 修改；
##          外部读取一律走 get_count()，避免调用者绕过 max_stack 上限直接改数。
## 范围声明：本阶段不含 UI、拾取、制作、装备、消耗与存档。

# ==================== 状态 ====================

## 本堆引用的物品定义：只引用不复制，因此定义改动后所有堆自动保持一致。
var definition: ItemDefinition = null

## 本堆当前数量：私有约定字段，只允许本类方法写入，外部请用 get_count() 读取。
var _count: int = 0

# ==================== 构造 ====================

## 创建一个物品堆：初始数量会被夹取到 0 ~ definition.max_stack 之间。
static func create(item_definition: ItemDefinition, amount: int = 1) -> ItemStack:
	# 先建空堆，再经受控方法写入数量，使上限夹取逻辑只有 add() 一处实现。
	var stack: ItemStack = ItemStack.new()
	# 记录物品定义：定义为空时后续数量操作都会安全地返回 0。
	stack.definition = item_definition
	# 用 add() 写入初始数量，放不下的部分会被忽略。
	stack.add(amount)
	# 返回完成初始化的堆。
	return stack

# ==================== 受控数量操作 ====================

## 增加数量：返回实际增加的数量，放不下的部分不改变本堆状态。
func add(amount: int) -> int:
	# 零或负数不构成有效增加，直接返回 0 且不改变状态。
	if amount <= 0:
		return 0
	# 缺少物品定义时无法判断上限，按"一点也放不下"处理。
	if definition == null:
		return 0
	# 实际增加量取"请求量"与"本堆剩余空间"中的较小值。
	var added: int = mini(amount, space_left())
	# 写入私有数量字段：这是全工程唯一修改数量的入口之一。
	_count += added
	# 返回实际增加量，供 Inventory 判断是否还有剩余。
	return added

## 减少数量：返回实际减少的数量，数量不会被减到 0 以下。
func remove(amount: int) -> int:
	# 零或负数不构成有效减少，直接返回 0 且不改变状态。
	if amount <= 0:
		return 0
	# 实际减少量取"请求量"与"当前数量"中的较小值，保证不会出现负数。
	var removed: int = mini(amount, _count)
	# 写入私有数量字段：这是全工程唯一减少数量的入口之一。
	_count -= removed
	# 返回实际减少量，供 Inventory 判断是否已扣够。
	return removed

# ==================== 只读查询 ====================

## 取当前数量：外部读取本堆数量的唯一入口。
func get_count() -> int:
	return _count

## 判断本堆是否已空：空堆由 Inventory 负责清理，本类不做删除。
func is_empty() -> bool:
	return _count <= 0

## 判断本堆是否已满：达到物品定义的单堆上限即视为满。
func is_full() -> bool:
	# 缺少物品定义时按"不可再放"处理，避免把数量加到无上限。
	if definition == null:
		return true
	# 当前数量达到单堆上限即为满。
	return _count >= definition.max_stack

## 取本堆还能再放多少个：已满或缺少定义时返回 0。
func space_left() -> int:
	# 缺少物品定义时无法判断上限，返回 0 表示不可再放。
	if definition == null:
		return 0
	# 用 maxi 兜底，避免上限被配置成小于当前数量时返回负数。
	return maxi(definition.max_stack - _count, 0)
