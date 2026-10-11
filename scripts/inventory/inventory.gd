extends RefCounted
class_name Inventory
## Robinson —— 背包（任务编号 INVENTORY-01：最小背包系统）。
## 绑定对象：不绑定任何节点——玩家背包由 InventoryManager（Autoload）持有；
##          未来的箱子 / NPC / 储物容器由 InventoryManager.create_inventory() 派生，二者结构完全相同。
## 职责：只负责背包自身的逻辑——增（add_item）、删（remove_item）、
##      查（has_item / get_item_count）、堆叠（按 ItemDefinition.max_stack 先补堆再开新堆）、
##      容量（capacity 以"堆数"为单位，即格子数）。
## 数据流：内部用 Array[ItemStack] 保存格子；每次内容真的发生变化后发出一次 changed 信号，
##        供未来的界面刷新与自动存档订阅。
## 范围声明：本阶段不含 UI、拾取、制作、装备、消耗、重量限制与完整存档实现；
##          代码中不按物品 id 写任何行为分支——需要区分用途时应由调用方查询 ItemDefinition.tags。

# ==================== 信号 ====================

## 数据变更通知：任意一次真的改变了背包内容的操作后触发一次。
signal changed

# ==================== 常量与状态 ====================

## 默认格子容量：以"堆数"计，不是物品总件数；主创 INVENTORY-01 裁决为 20。
const DEFAULT_CAPACITY: int = 20

## 格子容量（最多容纳多少堆）：本阶段不做重量系统，容量只看堆数。
var capacity: int = DEFAULT_CAPACITY

## 内部格子数组：外部需要枚举时请用 get_stacks() 取副本，避免绕过本类直接改写内部状态。
var _stacks: Array[ItemStack] = []

# ==================== 公共方法：增 ====================

## 添加物品：返回"未能放入的剩余量"，返回 0 表示全部放入。
## 规则（主创已批准）：先补满已有未满的同类堆，仍有剩余且未达容量上限时再开新堆。
func add_item(definition: ItemDefinition, amount: int = 1) -> int:
	# 非正数请求始终是空操作，即使同时传入空定义也不能返回负剩余量。
	if amount <= 0:
		return 0
	# 缺少物品定义时无法确定单堆上限与物品标识，按"一件都放不进去"处理。
	if definition == null:
		push_warning("[Inventory] add_item 收到空的 ItemDefinition，本次请求已忽略。")
		return amount
	# 拒绝缺失 id 或非法堆叠上限，避免把不可识别的物品写入库存。
	if not definition.is_valid():
		push_warning("[Inventory] add_item 收到无效的 ItemDefinition，本次请求已忽略。")
		return amount
	# 未放入量：随补堆与开新堆逐步递减，最终作为返回值。
	var remaining: int = amount
	# 是否真的改动了内容：决定本次要不要发 changed 信号。
	var mutated: bool = false
	# 第一轮：按格子顺序补满已有的未满同类堆。
	for stack: ItemStack in _stacks:
		# 已经放完就不再继续遍历。
		if remaining <= 0:
			break
		# 只补同类物品的堆：不同物品不允许合并。
		if not _is_same_item(stack, definition.id):
			continue
		# 已满的堆跳过，交给第二轮开新堆处理。
		if stack.is_full():
			continue
		# 实际放入量由 ItemStack 按上限夹取；返回 0 说明该堆未发生任何变化。
		var added: int = stack.add(remaining)
		if added > 0:
			remaining -= added
			mutated = true
	# 第二轮：仍有剩余且格子未满时开新堆，直到放完或格子用尽。
	while remaining > 0 and _stacks.size() < capacity:
		# 新堆的初始数量同样受单堆上限约束，超出部分留给下一轮。
		var new_stack: ItemStack = ItemStack.create(definition, remaining)
		# 取出夹取后的实际数量，作为本轮放入量。
		var placed: int = new_stack.get_count()
		# 上限配置异常（例如 max_stack 为 0）时放不进任何东西，必须跳出以免死循环。
		if placed <= 0:
			break
		# 只在确实放入后才把新堆并入背包。
		_stacks.append(new_stack)
		remaining -= placed
		mutated = true
	# 只有内容真的变了才通知订阅者，避免无效信号触发界面与存档的无谓工作。
	if mutated:
		changed.emit()
	# 返回未能放入的剩余量，调用方据此决定物品是否继续留在地上。
	return remaining

## 预检整批物品能否放入：只查询容量，不修改库存或发出 changed。
func can_add_item(definition: ItemDefinition, amount: int = 1) -> bool:
	if amount <= 0 or definition == null:
		return false
	if not definition.is_valid():
		return false
	# 已有同类堆可以补入的部分不占新格子，与 add_item 使用同样的物品身份规则。
	var remaining: int = amount
	for stack: ItemStack in _stacks:
		if not _is_same_item(stack, definition.id):
			continue
		remaining -= mini(remaining, stack.space_left())
		if remaining == 0:
			return true
	# 剩余数量必须全部容纳于空格；采用整数向上取整，避免浮点误差与加法溢出。
	if capacity <= _stacks.size():
		return false
	@warning_ignore("integer_division")
	var needed_slots: int = (remaining - 1) / definition.max_stack + 1
	return needed_slots <= capacity - _stacks.size()

# ==================== 公共方法：删 ====================

