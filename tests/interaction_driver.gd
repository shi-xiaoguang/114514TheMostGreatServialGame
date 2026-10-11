extends Node
## Robinson —— INTERACTION-01 无头验证驱动（测试专用，非生产代码）。
## 绑定方式：作为 tests/interaction_test.tscn 的根节点脚本，实例化正式 movement_test.tscn。
## 执行命令：godot --headless --path <工程目录> res://tests/interaction_test.tscn
## 为什么不用 -s（SceneTree 脚本）：
##   经实测，以 --script 启动时 GDScript 编译期解析不到 Autoload 标识符 InventoryManager
##   （报错 Identifier not found: InventoryManager），而正常以场景运行则完全正常；
##   因此本测试改用"场景运行"方式，保证验证的是与正式运行一致的那条路径。
## 职责：在真实场景中布置受控拾取物，注入真实的"交互键(E)按下"事件，验证最小拾取闭环与防复制规则。
## 覆盖：交互键映射 / 未识别玩家 / 范围外 / 成功拾取 / 最近者优先 / 连续按键不复制 /
##      超容量无变更 / 两堆失败不重排 / 精确及近似等距 / 退出范围 / 无效数据 / 主场景冒烟。
## 范围声明：本阶段不验证 UI、提示文字、制作、建造与存档。

# ==================== 常量 ====================

## 物品定义资源目录。
const ITEM_DIR: String = "res://resources/items/"

## 可拾取物场景路径。
const ITEM_SCENE_PATH: String = "res://scenes/world_item.tscn"

## 可拾取物分组名：与 world_item.gd 中的常量保持一致。
const GROUP_WORLD_ITEM: StringName = &"world_item"

## 玩家分组名：与 player.tscn 中 Player 节点的 groups 保持一致。
const GROUP_PLAYER: StringName = &"player"

## 木头物品 id：与 resources/items/wood.tres 保持一致。
const ID_WOOD: StringName = &"wood"

## 石头物品 id：与 resources/items/stone.tres 保持一致。
const ID_STONE: StringName = &"stone"

# ==================== 运行时状态 ====================

## 通过的断言条数。
var _passed: int = 0

## 失败的断言条数：大于 0 时以退出码 1 结束。
var _failed: int = 0

## 临时观察失败拾取是否错误发布背包变更。
var _changed_count: int = 0

## 场景中的玩家节点：所有距离布置都以它为基准。
var _player: Node3D = null

## 木头物品定义。
var _wood: ItemDefinition = null

## 石头物品定义。
var _stone: ItemDefinition = null

# ==================== 生命周期 ====================

## 节点就绪后加载输入数据，并启动完整验证流程。
func _ready() -> void:
	# 打印引擎版本，作为"本次确实运行过"的现场证据。
	print("[INTERACTION-01] 无头验证开始；引擎版本 = ", Engine.get_version_info()["string"])
	# 加载两份物品定义，作为后续拾取物的配置数据。
	_wood = load(ITEM_DIR + "wood.tres") as ItemDefinition
	_stone = load(ITEM_DIR + "stone.tres") as ItemDefinition
	_check("木头定义可加载", _wood != null)
	_check("石头定义可加载", _stone != null)
	# 以协程方式启动用例：await 期间引擎继续推进物理与输入。
	_run_all()

# ==================== 流程 ====================

## 顺序执行全部用例。
func _run_all() -> void:
	# 用例 0：交互键映射。
	_case_input_map()
	# 等待世界场景稳定、定位玩家并清掉预置物。
	var ready_ok: bool = await _prepare_world()
	# 世界场景不可用时后续用例都没有意义，直接收尾汇报。
	if not ready_ok:
		_finish()
		return
	# 用例 1：拾取物未识别到玩家时按键无效。
	await _case_no_player()
	# 用例 2：范围外按键不拾取。
	await _case_out_of_range()
	# 用例 3：范围内按键成功拾取并移除物体。
	await _case_pick_up_success()
	# 用例 4：最近者优先。
	await _case_nearest_first()
	# 用例 5：连续按键不复制。
	await _case_double_press()
	# 用例 6：超容量不丢物品。
	await _case_full_capacity_no_loss()
	# 用例 7：仅能放入一部分时整份拒绝，不复制。
	await _case_partial_capacity()
	# 用例 8：定义缺失不丢物、不崩溃。
	await _case_null_definition()
	await _case_equal_distance()
	await _case_almost_equal_distance()
	await _case_two_stacks_unchanged()
	await _case_ignored_input()
	await _case_leave_range()
	await _case_invalid_configuration()
	# 收尾。
	_finish()

