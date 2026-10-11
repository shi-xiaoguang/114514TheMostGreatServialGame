extends Node
## Robinson —— UI-01 无头验证驱动（测试专用，非生产代码）。
## 绑定方式：作为 tests/ui_test.tscn 的根节点脚本；测试场景实例化正式入口 movement_test.tscn，
##          测试其中的真实玩家、拾取脚本与背包界面。
## 执行命令：godot --headless --path <工程目录> res://tests/ui_test.tscn
## 为什么不用 -s（SceneTree 脚本）：
##   界面脚本需要引用 Autoload 标识符 InventoryManager，而 --script 启动模式在编译期解析不到该标识符
##   （已实测报错 Identifier not found: InventoryManager），因此沿用 INTERACTION-01 的场景运行方式。
## 职责：① 注入真实的 Tab 按键事件，验证面板双向开关；
##       ② 直接改动数据层，验证界面靠 Inventory.changed 自动刷新（不手动调用刷新）；
##       ③ 核对背包格的节点结构（Icon / Name / Count）与显示文本；
##       ④ 核对数据层未被界面污染；逐条输出 PASS/FAIL。
## 范围声明：本阶段不验证拖拽、丢弃、合成、装备与快捷栏（本次未实现）。

# ==================== 常量 ====================

## 物品定义资源目录。
const ITEM_DIR: String = "res://resources/items/"

## 界面分组名：与 inventory_ui.gd 中的常量保持一致。
const GROUP_INVENTORY_UI: StringName = &"inventory_ui"

## 木头物品 id。
const ID_WOOD: StringName = &"wood"

## 石头物品 id。
const ID_STONE: StringName = &"stone"

const WORLD_ITEM_SCENE: PackedScene = preload("res://scenes/world_item.tscn")

# ==================== 运行时状态 ====================

## 通过的断言条数。
var _passed: int = 0

## 失败的断言条数：大于 0 时以退出码 1 结束。
var _failed: int = 0

## 被测界面根节点（CanvasLayer）。
var _ui: CanvasLayer = null

## 背包面板：Tab 开关的对象。
var _panel: Control = null

## 物品网格容器。
var _grid: GridContainer = null

## 空背包提示标签。
var _hint: Label = null

## 木头物品定义。
var _wood: ItemDefinition = null

## 石头物品定义。
var _stone: ItemDefinition = null

var _player: CharacterBody3D = null

# ==================== 生命周期 ====================

## 节点就绪后加载输入数据并启动完整验证流程。
func _ready() -> void:
	# 打印引擎版本，作为"本次确实运行过"的现场证据。
	print("[UI-01] 无头验证开始；引擎版本 = ", Engine.get_version_info()["string"])
	# 加载两份物品定义，作为数据层操作的输入数据。
	_wood = load(ITEM_DIR + "wood.tres") as ItemDefinition
	_stone = load(ITEM_DIR + "stone.tres") as ItemDefinition
	_check("木头定义可加载", _wood != null)
	_check("石头定义可加载", _stone != null)
	# 以协程方式启动用例。
	_run_all()

# ==================== 流程 ====================

## 顺序执行全部用例。
func _run_all() -> void:
	# 用例 0：输入映射。
	_case_input_map()
	# 定位界面节点并核对关键子节点存在。
	var ok: bool = await _prepare()
	# 界面不可用时后续用例都没有意义，直接收尾汇报。
	if not ok:
		_finish()
		return
	# 用例 1：初始状态。
	_case_initial_state()
	# 用例 2：Tab 双向开关。
	await _case_toggle()
	# 用例 3：空背包提示。
	await _case_empty_hint()
	# 用例 4：添加后自动刷新 + 格子节点结构。
	await _case_refresh_on_add()
	# 用例 5：两种物品并存。
	await _case_multi_item()
	# 用例 6：移除后自动刷新。
	await _case_refresh_on_remove()
	# 用例 7：清空后自动刷新。
	await _case_refresh_on_clear()
	# 用例 8：数据层未被界面污染。
	await _case_data_layer_untouched()
	# 迁移回归：默认满包的全部格子可见；通过真实 E 输入联动隐藏/显示中的界面。
	await _case_full_inventory()
	await _case_pickup_updates_ui()
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

