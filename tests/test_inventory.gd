extends SceneTree
## Robinson —— INVENTORY-01 无头验证脚本（测试专用，非生产代码）。
## 绑定方式：不经场景，直接以资源路径执行：
##   godot --headless --path <工程目录> -s res://tests/test_inventory.gd
## 职责：① 验证 Inventory 的增（add_item）、删（remove_item）、查（has_item / get_item_count）、
##         堆叠（先补未满堆再开新堆）与容量（capacity 按堆数计）五组行为；
##       ② 验证 ItemStack 的数量封装（外部只能用 get_count / add / remove）；
##       ③ 验证 changed 信号只在内容真的变化时发出一次；
##       ④ 探测 InventoryManager Autoload 单例的可达性，并如实报告结论；
##       ⑤ 逐条输出 PASS/FAIL，并以退出码汇报总结果（0 = 全部通过，1 = 存在失败）。
## 执行时机：不依赖 Autoload 的用例在 _init() 内立即执行；Autoload 探测必须等引擎完成单例挂载，
##          因此挂到首个处理帧执行，并由"收尾闸门"保证只执行一次。
## 范围声明：本阶段不验证 UI、拾取、制作、装备、消耗与存档。

# ==================== 常量 ====================

## 物品定义资源目录：测试输入数据统一从这里取。
const ITEM_DIR: String = "res://resources/items/"

# ==================== 运行时状态 ====================

## 通过的断言条数。
var _passed: int = 0

## 失败的断言条数：大于 0 时以退出码 1 结束，便于命令行判定。
var _failed: int = 0

## 收尾闸门：保证"探测 Autoload + 打印汇总 + 退出"这套收尾流程只执行一次。
var _finished: bool = false

## 测试输入：木头定义（Material，单堆上限 99）。
var _wood: ItemDefinition = null

## 测试输入：石头定义（Material，单堆上限 99）。
var _stone: ItemDefinition = null

## 测试输入：浆果定义（Consumable，单堆上限 20）。
var _berry: ItemDefinition = null

## 测试输入：石斧定义（Tool，单堆上限 1，用于验证不可堆叠）。
var _stone_axe: ItemDefinition = null

# ==================== 主入口 ====================

## 脚本被实例化后立即执行不依赖 Autoload 的全部用例。
func _init() -> void:
	# 打印引擎版本，作为"本次确实运行过"的现场证据。
	print("[INVENTORY-01] 无头验证开始；引擎版本 = ", Engine.get_version_info()["string"])
	# 先加载四份物品定义，作为后续所有用例的输入数据。
	_wood = _load_definition("wood.tres")
	_stone = _load_definition("stone.tres")
	_berry = _load_definition("berry.tres")
	_stone_axe = _load_definition("stone_axe.tres")
	# 资源缺失已经计为失败，直接结束，避免空引用使后续测试误报或中断。
	if _wood == null or _stone == null or _berry == null or _stone_axe == null:
		_finished = true
		_finish()
		return
	# 第一组用例是纯类验证，在 _init 内直接执行，保证一定跑到。
	_run_unit_tests()
	# 第二组用例依赖 Autoload 单例，挂到首个处理帧再执行。
	process_frame.connect(_on_frame, CONNECT_ONE_SHOT)

## 首个处理帧的回调：先探测 Autoload 单例，再做收尾。
func _on_frame() -> void:
	# 收尾闸门：process_frame 与 _process 两条路径都可能触发，这里保证只执行一次。
	if _finished:
		return
	_finished = true
	# 探测 Autoload 单例可达性并验证入口可用。
	_verify_autoload()
	# 打印汇总并按失败条数退出。
	_finish()

## MainLoop 的处理帧虚拟方法：作为 process_frame 之外的第二条触发路径，避免极端情况下测试卡死。
func _process(_delta: float) -> bool:
	# 复用同一套收尾流程，由内部闸门保证不会重复执行。
	_on_frame()
	# _finish() 用 quit(code) 保留明确退出码，不另行请求无条件成功退出。
	return false

# ==================== 私有方法：断言与工具 ====================

## 记录一条布尔断言并打印结论。
func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		print("[FAIL] ", label)