# ==================== 私有方法：断言与工具 ====================

## 记录一条布尔断言并打印结论。
func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		print("[FAIL] ", label)

## 记录一条"实测值 vs 预期值"断言；不一致时把两者都打印出来便于定位。
func _check_eq(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
		print("[PASS] %s = %s" % [label, str(actual)])
	else:
		_failed += 1
		print("[FAIL] %s：实测 = %s，预期 = %s" % [label, str(actual), str(expected)])

## 等待指定数量的物理帧：范围侦测与节点释放都需要物理帧推进才能观察。
func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame

## 注入一次真实的"交互键(E)按下"事件，经引擎输入管线送达节点的 _unhandled_input。
func _press_interact() -> void:
	_send_interact(true)

## echo 与释放测试仍从视口注入，不绕过生产输入处理。
func _send_interact(pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	# 使用物理键码，与 project.godot 中 interact 动作的绑定保持一致。
	event.physical_keycode = KEY_E
	event.pressed = pressed
	event.echo = echo
	# 从根视口注入，保证走的是与真实按键相同的输入链路。
	get_viewport().push_input(event)

## 在指定世界坐标创建一个受控的可拾取物并加入场景树。
func _spawn_item(definition: ItemDefinition, amount: int, world_position: Vector3) -> WorldItem:
	var scene: PackedScene = load(ITEM_SCENE_PATH)
	# 实例化并显式转换；转换失败时返回空值，由调用方通过断言发现。
	var item: WorldItem = scene.instantiate() as WorldItem
	# 先配置数据再加入场景树，使 _ready 运行时参数已经就绪。
	item.definition = definition
	item.amount = amount
	add_child(item)
	# 入树后再设置坐标，保证语义是世界坐标。
	item.global_position = world_position
	return item

## 取当前玩家节点：通过 player 分组查找，避免依赖节点路径。
func _find_player() -> Node3D:
	# 分组内应恰好有一个玩家节点。
	var players: Array[Node] = get_tree().get_nodes_in_group(GROUP_PLAYER)
	if players.is_empty():
		return null
	return players[0] as Node3D

## 复位玩家背包到干净状态：清空内容并恢复默认容量。
func _reset_inventory() -> Inventory:
	var inventory: Inventory = InventoryManager.inventory
	inventory.clear()
	inventory.capacity = Inventory.DEFAULT_CAPACITY
	return inventory

func _on_inventory_changed() -> void:
	_changed_count += 1

## 保存逐堆内容而非只保存总数，可检测失败拾取导致的重排。
func _stack_snapshot(inventory: Inventory) -> Array[String]:
	var snapshot: Array[String] = []
	for stack: ItemStack in inventory.get_stacks():
		snapshot.append("%s:%d" % [stack.definition.id, stack.get_count()])
	return snapshot

## 打印汇总并按失败条数决定退出码。
func _finish() -> void:
	print("[INTERACTION-01] 汇总：PASS = %d，FAIL = %d" % [_passed, _failed])
	# 存在失败时返回非零退出码，使命令行可据此判定不通过。
	get_tree().quit(1 if _failed > 0 else 0)

# ==================== 用例 ====================

## 用例 0：确认交互键动作已按主创批准写入 InputMap，且绑定 E 键。
func _case_input_map() -> void:
	print("[INTERACTION-01] ---- 用例 0：交互键映射 ----")
	_check("InputMap 中存在 interact 动作", InputMap.has_action("interact"))
	# 取该动作绑定的全部事件。
	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	_check("interact 动作至少绑定一个按键", not events.is_empty())
	# 逐个核对绑定事件中确实存在物理键码为 E 的按键。
	var has_key_e: bool = false
	for event: InputEvent in events:
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == KEY_E:
			has_key_e = true
	_check("interact 绑定 E 键（physical_keycode = %d）" % KEY_E, has_key_e)

## 等待世界场景稳定、定位玩家、核对预置测试物并清理；返回是否可继续。
func _prepare_world() -> bool:
	print("[INTERACTION-01] ---- 用例前置：movement_test.tscn 冒烟检查 ----")
	# 等待若干物理帧，让玩家由重力落到地面并稳定下来。
	await _wait_frames(8)
	# 定位玩家节点，确认其已在 player 分组中。
	_player = _find_player()
	_check("主场景中的玩家已加入 player 分组", _player != null)
	# 定不到玩家则无法布置用例。
	if _player == null:
		return false
	print("  玩家落地位置 = %s" % str(_player.global_position))
	# 冒烟检查：预置的三个测试物是否都在，且物品定义正确。
	var items: Array[Node] = get_tree().get_nodes_in_group(GROUP_WORLD_ITEM)
	_check_eq("主场景中预置拾取物数量", items.size(), 3)
	# 逐个统计预置物的物品 id。
	var wood_count: int = 0
	var stone_count: int = 0
	for node: Node in items:
		var item: WorldItem = node as WorldItem
		# 非 WorldItem 或未配置定义的节点不参与统计。
		if item == null or item.definition == null:
			continue
		if item.definition.id == ID_WOOD:
			wood_count += 1
		elif item.definition.id == ID_STONE:
			stone_count += 1
	_check_eq("预置木头拾取物数量", wood_count, 2)
	_check_eq("预置石头拾取物数量", stone_count, 1)
	# 清掉预置物，为后续受控布置留出干净场景。
	for node: Node in items:
		node.queue_free()
	await _wait_frames(3)
	_check_eq("清理预置物后场上拾取物数量", get_tree().get_nodes_in_group(GROUP_WORLD_ITEM).size(), 0)
	return true

## 用例 1：拾取物未识别到玩家时按键不应产生任何效果。
## 实现方式：临时把玩家移出 player 分组，使拾取物无法确认其身份，等价于"场上没有玩家"，
##          由此覆盖 world_item.gd 中 _player == null 的保护分支。
func _case_no_player() -> void:
	print("[INTERACTION-01] ---- 用例 1：拾取物未识别到玩家 ----")
	var inventory: Inventory = _reset_inventory()
	# 临时摘掉玩家分组：后续新建的拾取物将无法把该实体识别为玩家。
	_player.remove_from_group(GROUP_PLAYER)
	await _wait_frames(2)
	# 记录按键前的数量，用于确认状态零变化。
	var before: int = inventory.get_item_count(ID_WOOD)
	# 在玩家身边放一个拾取物。
	var item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_check("未识别到玩家时物体不记录玩家在范围内", not item.is_player_in_range())
	_press_interact()
	await _wait_frames(2)
	# 没有可用玩家身份就不应发生拾取：物体保留、背包零变化。
	_check("未识别到玩家时按键后物体仍然存在", is_instance_valid(item))
	_check_eq("未识别到玩家时按键后木头数量", inventory.get_item_count(ID_WOOD), before)
	# 清理并恢复玩家分组，供后续用例使用。
	item.queue_free()
	_player.add_to_group(GROUP_PLAYER)
	await _wait_frames(3)

## 用例 2：玩家在侦测范围外时按键不拾取。
func _case_out_of_range() -> void:
	print("[INTERACTION-01] ---- 用例 2：范围外按键 ----")
	var inventory: Inventory = _reset_inventory()
	# 在离玩家 8 米处放一个木头：侦测球半径只有 2.5 米，因此不在范围内。
	var far_item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -8.0))
	await _wait_frames(3)
	_check("范围外物体未记录玩家在范围内", not far_item.is_player_in_range())
	_press_interact()
	await _wait_frames(2)
	_check_eq("范围外按键后木头数量", inventory.get_item_count(ID_WOOD), 0)
	_check("范围外按键后物体仍然存在", is_instance_valid(far_item))
	# 清理，避免影响后续用例。
	far_item.queue_free()
	await _wait_frames(2)