## 记录一条数组相等断言：逐项打印，便于直接看出差异位置。
func _check_texts(label: String, actual: Array[String], expected: Array[String]) -> void:
	var same: bool = actual.size() == expected.size()
	# 长度不一致时无需再逐项比较。
	if same:
		for i: int in range(expected.size()):
			if actual[i] != expected[i]:
				same = false
				break
	if same:
		_passed += 1
		print("[PASS] %s = %s" % [label, str(actual)])
	else:
		_failed += 1
		print("[FAIL] %s：实测 = %s，预期 = %s" % [label, str(actual), str(expected)])

## 等待指定数量的处理帧：界面刷新与输入送达都以处理帧为观察单位。
func _wait_frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().process_frame

## 注入一次真实的 Tab 按键事件，经引擎输入管线送达界面的 _unhandled_input。
func _press_tab() -> void:
	_send_tab(true)
	_send_tab(false)

func _send_tab(pressed: bool, echo_event: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	# 使用物理键码，与 project.godot 中 toggle_inventory 动作的绑定保持一致。
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	event.echo = echo_event
	# 从根视口注入，保证走的是与真实按键相同的输入链路。
	get_viewport().push_input(event)

func _press_interact() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	get_viewport().push_input(event)
	var release: InputEventKey = InputEventKey.new()
	release.physical_keycode = KEY_E
	release.pressed = false
	get_viewport().push_input(release)

func _wait_physics_frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame
	await get_tree().process_frame

func _spawn_pickup(definition: ItemDefinition, amount: int) -> WorldItem:
	var item: WorldItem = WORLD_ITEM_SCENE.instantiate() as WorldItem
	item.definition = definition
	item.amount = amount
	add_child(item)
	item.global_position = _player.global_position + Vector3(1.0, 0.15, 0.0)
	return item

## 复位玩家背包到干净状态：清空内容并恢复默认容量。
func _reset_inventory() -> Inventory:
	var inventory: Inventory = InventoryManager.inventory
	inventory.clear()
	inventory.capacity = Inventory.DEFAULT_CAPACITY
	return inventory

## 收集网格中每个格子的显示文本，格式为"名称 x数量"，便于与数据层逐项比对。
func _slot_texts() -> Array[String]:
	var texts: Array[String] = []
	for child: Node in _grid.get_children():
		# 名称与数量分别取自格子的 Name 与 Count 子节点。
		var name_label: Label = child.find_child("Name", true, false) as Label
		var count_label: Label = child.find_child("Count", true, false) as Label
		# 子节点缺失时用占位文本标出，避免断言只报"数量不符"而掩盖结构问题。
		var name_text: String = name_label.text if name_label != null else "<缺 Name>"
		var count_text: String = count_label.text if count_label != null else "<缺 Count>"
		texts.append((name_text + " " + count_text).strip_edges())
	return texts

## 打印汇总并按失败条数决定退出码。
func _finish() -> void:
	print("[UI-01] 汇总：PASS = %d，FAIL = %d" % [_passed, _failed])
	# 存在失败时返回非零退出码，使命令行可据此判定不通过。
	get_tree().quit(1 if _failed > 0 else 0)

# ==================== 用例 ====================

## 用例 0：确认开关背包动作已按主创批准写入 InputMap，且绑定 Tab 键。
func _case_input_map() -> void:
	print("[UI-01] ---- 用例 0：输入映射 ----")
	_check("InputMap 中存在 toggle_inventory 动作", InputMap.has_action("toggle_inventory"))
	# 取该动作绑定的全部事件。
	var events: Array[InputEvent] = InputMap.action_get_events("toggle_inventory")
	_check("toggle_inventory 至少绑定一个按键", not events.is_empty())
	# 逐个核对绑定事件中确实存在物理键码为 Tab 的按键。
	var has_key_tab: bool = false
	for event: InputEvent in events:
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == KEY_TAB:
			has_key_tab = true
	_check("toggle_inventory 绑定 Tab 键（physical_keycode = %d）" % KEY_TAB, has_key_tab)

## 定位界面实例与三个关键子节点；返回是否可继续验证。
func _prepare() -> bool:
	print("[UI-01] ---- 用例前置：定位正式入口中的界面实例 ----")
	# 等待若干帧，保证场景树与界面脚本初始化完成。
	await _wait_frames(3)
	# 通过分组查找界面实例，避免依赖具体节点路径。
	var uis: Array[Node] = get_tree().get_nodes_in_group(GROUP_INVENTORY_UI)
	_check("场景中存在背包界面实例", not uis.is_empty())
	# 找不到界面就无法继续。
	if uis.is_empty():
		return false
	_ui = uis[0] as CanvasLayer
	# 按名字查找关键子节点，节点改名会在这里直接暴露。
	_panel = _ui.find_child("InventoryPanel", true, false) as Control
	_grid = _ui.find_child("ItemGrid", true, false) as GridContainer
	_hint = _ui.find_child("EmptyHint", true, false) as Label
	_check("面板节点 InventoryPanel 存在", _panel != null)
	_check("网格节点 ItemGrid 存在", _grid != null)
	_check("空背包提示节点 EmptyHint 存在", _hint != null)
	# 任一关键节点缺失都无法继续。
	if _panel == null or _grid == null or _hint == null:
		return false
	_check("界面根节点为 CanvasLayer", _ui is CanvasLayer)
	_player = get_tree().get_first_node_in_group(&"player") as CharacterBody3D
	_check("正式玩家已接入 player 分组", _player != null)
	if _player == null:
		return false
	return true

## 用例 1：界面初始状态。
func _case_initial_state() -> void:
	print("[UI-01] ---- 用例 1：初始状态 ----")
	_check("面板初始隐藏", not _panel.visible)
	_check_eq("网格列数为导出参数值", _grid.columns, 5)

## 用例 2：Tab 双向开关，且不影响背包数据。
func _case_toggle() -> void:
	print("[UI-01] ---- 用例 2：Tab 开关 ----")
	var inventory: Inventory = _reset_inventory()
	# 记录按键前的木头数量，用于确认 Tab 不会误触发拾取或任何数据变更。
	var before: int = inventory.get_item_count(ID_WOOD)
	# 第一次按 Tab：应打开面板。
	_press_tab()
	await _wait_frames(2)
	_check("按 Tab 后面板可见", _panel.visible)
	_send_tab(true, true)
	await _wait_frames(2)
	_check("Tab 长按重复事件不会关闭面板", _panel.visible)
	_send_tab(false)
	await _wait_frames(2)
	_check("释放 Tab 不会关闭面板", _panel.visible)
	# 第二次按 Tab：应关闭面板。
	_press_tab()
	await _wait_frames(2)
	_check("再按 Tab 后面板隐藏", not _panel.visible)
	# 第三次按 Tab 再次打开，确认可反复双向切换。
	_press_tab()
	await _wait_frames(2)
	_check("第三次按 Tab 后面板再次可见", _panel.visible)
	_check_eq("Tab 未改变背包数据", inventory.get_item_count(ID_WOOD), before)
	# 关闭面板，保持与后续用例一致的初始可见性。
	_press_tab()
	await _wait_frames(2)

## 用例 3：空背包时显示"暂无物品"提示，且网格为空。
func _case_empty_hint() -> void:
	print("[UI-01] ---- 用例 3：空背包提示 ----")
	_reset_inventory()
	await _wait_frames(2)
	_check_eq("空背包时网格格子数", _grid.get_child_count(), 0)
	_check("空背包时显示提示文本", _hint.visible)
	_check_eq("提示文本内容", _hint.text, "暂无物品")
	_check("空背包时网格隐藏", not _grid.visible)

## 用例 4：添加物品后界面自动刷新（全程不手动调用刷新），并核对格子节点结构。
func _case_refresh_on_add() -> void:
	print("[UI-01] ---- 用例 4：添加后自动刷新 ----")
	var inventory: Inventory = _reset_inventory()
	# 250 件木头按单堆上限 99 切成 99 / 99 / 52 三堆。
	inventory.add_item(_wood, 250)
	await _wait_frames(2)
	_check_eq("网格格子数", _grid.get_child_count(), 3)
	_check_texts("格子文本", _slot_texts(), ["木头 x99", "木头 x99", "木头 x52"])
	_check("有物品时隐藏提示文本", not _hint.visible)
	_check("有物品时显示网格", _grid.visible)
	# 核对格子节点结构：根为 Control 且挂 InventorySlot 脚本，三个子节点齐全。
	_check("格子根节点为 Control", _grid.get_child(0) is Control)
	_check("格子根节点挂有 InventorySlot 脚本", _grid.get_child(0) is InventorySlot)
	_check("格子包含 Icon(TextureRect) 子节点", _grid.get_child(0).find_child("Icon", true, false) is TextureRect)
	_check("格子包含 Name(Label) 子节点", _grid.get_child(0).find_child("Name", true, false) is Label)
	_check("格子包含 Count(Label) 子节点", _grid.get_child(0).find_child("Count", true, false) is Label)

## 用例 5：两种物品并存时逐一渲染。
func _case_multi_item() -> void:
	print("[UI-01] ---- 用例 5：两种物品 ----")
	var inventory: Inventory = InventoryManager.inventory
	inventory.add_item(_stone, 40)
	await _wait_frames(2)
	_check_eq("网格格子数", _grid.get_child_count(), 4)
	_check_texts("格子文本", _slot_texts(), ["木头 x99", "木头 x99", "木头 x52", "石头 x40"])

## 用例 6：移除物品后界面自动刷新，空堆不残留。
func _case_refresh_on_remove() -> void:
	print("[UI-01] ---- 用例 6：移除后自动刷新 ----")
	var inventory: Inventory = InventoryManager.inventory
	# 木头共 250（99/99/52），从前向后扣 100 → 第一堆清空被删，剩 98 与 52。
	var removed: int = inventory.remove_item(ID_WOOD, 100)
	_check_eq("实际移除量", removed, 100)
	await _wait_frames(2)
	_check_eq("网格格子数", _grid.get_child_count(), 3)
	_check_texts("格子文本", _slot_texts(), ["木头 x98", "木头 x52", "石头 x40"])

## 用例 7：清空后界面自动刷新为空状态。
func _case_refresh_on_clear() -> void:
	print("[UI-01] ---- 用例 7：清空后自动刷新 ----")
	var inventory: Inventory = InventoryManager.inventory
	inventory.clear()
	await _wait_frames(2)
	_check_eq("网格格子数", _grid.get_child_count(), 0)
	_check("清空后重新显示提示文本", _hint.visible)
	_check("清空后网格隐藏", not _grid.visible)

## 用例 8：反复触碰数据层触发多次界面重建，核对数据层始终未被界面污染。
func _case_data_layer_untouched() -> void:
	print("[UI-01] ---- 用例 8：数据层未被界面污染 ----")
	var inventory: Inventory = _reset_inventory()
	# 装载 4 堆内容作为基准。
	inventory.add_item(_wood, 250)
	inventory.add_item(_stone, 40)
	# 记录基准数据。
	var slots_before: int = inventory.get_used_slots()
	var wood_before: int = inventory.get_item_count(ID_WOOD)
	var stone_before: int = inventory.get_item_count(ID_STONE)
	# 反复加一又减一，制造多次界面重建：界面只读消费副本，不应影响数据。
	for _i: int in range(3):
		inventory.add_item(_wood, 1)
		inventory.remove_item(ID_WOOD, 1)
	await _wait_frames(3)
	# 数据层各项数值必须与基准完全一致。
	_check_eq("多次刷新后已用格子未变", inventory.get_used_slots(), slots_before)
	_check_eq("多次刷新后木头数量未变", inventory.get_item_count(ID_WOOD), wood_before)
	_check_eq("多次刷新后石头数量未变", inventory.get_item_count(ID_STONE), stone_before)
	# 界面渲染的格子数应与数据层堆数一致。
	_check_eq("界面格子数与数据层堆数一致", _grid.get_child_count(), slots_before)
	# 打印最终界面内容，作为人工复核用的可读证据。
	print("  界面最终内容：")
	var texts: Array[String] = _slot_texts()
	for text: String in texts:
		print("    %s" % text)


## 默认容量装满后，20 个格子的内容和布局都应保留，Tab 不得改动库存。
func _case_full_inventory() -> void:
	print("[UI-01] ---- 用例 9：20 格满包显示 ----")
	var inventory: Inventory = _reset_inventory()
	_check_eq("默认容量为 20 格", inventory.capacity, 20)
	var amount: int = 20 * _wood.max_stack
	_check_eq("装入 20 个完整物品堆无剩余", inventory.add_item(_wood, amount), 0)
	if not _panel.visible:
		_press_tab()
	await _wait_frames(4)
	_check("满包面板可见", _panel.visible)
	_check_eq("满包显示 20 个格子", _grid.get_child_count(), 20)
	var expected: Array[String] = []
	for _i: int in range(20):
		expected.append("木头 x%d" % _wood.max_stack)
	_check_texts("满包逐格数量正确", _slot_texts(), expected)
	var all_slots_visible: bool = true
	for child: Node in _grid.get_children():
		var slot: Control = child as Control
		if slot == null or not slot.is_visible_in_tree():
			all_slots_visible = false
		elif not _panel.get_global_rect().encloses(slot.get_global_rect()):
			all_slots_visible = false
	_check("满包 20 格全部位于可见面板内", all_slots_visible)
	_check("满包面板位于当前视口内", get_viewport().get_visible_rect().encloses(_panel.get_global_rect()))
	_check_eq("显示满包未改变数量", inventory.get_item_count(ID_WOOD), amount)
	_press_tab()
	await _wait_frames(2)
	_check("满包仍可关闭面板", not _panel.visible)


## 经真实世界物品与 E 按键完成拾取，不直接调用 UI 刷新或库存添加方法。
func _case_pickup_updates_ui() -> void:
	print("[UI-01] ---- 用例 10：真实拾取与界面联动 ----")
	var inventory: Inventory = _reset_inventory()
	# 移除入口自带样例，防止附近其他物品影响本用例的距离选择。
	for node: Node in get_tree().get_nodes_in_group(&"world_item"):
		node.queue_free()
	await _wait_physics_frames(8)
	if _panel.visible:
		_press_tab()
	_check("拾取前界面隐藏", not _panel.visible)
	var first: WorldItem = _spawn_pickup(_wood, 4)
	await _wait_physics_frames(5)
	_press_interact()
	await _wait_physics_frames(3)
	_check("隐藏界面时 E 成功移除世界物品", not is_instance_valid(first))
	_check_eq("隐藏界面时 E 正确增加库存", inventory.get_item_count(ID_WOOD), 4)
	_check("E 不会自动打开界面", not _panel.visible)
	_check_texts("隐藏界面仍自动更新数量", _slot_texts(), ["木头 x4"])
	_press_tab()
	await _wait_frames(2)
	_check("拾取后 Tab 正常打开界面", _panel.visible)
	_check_texts("打开时显示刚拾取的数量", _slot_texts(), ["木头 x4"])
	var second: WorldItem = _spawn_pickup(_wood, 3)
	await _wait_physics_frames(5)
	_press_interact()
	await _wait_physics_frames(3)
	_check("界面打开时 E 仍能拾取", not is_instance_valid(second))
	_check_eq("第二次拾取后库存累计正确", inventory.get_item_count(ID_WOOD), 7)
	_check("拾取后界面保持打开", _panel.visible)
	_check_texts("打开中的界面立即显示累计数量", _slot_texts(), ["木头 x7"])
	_press_tab()
	await _wait_frames(2)
	_check("拾取后仍可关闭界面", not _panel.visible)
	_check_eq("整个联动流程不丢失或复制物品", inventory.get_item_count(ID_WOOD), 7)