## 移除物品：返回"实际移除的数量"；库存不足时返回全部库存量。
## 规则：按格子顺序从前往后扣减（先入先出），扣空的格子立即从背包中删除。
func remove_item(id: StringName, amount: int = 1) -> int:
	# 零或负数不构成有效变更，直接返回 0。
	if amount <= 0:
		return 0
	# 未扣减量：随扣减逐步递减。
	var remaining: int = amount
	# 实际移除总量：作为返回值，保证不会超过背包实际拥有量。
	var removed_total: int = 0
	# 正序遍历格子，保证扣减顺序稳定可预测。
	for stack: ItemStack in _stacks:
		# 已经扣够就不再继续遍历。
		if remaining <= 0:
			break
		# 只扣目标物品的堆。
		if not _is_same_item(stack, id):
			continue
		# 实际扣减量由 ItemStack 按当前数量夹取。
		var removed: int = stack.remove(remaining)
		if removed > 0:
			remaining -= removed
			removed_total += removed
	# 统一清理空堆：先选出非空堆再整体替换，避免在遍历过程中修改数组。
	var kept: Array[ItemStack] = []
	for stack: ItemStack in _stacks:
		# 数量归零的格子不再保留，避免背包里出现占格子的空堆。
		if not stack.is_empty():
			kept.append(stack)
	# 用清理后的数组替换内部状态。
	_stacks = kept
	# 至少移除了 1 件才通知订阅者。
	if removed_total > 0:
		changed.emit()
	# 返回实际移除量，制作 / 建造等调用方据此判断扣料是否成功。
	return removed_total

# ==================== 公共方法：查 ====================

## 查询是否拥有指定数量的物品：默认查询 1 件。
func has_item(id: StringName, amount: int = 1) -> bool:
	# 零或负数请求视为"无需拥有"，直接判定为真。
	if amount <= 0:
		return true
	# 数量足够即为真，统计细节交给 get_item_count 实现以保持单一真相来源。
	return get_item_count(id) >= amount

## 查询指定物品的总数量：同一物品可能横跨多个堆，需要逐堆累加。
func get_item_count(id: StringName) -> int:
	# 累加所有同类堆的数量。
	var total: int = 0
	for stack: ItemStack in _stacks:
		# 非目标物品不参与统计。
		if not _is_same_item(stack, id):
			continue
		total += stack.get_count()
	# 返回总数；背包中没有该物品时自然返回 0。
	return total

## 取所有格子的快照：数组与数量各自独立；物品定义仍按只读约定共享。
func get_stacks() -> Array[ItemStack]:
	# 仅复制数组仍会暴露内部 ItemStack，调用者可绕过 changed 直接增减数量。
	var snapshots: Array[ItemStack] = []
	for stack: ItemStack in _stacks:
		snapshots.append(ItemStack.create(stack.definition, stack.get_count()))
	return snapshots

## 取当前已占用的格子数（堆数）：供容量判断、调试与未来的界面显示使用。
func get_used_slots() -> int:
	return _stacks.size()

## 判断背包格子是否已被占满：占满后新物品无法再开新堆。
func is_full() -> bool:
	return _stacks.size() >= capacity

# ==================== 公共方法：清空与调试 ====================

## 清空背包：一次性移除所有格子，并且只发出一次 changed 信号。
func clear() -> void:
	# 本来就是空背包时不算变更，避免发出无意义的通知。
	if _stacks.is_empty():
		return
	# 直接替换为新的空数组，不做逐格清理。
	_stacks = []
	# 清空属于一次整体变更，因此只通知一次。
	changed.emit()

## 生成背包内容的多行文本：本阶段没有界面，这是唯一查看背包内容的方式。
func debug_dump() -> String:
	# 每格一行，便于在日志中逐行比对。
	var lines: Array[String] = []
	# 按下标遍历，顺带把格子序号打印出来。
	for index: int in _stacks.size():
		var stack: ItemStack = _stacks[index]
		# 定义缺失属于异常数据，单独标注以便尽早发现资源配置问题。
		if stack.definition == null:
			lines.append("  [%d] <定义缺失> x%d" % [index, stack.get_count()])
			continue
		# 正常格子打印"显示名(id) x数量"，id 便于与资源文件核对。
		lines.append("  [%d] %s(%s) x%d" % [index, stack.definition.get_display_name(), stack.definition.id, stack.get_count()])
	# 末尾补一行汇总：已用格子 / 容量 / 物品总件数。
	lines.append("  已用格子 %d / 容量 %d，共 %d 件" % [_stacks.size(), capacity, _get_total_count()])
	# 用换行拼接为多行文本返回。
	return "\n".join(lines)

# ==================== 私有方法 ====================

## 判断某个格子是否属于指定物品：按物品 id 比较，避免调用方按物品名做判断。
func _is_same_item(stack: ItemStack, id: StringName) -> bool:
	# 定义缺失的异常格子不匹配任何 id。
	if stack.definition == null:
		return false
	# 以物品 id 作为唯一标识进行匹配。
	return stack.definition.id == id

## 统计背包内物品总件数：仅用于调试输出的汇总行。
func _get_total_count() -> int:
	# 累加所有格子的数量。
	var total: int = 0
	for stack: ItemStack in _stacks:
		total += stack.get_count()
	# 返回总件数。
	return total