## 用例 3：玩家在范围内按键，成功拾取并移除物体。
func _case_pick_up_success() -> void:
	print("[INTERACTION-01] ---- 用例 3：范围内按键成功拾取 ----")
	var inventory: Inventory = _reset_inventory()
	# 在离玩家 1 米处放一个木头。
	var item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_check("范围内物体已记录玩家", item.is_player_in_range())
	_press_interact()
	# 拾取会触发 queue_free，需要推进帧才能观察到节点被释放。
	await _wait_frames(3)
	_check_eq("拾取后木头数量", inventory.get_item_count(ID_WOOD), 1)
	_check("拾取后物体已从世界移除", not is_instance_valid(item))
	print("  拾取后背包：\n%s" % inventory.debug_dump())

## 用例 4：多个物体同时在范围内时，只有离玩家最近的那个被拾取。
func _case_nearest_first() -> void:
	print("[INTERACTION-01] ---- 用例 4：最近者优先 ----")
	var inventory: Inventory = _reset_inventory()
	# 近处放石头（约 1 米），稍远处放木头（约 2 米），两者都在 2.5 米侦测范围内。
	var near_stone: WorldItem = _spawn_item(_stone, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	var mid_wood: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -2.0))
	await _wait_frames(3)
	_check("较近的石头在范围内", near_stone.is_player_in_range())
	_check("较远的木头也在范围内", mid_wood.is_player_in_range())
	# 第一次按键：应拾取最近的石头，木头不受影响。
	_press_interact()
	await _wait_frames(3)
	_check_eq("第一次按键后石头数量", inventory.get_item_count(ID_STONE), 1)
	_check_eq("第一次按键后木头数量（应为 0）", inventory.get_item_count(ID_WOOD), 0)
	_check("较近的石头已移除", not is_instance_valid(near_stone))
	_check("较远的木头仍然存在", is_instance_valid(mid_wood))
	# 第二次按键：最近的已被移除，应轮到稍远的木头。
	_press_interact()
	await _wait_frames(3)
	_check_eq("第二次按键后木头数量", inventory.get_item_count(ID_WOOD), 1)
	_check("稍远的木头已移除", not is_instance_valid(mid_wood))
	print("  拾取顺序验证后背包：\n%s" % inventory.debug_dump())