## 记录一条"实测值 vs 预期值"断言；不一致时把两者都打印出来，便于直接定位差异。
func _check_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		print("[PASS] %s = %s" % [label, str(actual)])
	else:
		_failed += 1
		print("[FAIL] %s：实测 = %s，预期 = %s" % [label, str(actual), str(expected)])

## 按文件名加载物品定义资源，并显式转换为 ItemDefinition 类型。
func _load_definition(file_name: String) -> ItemDefinition:
	# 以 res:// 路径加载资源，避免依赖全局类缓存之外的任何机制。
	var resource: Resource = load(ITEM_DIR + file_name)
	# 显式安全转换：失败时返回空值，由调用方决定后续处理。
	var definition: ItemDefinition = resource as ItemDefinition
	# 加载或转换失败都必须记为失败，避免用例"静默跳过"却看起来通过。
	_check(ITEM_DIR + file_name + " 可加载并转换为 ItemDefinition", definition != null)
	# 返回转换结果。
	return definition

## 打印汇总并按失败条数决定退出码。
func _finish() -> void:
	print("[INVENTORY-01] 汇总：PASS = %d，FAIL = %d" % [_passed, _failed])
	# 存在失败时返回非零退出码，使命令行可据此判定不通过。
	quit(1 if _failed > 0 else 0)

# ==================== 第一组：纯类单元验证 ====================

## 顺序执行全部不依赖 Autoload 的用例。
func _run_unit_tests() -> void:
	_case_initial_state()
	_case_add_and_print()
	_case_top_up_existing_stack()
	_case_capacity_limit()
	_case_unstackable()
	_case_remove_overflow()
	_case_queries()
	_case_invalid_requests()
	_case_clear()
	_case_changed_signal()
	_case_get_stacks_is_copy()
	_case_item_stack_boundaries()
	_case_zero_capacity()
	_case_can_add_item()

## 用例 1：新背包的初始状态与默认容量。
func _case_initial_state() -> void:
	print("[INVENTORY-01] ---- 用例 1：新背包初始状态 ----")
	var inventory: Inventory = Inventory.new()
	# 默认容量常量本身单独核对一次，防止数值被无意改动而无人发现。
	_check_eq("DEFAULT_CAPACITY 常量", Inventory.DEFAULT_CAPACITY, 20)
	# 新背包的容量应等于默认值。
	_check_eq("默认 capacity", inventory.capacity, Inventory.DEFAULT_CAPACITY)
	# 空背包的格子数与各类查询结果。
	_check_eq("初始已用格子", inventory.get_used_slots(), 0)
	_check("初始 is_full() = false", not inventory.is_full())
	_check("初始 get_stacks() 为空", inventory.get_stacks().is_empty())
	_check_eq("初始 get_item_count(wood)", inventory.get_item_count(&"wood"), 0)
	_check("初始 has_item(wood) = false", not inventory.has_item(&"wood"))
	# 打印空背包内容，确认 debug_dump 在空状态下也能正常输出。
	print(inventory.debug_dump())

## 用例 2：添加木头 250 件（单堆上限 99）并打印背包内容。
func _case_add_and_print() -> void:
	print("[INVENTORY-01] ---- 用例 2：添加木头 x250（单堆上限 99） ----")
	var inventory: Inventory = Inventory.new()
	# 250 件应全部放入，因此返回的剩余量为 0。
	_check_eq("add_item(wood, 250) 剩余量", inventory.add_item(_wood, 250), 0)
	# 总数应为 250，堆数应为 3（99 / 99 / 52）。
	_check_eq("木头总数", inventory.get_item_count(&"wood"), 250)
	_check_eq("已用格子", inventory.get_used_slots(), 3)
	# 逐堆核对数量，确认是按单堆上限切分的。
	var stacks: Array[ItemStack] = inventory.get_stacks()
	# 堆数不足时跳过逐堆核对，避免空引用中断整个测试。
	if stacks.size() >= 3:
		_check_eq("第 1 堆数量", stacks[0].get_count(), 99)
		_check_eq("第 2 堆数量", stacks[1].get_count(), 99)
		_check_eq("第 3 堆数量", stacks[2].get_count(), 52)
		# 第 3 堆未满，说明"未满"判定可用。
		_check("第 3 堆 is_full() = false", not stacks[2].is_full())
		_check_eq("第 3 堆 space_left()", stacks[2].space_left(), 47)
	# 打印背包内容：本阶段没有界面，这是唯一的"查看背包"方式。
	print(inventory.debug_dump())