## 用例 5：同一帧内连续按键不会把同一个物体拾取两次。
func _case_double_press() -> void:
	print("[INTERACTION-01] ---- 用例 5：连续按键不复制 ----")
	var inventory: Inventory = _reset_inventory()
	var item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	# 不间隔等待，连发两次按键事件，模拟同一帧内的快速连按。
	_press_interact()
	_press_interact()
	await _wait_frames(3)
	_check_eq("连续两次按键后木头数量（应为 1）", inventory.get_item_count(ID_WOOD), 1)
	_check("连续按键后物体已移除", not is_instance_valid(item))
	# 物体移除后再按一次，数量不应继续增长。
	_press_interact()
	await _wait_frames(2)
	_check_eq("物体移除后再按键木头数量（仍为 1）", inventory.get_item_count(ID_WOOD), 1)

## 用例 6：背包该物品已放不下时拾取失败，但既不丢物也不复制。
func _case_full_capacity_no_loss() -> void:
	print("[INTERACTION-01] ---- 用例 6：超容量不丢物品 ----")
	var inventory: Inventory = _reset_inventory()
	# 把容量压到 1 堆并填满该堆（99 件），使新木头再也开不了新堆。
	inventory.capacity = 1
	inventory.add_item(_wood, 99)
	_check_eq("前置：背包木头数量", inventory.get_item_count(ID_WOOD), 99)
	_check("前置：背包已满", inventory.is_full())
	# 在范围内放一个代表 1 件木头的拾取物。
	var item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_press_interact()
	await _wait_frames(3)
	# 放不下时应保持原样：物体不消失、背包数量不变，杜绝"物体没了物品也没进包"。
	_check_eq("拾取失败后木头数量（应仍为 99）", inventory.get_item_count(ID_WOOD), 99)
	_check("拾取失败后物体保留在世界中", is_instance_valid(item))
	# 清理，避免影响后续用例。
	item.queue_free()
	await _wait_frames(2)