## 用例 3：再次添加时先补满已有未满堆，而不是直接开新堆。
func _case_top_up_existing_stack() -> void:
	print("[INVENTORY-01] ---- 用例 3：先补满未满堆再开新堆 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_wood, 250)
	# 第 3 堆为 52，补 47 应刚好填满到 99，且不新增格子。
	_check_eq("add_item(wood, 47) 剩余量", inventory.add_item(_wood, 47), 0)
	_check_eq("木头总数", inventory.get_item_count(&"wood"), 297)
	_check_eq("已用格子（不应新增堆）", inventory.get_used_slots(), 3)
	var stacks: Array[ItemStack] = inventory.get_stacks()
	# 堆数异常时跳过逐堆核对。
	if stacks.size() >= 3:
		_check_eq("第 3 堆已补满", stacks[2].get_count(), 99)
	# 三堆都满了，再补 1 件必须开新堆。
	_check_eq("add_item(wood, 1) 剩余量", inventory.add_item(_wood, 1), 0)
	_check_eq("已用格子（应新增 1 堆）", inventory.get_used_slots(), 4)
	print(inventory.debug_dump())

## 用例 4：容量按"堆数"计，格子用尽后返回未能放入的剩余量。
func _case_capacity_limit() -> void:
	print("[INVENTORY-01] ---- 用例 4：容量上限（capacity = 2 堆） ----")
	var inventory: Inventory = Inventory.new()
	# 把容量压到 2 堆，便于快速触发上限。
	inventory.capacity = 2
	# 前两种物品各占一格，都放得进去。
	_check_eq("放入木头 x5 剩余量", inventory.add_item(_wood, 5), 0)
	_check_eq("放入石头 x5 剩余量", inventory.add_item(_stone, 5), 0)
	# 两格占满后，背包整体应判定为满。
	_check("is_full() = true", inventory.is_full())
	# 第三种物品应一件都放不进去，返回值等于请求量。
	_check_eq("放入浆果 x3 剩余量（应为 3）", inventory.add_item(_berry, 3), 3)
	# 浆果不应产生任何库存，堆数保持 2。
	_check_eq("浆果总数", inventory.get_item_count(&"berry"), 0)
	_check_eq("已用格子", inventory.get_used_slots(), 2)
	# 容量只限制"开新堆"：已存在的同类物品仍可补进未满堆。
	_check_eq("补同类物品石头 x10 剩余量", inventory.add_item(_stone, 10), 0)
	_check_eq("石头总数", inventory.get_item_count(&"stone"), 15)
	print(inventory.debug_dump())

## 用例 5：单堆上限为 1 的物品不可堆叠，每件各占一格。
func _case_unstackable() -> void:
	print("[INVENTORY-01] ---- 用例 5：不可堆叠物品（石斧 max_stack = 1） ----")
	var inventory: Inventory = Inventory.new()
	# 3 件石斧应全部放入并占满 3 格。
	_check_eq("add_item(stone_axe, 3) 剩余量", inventory.add_item(_stone_axe, 3), 0)
	_check_eq("石斧总数", inventory.get_item_count(&"stone_axe"), 3)
	_check_eq("已用格子", inventory.get_used_slots(), 3)
	var stacks: Array[ItemStack] = inventory.get_stacks()
	# 堆数异常时跳过逐堆核对。
	if stacks.size() >= 3:
		_check_eq("第 1 堆数量", stacks[0].get_count(), 1)
		_check_eq("第 2 堆数量", stacks[1].get_count(), 1)
		_check_eq("第 3 堆数量", stacks[2].get_count(), 1)
		# 单堆上限为 1 时，每堆都应立即处于已满状态。
		_check("第 1 堆 is_full() = true", stacks[0].is_full())
		_check_eq("第 1 堆 space_left()", stacks[0].space_left(), 0)
	print(inventory.debug_dump())

## 用例 6：移除量超过库存时返回实际移除量，并清理掉空堆。
func _case_remove_overflow() -> void:
	print("[INVENTORY-01] ---- 用例 6：超量移除与空堆清理 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_wood, 250)
	# 请求移除 300 件但只有 250 件，应返回 250 而不是 300。
	_check_eq("remove_item(wood, 300) 实际移除量", inventory.remove_item(&"wood", 300), 250)
	_check_eq("木头总数", inventory.get_item_count(&"wood"), 0)
	_check_eq("已用格子（空堆应被删除）", inventory.get_used_slots(), 0)
	# 重新装料后只移除一部分，验证剩余数量与堆数。
	inventory.add_item(_wood, 250)
	_check_eq("remove_item(wood, 100) 实际移除量", inventory.remove_item(&"wood", 100), 100)
	_check_eq("木头剩余总数", inventory.get_item_count(&"wood"), 150)
	# 99 / 99 / 52 从前向后扣 100 后：第 1 堆清空被删，剩下 98 与 52，共 2 堆。
	_check_eq("已用格子（应为 2 堆）", inventory.get_used_slots(), 2)
	print(inventory.debug_dump())

## 用例 7：查询类方法的边界（数量不足、物品不存在、默认数量）。
func _case_queries() -> void:
	print("[INVENTORY-01] ---- 用例 7：查询边界 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_stone, 40)
	# 数量刚好足够时应为真，多 1 件则为假。
	_check("has_item(stone, 40) = true", inventory.has_item(&"stone", 40))
	_check("has_item(stone, 41) = false", not inventory.has_item(&"stone", 41))
	# 默认数量为 1 件。
	_check("has_item(stone) 默认查 1 件 = true", inventory.has_item(&"stone"))
	# 背包内不存在的物品一律为假。
	_check("has_item(wood) = false", not inventory.has_item(&"wood"))
	_check("has_item(不存在 id) = false", not inventory.has_item(&"no_such_item"))
	# 不存在物品的数量查询应为 0，而不是报错。
	_check_eq("get_item_count(wood)", inventory.get_item_count(&"wood"), 0)
	_check_eq("get_item_count(不存在 id)", inventory.get_item_count(&"no_such_item"), 0)

## 用例 8：非法请求不改变背包状态。
func _case_invalid_requests() -> void:
	print("[INVENTORY-01] ---- 用例 8：非法请求 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_wood, 10)
	# 记录请求前的格子数，用于比对状态是否被改动。
	var slots_before: int = inventory.get_used_slots()
	# 空物品定义：无法判断上限与标识，应返回请求量本身。
	_check_eq("add_item(null, 5) 剩余量（应为 5）", inventory.add_item(null, 5), 5)
	# 零与负数请求：应返回 0 且不改变任何状态。
	_check_eq("add_item(wood, 0) 返回 0", inventory.add_item(_wood, 0), 0)
	_check_eq("add_item(wood, -3) 返回 0", inventory.add_item(_wood, -3), 0)
	_check_eq("add_item(null, -3) 返回 0", inventory.add_item(null, -3), 0)
	_check_eq("add_item(null, 0) 返回 0", inventory.add_item(null, 0), 0)
	var invalid: ItemDefinition = ItemDefinition.new()
	_check_eq("空 id 定义全部拒绝", inventory.add_item(invalid, 5), 5)
	_check_eq("空 id 未产生库存", inventory.get_item_count(&""), 0)
	invalid.id = &"invalid_stack"
	invalid.max_stack = 0
	_check_eq("零堆叠上限定义全部拒绝", inventory.add_item(invalid, 5), 5)
	invalid.max_stack = -1
	_check_eq("负堆叠上限定义全部拒绝", inventory.add_item(invalid, 5), 5)
	_check_eq("remove_item(wood, -1) 返回 0", inventory.remove_item(&"wood", -1), 0)
	_check_eq("remove_item(wood, 0) 返回 0", inventory.remove_item(&"wood", 0), 0)
	# 移除不存在的物品也应是安全空操作。
	_check_eq("remove_item(不存在 id, 5) 返回 0", inventory.remove_item(&"no_such_item", 5), 0)
	# 状态必须与非法请求之前完全一致。
	_check_eq("木头总数未变", inventory.get_item_count(&"wood"), 10)
	_check_eq("已用格子未变", inventory.get_used_slots(), slots_before)

## 用例 9：清空背包后所有查询归零。
func _case_clear() -> void:
	print("[INVENTORY-01] ---- 用例 9：clear() 清空 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_wood, 120)
	inventory.add_item(_stone, 30)
	# 清空前确认确实装了东西，避免"清空了个空背包"的假通过。
	# 木头 120 件按上限 99 切分为 2 堆（99 + 21），石头 30 件另占 1 堆，合计 3 堆。
	_check_eq("清空前已用格子", inventory.get_used_slots(), 3)
	inventory.clear()
	# 清空后格子数与各类计数都应归零。
	_check_eq("清空后已用格子", inventory.get_used_slots(), 0)
	_check_eq("清空后木头总数", inventory.get_item_count(&"wood"), 0)
	_check_eq("清空后石头总数", inventory.get_item_count(&"stone"), 0)
	_check("清空后 is_full() = false", not inventory.is_full())
	_check("清空后 get_stacks() 为空", inventory.get_stacks().is_empty())
	print(inventory.debug_dump())

## 用例 10：changed 信号只在内容真的发生变化时发出一次。
func _case_changed_signal() -> void:
	print("[INVENTORY-01] ---- 用例 10：changed 信号 ----")
	var inventory: Inventory = Inventory.new()
	# 用单元素数组做计数器：GDScript 的 lambda 按值捕获，但数组是引用类型，因此计数有效。
	var counter: Array[int] = [0]
	inventory.changed.connect(func() -> void: counter[0] += 1)
	# 成功添加 1 件：应恰好发出一次。
	inventory.add_item(_wood, 1)
	_check_eq("添加成功后信号次数", counter[0], 1)
	# 零数量请求不构成变更。
	inventory.add_item(_wood, 0)
	_check_eq("零数量请求后信号次数（不变）", counter[0], 1)
	# 空物品定义不构成变更。
	inventory.add_item(null, 1)
	_check_eq("空定义请求后信号次数（不变）", counter[0], 1)
	# 移除不存在的物品不构成变更。
	inventory.remove_item(&"no_such_item", 1)
	_check_eq("无效移除后信号次数（不变）", counter[0], 1)
	# 成功移除 1 件：应再发出一次。
	inventory.remove_item(&"wood", 1)
	_check_eq("移除成功后信号次数", counter[0], 2)
	# 此时背包已空，清空空背包不应发出信号。
	inventory.clear()
	_check_eq("空背包 clear() 后信号次数（不变）", counter[0], 2)
	# 重新装料后清空，应恰好再发出两次（添加一次 + 清空一次）。
	inventory.add_item(_wood, 5)
	inventory.clear()
	_check_eq("加料并清空后信号次数", counter[0], 4)
	# 一次跨多堆的部分放入也只通知一次；满包拒绝和非法输入均不通知。
	inventory.capacity = 2
	_check_eq("两格加入 250 木头剩余 52", inventory.add_item(_wood, 250), 52)
	_check_eq("部分放入后信号次数", counter[0], 5)
	_check_eq("满包拒绝石头", inventory.add_item(_stone, 1), 1)
	inventory.add_item(null, -1)
	inventory.remove_item(&"wood", 0)
	inventory.remove_item(&"wood", -1)
	_check_eq("满包及非法请求后信号次数不变", counter[0], 5)
	_check_eq("批量移除实际为 198", inventory.remove_item(&"wood", 250), 198)
	_check_eq("批量移除只通知一次", counter[0], 6)
	print("  changed 信号总触发次数 = %d" % counter[0])

## 用例 11：get_stacks() 返回副本，外部改写不影响背包内部状态。
func _case_get_stacks_is_copy() -> void:
	print("[INVENTORY-01] ---- 用例 11：get_stacks() 返回副本 ----")
	var inventory: Inventory = Inventory.new()
	inventory.add_item(_wood, 100)
	# 100 件按单堆上限切分为 99 + 1，共 2 格。
	var slots_before: int = inventory.get_used_slots()
	_check_eq("清空前已用格子", slots_before, 2)
	# 清空副本不应影响背包。
	var copy: Array[ItemStack] = inventory.get_stacks()
	copy.clear()
	_check_eq("清空副本后背包已用格子", inventory.get_used_slots(), slots_before)
	_check_eq("清空副本后背包木头总数", inventory.get_item_count(&"wood"), 100)
	# 往副本里追加元素同样不应影响背包。
	var appended: Array[ItemStack] = inventory.get_stacks()
	appended.append(ItemStack.create(_stone, 1))
	_check_eq("改副本后背包已用格子", inventory.get_used_slots(), slots_before)
	_check_eq("改副本后背包石头总数", inventory.get_item_count(&"stone"), 0)
	# 快照初始内容应与背包一致，但其中 ItemStack 的数量也必须相互独立。
	var fresh: Array[ItemStack] = inventory.get_stacks()
	_check_eq("副本元素个数", fresh.size(), slots_before)
	# 元素个数异常时跳过逐堆核对。
	if fresh.size() >= 1:
		_check_eq("副本首堆数量", fresh[0].get_count(), 99)
		var counter: Array[int] = [0]
		inventory.changed.connect(func() -> void: counter[0] += 1)
		fresh[0].remove(99)
		fresh[0].add(5)
		_check_eq("改快照堆数量不改变库存", inventory.get_item_count(&"wood"), 100)
		fresh[0].definition = _stone
		_check_eq("替换快照定义不改变原库存", inventory.get_item_count(&"wood"), 100)
		_check_eq("替换快照定义不产生石头", inventory.get_item_count(&"stone"), 0)
		_check_eq("改快照不触发库存 changed", counter[0], 0)
		var before_remove: Array[ItemStack] = inventory.get_stacks()
		inventory.remove_item(&"wood", 50)
		_check_eq("原库存变化不回写旧快照", before_remove[0].get_count(), 99)
		_check_eq("原库存正常移除", inventory.get_item_count(&"wood"), 50)

## ItemStack 的单堆数量边界不会产生负数量或超出上限。
func _case_item_stack_boundaries() -> void:
	print("[INVENTORY-01] ---- ItemStack 数量边界 ----")
	var stack: ItemStack = ItemStack.create(_wood, 200)
	_check_eq("初始化数量限制在单堆上限", stack.get_count(), 99)
	_check_eq("满堆添加实际为零", stack.add(5), 0)
	_check_eq("负数添加实际为零", stack.add(-1), 0)
	_check_eq("负数移除实际为零", stack.remove(-1), 0)
	_check_eq("超量移除返回实际量", stack.remove(200), 99)
	_check_eq("移除后数量为零", stack.get_count(), 0)
	_check_eq("空堆再次移除为零", stack.remove(1), 0)
	_check("空堆 is_empty", stack.is_empty())
	_check_eq("空堆剩余空间", stack.space_left(), 99)
	_check_eq("空定义创建空堆", ItemStack.create(null, 5).get_count(), 0)
	_check_eq("负初始数量创建空堆", ItemStack.create(_wood, -5).get_count(), 0)

## 零与负容量都不能新增格子，不会丢失请求中的数量。
func _case_zero_capacity() -> void:
	print("[INVENTORY-01] ---- 非正容量边界 ----")
	var inventory: Inventory = Inventory.new()
	inventory.capacity = 0
	_check_eq("零容量全部退回", inventory.add_item(_wood, 5), 5)
	_check_eq("零容量没有新增格子", inventory.get_used_slots(), 0)
	inventory.capacity = -1
	_check_eq("负容量全部退回", inventory.add_item(_wood, 5), 5)
	_check_eq("负容量没有新增格子", inventory.get_used_slots(), 0)

## 整批容量预检供拾取使用，不能出现部分入库、假阳性或副作用。
func _case_can_add_item() -> void:
	print("[INVENTORY-01] ---- 整批容量预检 ----")
	var inventory: Inventory = Inventory.new()
	inventory.capacity = 2
	inventory.add_item(_wood, 194)
	var counter: Array[int] = [0]
	inventory.changed.connect(func() -> void: counter[0] += 1)
	_check("[99,95] 无法完整加入 5 木头", not inventory.can_add_item(_wood, 5))
	_check("[99,95] 可以完整加入 4 木头", inventory.can_add_item(_wood, 4))
	_check("满格无法加入不同物品", not inventory.can_add_item(_stone, 1))
	_check("零数量预检拒绝", not inventory.can_add_item(_wood, 0))
	_check("负数量预检拒绝", not inventory.can_add_item(_wood, -1))
	_check("空定义预检拒绝", not inventory.can_add_item(null, 1))
	var invalid: ItemDefinition = ItemDefinition.new()
	_check("空 id 预检拒绝", not inventory.can_add_item(invalid, 1))
	invalid.id = &"invalid"
	invalid.max_stack = 0
	_check("无效堆叠上限预检拒绝", not inventory.can_add_item(invalid, 1))
	# 同 id 的另一份资源仍表示同一物品，与实际添加的身份规则一致。
	var same_id: ItemDefinition = _wood.duplicate() as ItemDefinition
	_check("同 id 定义可补入已有堆", inventory.can_add_item(same_id, 4))
	_check_eq("预检后木头总数未变", inventory.get_item_count(&"wood"), 194)
	_check_eq("预检后堆数未变", inventory.get_used_slots(), 2)
	_check_eq("所有预检均不发 changed", counter[0], 0)
	_check_eq("预检可放的 4 件实际全放入", inventory.add_item(_wood, 4), 0)
	_check("补满之后无法再加入", not inventory.can_add_item(_wood, 1))
	inventory.clear()
	_check("两个空格可放 198 木头", inventory.can_add_item(_wood, 198))
	_check("两个空格无法放 199 木头", not inventory.can_add_item(_wood, 199))
	_check("两个空格可放两把石斧", inventory.can_add_item(_stone_axe, 2))
	_check("两个空格无法放三把石斧", not inventory.can_add_item(_stone_axe, 3))
	inventory.capacity = 0
	_check("零容量预检拒绝", not inventory.can_add_item(_wood, 1))
	inventory.capacity = -1
	_check("负容量预检拒绝", not inventory.can_add_item(_wood, 1))
	_check_eq("空背包预检不添加物品", inventory.get_used_slots(), 0)

# ==================== 第二组：Autoload 可达性 ====================

## 用例 12：探测 InventoryManager 单例并验证入口可用；结论以实测为准，不预设结果。
func _verify_autoload() -> void:
	print("[INVENTORY-01] ---- 用例 12：InventoryManager Autoload 可达性 ----")
	# 在场景树根下按单例名查找；--script 模式是否加载 Autoload 由引擎决定，此处只如实报告。
	var manager: Node = root.get_node_or_null("InventoryManager")
	_check("场景树根下存在 InventoryManager 单例", manager != null)
	# 单例缺失时明确说明这是环境限制，不得伪装成通过。
	if manager == null:
		print("  【环境限制】本次以 --script 启动，未加载 Autoload，单例可达性未能验证。")
		return
	# 单例应持有一个已创建的玩家背包。
	var player_inventory: Inventory = manager.get("inventory") as Inventory
	_check("单例已创建玩家背包", player_inventory != null)
	# 玩家背包缺失时无法继续验证入口。
	if player_inventory == null:
		return
	# 玩家背包初始应为空，且容量为 Inventory 的默认值。
	_check_eq("玩家背包初始已用格子", player_inventory.get_used_slots(), 0)
	_check_eq("玩家背包默认容量", player_inventory.capacity, Inventory.DEFAULT_CAPACITY)
	# 经单例入口实际添加物品，验证入口真的可用而不只是一个空壳。
	_check_eq("经单例添加木头 x5 剩余量", player_inventory.add_item(_wood, 5), 0)
	_check_eq("经单例添加后木头总数", player_inventory.get_item_count(&"wood"), 5)
	# create_inventory() 应返回与玩家背包相互独立的实例。
	var other: Inventory = manager.call("create_inventory", 5) as Inventory
	_check("create_inventory() 返回实例", other != null)
	# 派生实例缺失时跳过后续独立性验证。
	if other == null:
		return
	_check("派生背包与玩家背包不是同一实例", other != player_inventory)
	_check_eq("派生背包容量按参数生效", other.capacity, 5)
	_check_eq("派生背包初始为空（与玩家背包相互独立）", other.get_item_count(&"wood"), 0)
	print("  通过单例添加后玩家背包内容：\n%s" % player_inventory.debug_dump())