## 用例 7：只能放入一部分时整个拾取失败；保留原有单堆回归。
func _case_partial_capacity() -> void:
	print("[INTERACTION-01] ---- 用例 7：容量不足拒绝整份拾取 ----")
	var inventory: Inventory = _reset_inventory()
	# 容量 1 堆，已有 95 件木头：该堆只剩 4 个空位。
	inventory.capacity = 1
	inventory.add_item(_wood, 95)
	_check_eq("前置：背包木头数量", inventory.get_item_count(ID_WOOD), 95)
	# 放一个代表 5 件的木头拾取物：只能放入 4 件，剩余 1 件放不下。
	var item: WorldItem = _spawn_item(_wood, 5, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_press_interact()
	await _wait_frames(3)
	# 预检应在写入前拒绝，数量仍为 95 且物体保留。
	_check_eq("容量不足后木头数量（应仍为 95）", inventory.get_item_count(ID_WOOD), 95)
	_check("容量不足后物体保留在世界中", is_instance_valid(item))
	# 清理，避免影响后续用例。
	item.queue_free()
	await _wait_frames(2)

## 用例 8：未配置物品定义时按键不丢物、不崩溃。
func _case_null_definition() -> void:
	print("[INTERACTION-01] ---- 用例 8：物品定义缺失 ----")
	var inventory: Inventory = _reset_inventory()
	# 故意创建一个没有物品定义的拾取物。
	var item: WorldItem = _spawn_item(null, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_press_interact()
	await _wait_frames(3)
	_check_eq("定义缺失时背包木头数量", inventory.get_item_count(ID_WOOD), 0)
	_check("定义缺失时物体保留在世界中", is_instance_valid(item))
	# 清理。
	item.queue_free()
	await _wait_frames(2)
	print("  （本条用例会输出一条预期内的 WorldItem 警告）")

## 精确等距以实例 ID 唯一选择，一次按键不能同时拿走两个物体。
func _case_equal_distance() -> void:
	print("[MIGRATION] ---- 精确等距只拾取一物 ----")
	var inventory: Inventory = _reset_inventory()
	var location: Vector3 = _player.global_position + Vector3(0.0, 0.15, -1.0)
	var wood: WorldItem = _spawn_item(_wood, 1, location)
	var stone: WorldItem = _spawn_item(_stone, 1, location)
	var wood_first: bool = wood.get_instance_id() < stone.get_instance_id()
	await _wait_frames(3)
	_check("等距双方都进入范围", wood.is_player_in_range() and stone.is_player_in_range())
	_press_interact()
	await _wait_frames(3)
	_check_eq("等距第一次拾取木头数", inventory.get_item_count(ID_WOOD), 1 if wood_first else 0)
	_check_eq("等距第一次拾取石头数", inventory.get_item_count(ID_STONE), 0 if wood_first else 1)
	_check("等距第一次只移除一个物体", is_instance_valid(wood) != is_instance_valid(stone))
	_press_interact()
	await _wait_frames(3)
	_check_eq("等距第二次木头总数", inventory.get_item_count(ID_WOOD), 1)
	_check_eq("等距第二次石头总数", inventory.get_item_count(ID_STONE), 1)
	if is_instance_valid(wood):
		wood.queue_free()
	if is_instance_valid(stone):
		stone.queue_free()
	await _wait_frames(2)

## 旧实现会让略远、ID 较小的一方与略近的一方相互退让。
func _case_almost_equal_distance() -> void:
	print("[MIGRATION] ---- 近似等距仍选严格最近者 ----")
	var inventory: Inventory = _reset_inventory()
	var farther: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.000001))
	var nearer: WorldItem = _spawn_item(_stone, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	var farther_distance: float = farther.global_position.distance_to(_player.global_position)
	var nearer_distance: float = nearer.global_position.distance_to(_player.global_position)
	_check("近似等距前置：较远者 ID 更小", farther.get_instance_id() < nearer.get_instance_id())
	_check("近似等距前置：严格不等但近似相等", nearer_distance < farther_distance and is_equal_approx(nearer_distance, farther_distance))
	_press_interact()
	await _wait_frames(3)
	_check_eq("近似等距拾取较近石头", inventory.get_item_count(ID_STONE), 1)
	_check_eq("近似等距保留较远木头", inventory.get_item_count(ID_WOOD), 0)
	_check("近似等距较近物体移除", not is_instance_valid(nearer))
	_check("近似等距较远物体保留", is_instance_valid(farther))
	if is_instance_valid(farther):
		farther.queue_free()
	if is_instance_valid(nearer):
		nearer.queue_free()
	await _wait_frames(2)

## [99,95] 只能容纳 4 件；拒绝 5 件时必须保留逐堆顺序且不发信号。
func _case_two_stacks_unchanged() -> void:
	print("[MIGRATION] ---- 失败拾取不重排也不发送 changed ----")
	var inventory: Inventory = _reset_inventory()
	inventory.capacity = 2
	inventory.add_item(_wood, 194)
	var before: Array[String] = _stack_snapshot(inventory)
	_check_eq("两堆前置", before, ["wood:99", "wood:95"])
	var item: WorldItem = _spawn_item(_wood, 5, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_changed_count = 0
	inventory.changed.connect(_on_inventory_changed)
	_press_interact()
	_press_interact()
	await _wait_frames(3)
	_check_eq("两次失败后逐堆内容保持原样", _stack_snapshot(inventory), before)
	_check_eq("两次失败后总数保持原样", inventory.get_item_count(ID_WOOD), 194)
	_check_eq("两次失败不发布 changed", _changed_count, 0)
	_check("两次失败后世界物体保留", is_instance_valid(item))
	# 容量恰好足够时仍能补满原堆，一次成功仅发出一次通知。
	if is_instance_valid(item):
		item.amount = 4
		_press_interact()
		await _wait_frames(3)
		_check_eq("恰好容纳后逐堆数量", _stack_snapshot(inventory), ["wood:99", "wood:99"])
		_check_eq("成功拾取仅发布一次 changed", _changed_count, 1)
		_check("成功后物体移除", not is_instance_valid(item))
	inventory.changed.disconnect(_on_inventory_changed)
	if is_instance_valid(item):
		item.queue_free()
	await _wait_frames(2)

func _case_ignored_input() -> void:
	print("[MIGRATION] ---- 长按重复与释放不拾取 ----")
	var inventory: Inventory = _reset_inventory()
	var item: WorldItem = _spawn_item(_wood, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_send_interact(true, true)
	_send_interact(false)
	await _wait_frames(3)
	_check_eq("echo 与释放后数量为零", inventory.get_item_count(ID_WOOD), 0)
	_check("echo 与释放后物体保留", is_instance_valid(item))
	_press_interact()
	await _wait_frames(3)
	_check_eq("正常按下仍可拾取", inventory.get_item_count(ID_WOOD), 1)
	if is_instance_valid(item):
		item.queue_free()
	await _wait_frames(2)

func _case_leave_range() -> void:
	print("[MIGRATION] ---- 进入再离开后不能拾取 ----")
	var inventory: Inventory = _reset_inventory()
	var start: Vector3 = _player.global_position
	var item: WorldItem = _spawn_item(_wood, 1, start + Vector3(0.0, 0.15, -1.0))
	await _wait_frames(3)
	_check("退出范围前已经识别玩家", item.is_player_in_range())
	_player.global_position = start + Vector3(8.0, 0.0, 0.0)
	await _wait_frames(4)
	_check("离开后范围状态清除", not item.is_player_in_range())
	_press_interact()
	await _wait_frames(3)
	_check_eq("离开后按键未增加库存", inventory.get_item_count(ID_WOOD), 0)
	_check("离开后按键保留世界物体", is_instance_valid(item))
	if is_instance_valid(item):
		item.queue_free()
	_player.global_position = start
	await _wait_frames(8)

func _case_invalid_configuration() -> void:
	print("[MIGRATION] ---- 无效数量与定义不丢物 ----")
	var inventory: Inventory = _reset_inventory()
	_changed_count = 0
	inventory.changed.connect(_on_inventory_changed)
	for invalid_amount: int in [0, -1]:
		var item: WorldItem = _spawn_item(_wood, invalid_amount, _player.global_position + Vector3(0.0, 0.15, -1.0))
		await _wait_frames(3)
		_press_interact()
		await _wait_frames(3)
		_check("无效数量 %d 时物体保留" % invalid_amount, is_instance_valid(item))
		if is_instance_valid(item):
			item.queue_free()
		await _wait_frames(2)
	var invalid_definitions: Array[ItemDefinition] = [ItemDefinition.new(), _wood.duplicate() as ItemDefinition]
	invalid_definitions[1].max_stack = 0
	for definition: ItemDefinition in invalid_definitions:
		var item: WorldItem = _spawn_item(definition, 1, _player.global_position + Vector3(0.0, 0.15, -1.0))
		await _wait_frames(3)
		_press_interact()
		await _wait_frames(3)
		_check("无效定义时物体保留", is_instance_valid(item))
		if is_instance_valid(item):
			item.queue_free()
		await _wait_frames(2)
	_check_eq("无效配置未新增任何库存格", inventory.get_used_slots(), 0)
	_check_eq("无效配置不发布 changed", _changed_count, 0)
	inventory.changed.disconnect(_on_inventory_changed)
