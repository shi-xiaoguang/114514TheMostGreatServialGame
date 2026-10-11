extends SceneTree
## Robinson —— ITEM-01 无头验证脚本（测试专用，非生产代码）。
## 绑定方式：不经场景，直接以资源路径执行：
##   godot --headless --path <工程目录> -s res://tests/test_item_definition.gd
## 职责：① 按路径加载 resources/items/ 下的四个物品定义资源，逐项打印实测字段并与预期比对；
##       ② 验证 has_tag 的命中、未命中与大小写不敏感行为；
##       ③ 验证 is_valid / is_stackable / get_display_name 的边界行为；
##       ④ 逐条输出 PASS/FAIL，并以退出码汇报总结果（0 = 全部通过，1 = 存在失败）。
## 设计说明：本脚本刻意不引用全局类名 ItemDefinition，而是以 preload 取脚本再读取其枚举，
##           以免依赖 .godot 全局类缓存是否已刷新；枚举取值另用断言与脚本声明对齐。
## 范围说明：本阶段不验证背包、拾取、制作、装备、消耗与界面，只验证物品定义层。

# ==================== 常量 ====================

## 物品定义脚本：以路径预加载，用于实例化临时定义与读取 ItemType 枚举。
const ItemDefinitionScript: GDScript = preload("res://scripts/items/item_definition.gd")

## 物品类型字面量：与 item_definition.gd 中 ItemType 的声明顺序一致，另由枚举对齐断言兜底。
const TYPE_MATERIAL: int = 0

## 物品类型字面量：Tool（提供能力的工具）。
const TYPE_TOOL: int = 1

## 物品类型字面量：Consumable（消耗品）。
const TYPE_CONSUMABLE: int = 2

## 物品类型字面量：Equipment（装备，本阶段不使用）。
const TYPE_EQUIPMENT: int = 3

## 目标物品定义资源所在目录：仅用于日志展示。
const ITEM_DIR: String = "res://resources/items/"

# ==================== 运行时状态 ====================

## 通过的断言条数。
var _passed: int = 0

## 失败的断言条数：大于 0 时以退出码 1 结束，便于命令行判定。
var _failed: int = 0

# ==================== 主入口 ====================

## 脚本被实例化后立即执行全部验证，并按失败条数决定退出码。
func _init() -> void:
	# 打印引擎版本与脚本加载结果，作为"本次确实运行过"的现场证据。
	print("[ITEM-01] 无头验证开始；引擎版本 = ", Engine.get_version_info()["string"])
	# 逐项执行四组验证，顺序固定以便日志可比对。
	_verify_enum_alignment()
	_verify_definitions()
	_verify_tags()
	_verify_boundaries()
	_print_catalog()
	# 打印总结：PASS/FAIL 计数必须与上面逐条日志条数一致。
	print("[ITEM-01] 汇总：PASS = %d，FAIL = %d" % [_passed, _failed])
	# 存在失败时返回非零退出码，使命令行可据此判定不通过。
	quit(1 if _failed > 0 else 0)

# ==================== 私有方法：断言辅助 ====================

## 记录并打印一条断言的结论：通过计入 _passed，失败计入 _failed。
func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		print("[FAIL] ", label)

## 把标签数组转成稳定可读文本，避免依赖 Array 默认打印格式，便于日志肉眼比对。
func _tags_to_text(tags: Array) -> String:
	# 逐项转字符串后以逗号连接；空数组返回 "(空)"，避免打印出难以辨认的空白。
	var parts: Array[String] = []
	for tag: Variant in tags:
		parts.append(String(tag))
	return ",".join(parts) if not parts.is_empty() else "(空)"

## 比较两个标签集合是否等价：顺序无关、大小写不敏感，避免因书写顺序或大小写不同而误判。
func _same_tag_set(actual: Array, expected: Array) -> bool:
	# 元素个数不同时集合必然不等价，提前返回。
	if actual.size() != expected.size():
		return false
	# 逐个确认预期标签都能在实际集合中找到。
	for expected_tag: Variant in expected:
		var found: bool = false
		for actual_tag: Variant in actual:
			# 统一转小写后比较，与 ItemDefinition.has_tag 的大小写不敏感口径保持一致。
			if String(actual_tag).to_lower() == String(expected_tag).to_lower():
				found = true
				break
		# 任一预期标签缺失即判定集合不等价。
		if not found:
			return false
	# 全部预期标签均命中且数量一致，判定等价。
	return true

## 按资源路径取资源，并在加载失败时打印明确的失败原因，避免后续空引用中断测试。
func _load_definition(path: String) -> Resource:
	var definition: Resource = load(path)
	_check("资源可加载：" + path, definition != null)
	# 加载失败时返回空值，由调用方提前返回，保证后续断言不触发运行错误。
	return definition

# ==================== 私有方法：四组验证 ====================

## 验证测试内使用的类型字面量与 item_definition.gd 的 ItemType 枚举声明一一对应。
func _verify_enum_alignment() -> void:
	# 从脚本读取常量表；ItemType 在表中表现为一个字典。
	var constants: Dictionary = ItemDefinitionScript.get_script_constant_map()
	var enum_map: Dictionary = constants.get("ItemType", {})
	# 枚举能被读出是后续一切类型断言的前提。
	_check("ItemType 枚举可从 item_definition.gd 读取", not enum_map.is_empty())
	# 四个类型逐一比对字面量，任何声明顺序变动都会被这里捕获。
	_check("MATERIAL 字面量 = 0", int(enum_map.get("MATERIAL", -1)) == TYPE_MATERIAL)
	_check("TOOL 字面量 = 1", int(enum_map.get("TOOL", -1)) == TYPE_TOOL)
	_check("CONSUMABLE 字面量 = 2", int(enum_map.get("CONSUMABLE", -1)) == TYPE_CONSUMABLE)
	_check("EQUIPMENT 字面量 = 3", int(enum_map.get("EQUIPMENT", -1)) == TYPE_EQUIPMENT)
	# 打印枚举实测内容，作为日志证据。
	print("[ITEM-01] ItemType 枚举实测 = ", enum_map)

## 加载四个示例资源，逐项打印实测字段并与预期比对。
func _verify_definitions() -> void:
	# 每个用例写成一条"路径 + 全部预期字段"的记录，预期值与实测值同屏打印便于复核。
	var cases: Array[Dictionary] = [
		{
			"path": ITEM_DIR + "wood.tres",
			"id": &"wood",
			"display_name": "木头",
			"type": TYPE_MATERIAL,
			"max_stack": 99,
			"tags": [&"wood", &"fuel", &"building"],
			"stackable": true,
		},
		{
			"path": ITEM_DIR + "stone.tres",
			"id": &"stone",
			"display_name": "石头",
			"type": TYPE_MATERIAL,
			"max_stack": 99,
			"tags": [&"stone", &"building"],
			"stackable": true,
		},
		{
			"path": ITEM_DIR + "berry.tres",
			"id": &"berry",
			"display_name": "浆果",
			"type": TYPE_CONSUMABLE,
			"max_stack": 20,
			"tags": [&"food"],
			"stackable": true,
		},
		{
			"path": ITEM_DIR + "stone_axe.tres",
			"id": &"stone_axe",
			"display_name": "石斧",
			"type": TYPE_TOOL,
			"max_stack": 1,
			"tags": [&"tool", &"cutting", &"wood_processing"],
			"stackable": false,
		},
	]
	# 逐个用例执行加载与逐字段比对。
	for entry: Dictionary in cases:
		var path: String = String(entry["path"])
		print("[ITEM-01] ---- 用例：", path, " ----")
		var definition: Resource = _load_definition(path)
		# 资源加载失败时跳过该用例的字段比对，避免空引用导致测试中断。
		if definition == null:
			continue
		# 确认资源确实由物品定义脚本驱动，而非退化成裸 Resource。
		_check(path + " 由 item_definition.gd 驱动", definition.get_script() == ItemDefinitionScript)
		# 读取实测字段；使用 get() 动态取值，避免依赖全局类名注册状态。
		var actual_id: StringName = definition.get("id")
		var actual_name: String = definition.get("display_name")
		var actual_type: int = definition.get("type")
		var actual_stack: int = definition.get("max_stack")
		var actual_tags: Array = definition.get("tags")
		var actual_metadata: Dictionary = definition.get("metadata")
		var actual_icon: Texture2D = definition.get("icon")
		var actual_description: String = definition.get("description")
		# 同屏打印实测值与预期值，便于不依赖断言也能人工复核。
		print("    实测：id=%s name=%s type=%d max_stack=%d tags=[%s] description=%s" % [
			actual_id, actual_name, actual_type, actual_stack, _tags_to_text(actual_tags), actual_description,
		])
		print("    预期：id=%s name=%s type=%d max_stack=%d tags=[%s]" % [
			String(entry["id"]), String(entry["display_name"]), int(entry["type"]),
			int(entry["max_stack"]), _tags_to_text(entry["tags"]),
		])
		print("    预留字段实测：icon=%s metadata=%s" % [str(actual_icon), str(actual_metadata)])
		# 逐字段断言。
		_check(path + " → id 正确", actual_id == entry["id"])
		_check(path + " → display_name 正确", actual_name == String(entry["display_name"]))
		_check(path + " → type 正确", actual_type == int(entry["type"]))
		_check(path + " → max_stack 正确", actual_stack == int(entry["max_stack"]))
		_check(path + " → tags 集合正确", _same_tag_set(actual_tags, entry["tags"]))
		# 预留字段的默认值断言：icon 必须为空（不加载外部贴图），metadata 必须为空字典。
		_check(path + " → icon 预留且默认为空", actual_icon == null)
		_check(path + " → metadata 为 Dictionary", actual_metadata is Dictionary)
		_check(path + " → metadata 默认为空", actual_metadata.is_empty())
		# 只读方法断言。
		_check(path + " → is_valid() = true", bool(definition.call("is_valid")))
		_check(path + " → is_stackable() 正确", bool(definition.call("is_stackable")) == bool(entry["stackable"]))
		_check(path + " → get_display_name() 非空", String(definition.call("get_display_name")) != "")

## 验证 has_tag 的命中、未命中、大小写不敏感与空标签行为。
func _verify_tags() -> void:
	print("[ITEM-01] ---- 用例：has_tag 标签查询 ----")
	# 取三份定义分别代表材料、消耗品与工具。
	var wood: Resource = _load_definition(ITEM_DIR + "wood.tres")
	var stone: Resource = _load_definition(ITEM_DIR + "stone.tres")
	var berry: Resource = _load_definition(ITEM_DIR + "berry.tres")
	var stone_axe: Resource = _load_definition(ITEM_DIR + "stone_axe.tres")
	# 任一份加载失败时终止本组验证，避免空引用。
	if wood == null or stone == null or berry == null or stone_axe == null:
		_check("标签验证前置条件：四份定义全部可加载", false)
		return
	# 命中用例：木头应同时带有 wood / fuel / building。
	_check("木头 has_tag(wood) = true", bool(wood.call("has_tag", &"wood")))
	_check("木头 has_tag(fuel) = true", bool(wood.call("has_tag", &"fuel")))
	_check("木头 has_tag(building) = true", bool(wood.call("has_tag", &"building")))
	# 未命中用例：木头不应带 stone / food。
	_check("木头 has_tag(stone) = false", not bool(wood.call("has_tag", &"stone")))
	_check("木头 has_tag(food) = false", not bool(wood.call("has_tag", &"food")))
	# 大小写不敏感用例：编辑器里手填大小写混杂也应命中。
	_check("木头 has_tag(Wood) 大小写不敏感", bool(wood.call("has_tag", &"Wood")))
	_check("木头 has_tag(WOOD) 大小写不敏感", bool(wood.call("has_tag", &"WOOD")))
	_check("木头 has_tag(fUeL) 大小写不敏感", bool(wood.call("has_tag", &"fUeL")))
	# 石头与浆果的标签互斥关系，确认标签不是"人人都有"的装饰字段。
	_check("石头 has_tag(stone) = true", bool(stone.call("has_tag", &"stone")))
	_check("石头 has_tag(fuel) = false", not bool(stone.call("has_tag", &"fuel")))
	_check("浆果 has_tag(food) = true", bool(berry.call("has_tag", &"food")))
	_check("浆果 has_tag(wood) = false", not bool(berry.call("has_tag", &"wood")))
	# 石斧按主创裁决为 Tool 类型；其标签只表达用途能力，不表达材料类别。
	_check("石斧 has_tag(tool) = true", bool(stone_axe.call("has_tag", &"tool")))
	_check("石斧 has_tag(cutting) = true", bool(stone_axe.call("has_tag", &"cutting")))
	_check("石斧 has_tag(wood_processing) = true", bool(stone_axe.call("has_tag", &"wood_processing")))
	_check("石斧 type = TOOL", int(stone_axe.get("type")) == TYPE_TOOL)
	# 工具不承担材料类标签：石斧不应带 building，也不应带 wood，避免标签语义被混用。
	_check("石斧 has_tag(building) = false（工具不承担材料标签）", not bool(stone_axe.call("has_tag", &"building")))
	_check("石斧 has_tag(wood) = false（工具不承担材料标签）", not bool(stone_axe.call("has_tag", &"wood")))
	# 边界用例：空标签与不存在的标签都必须返回假。
	_check("空标签 has_tag(\"\") = false", not bool(wood.call("has_tag", &"")))
	_check("未知标签 has_tag(no_such_tag) = false", not bool(wood.call("has_tag", &"no_such_tag")))

## 用临时实例验证边界行为：空定义、堆叠上限非法值、正常定义。
func _verify_boundaries() -> void:
	print("[ITEM-01] ---- 用例：is_valid / get_display_name 边界 ----")
	# 空定义：未设置 id 与显示名。
	var empty_definition: Resource = ItemDefinitionScript.new()
	_check("空定义 is_valid() = false", not bool(empty_definition.call("is_valid")))
	# 空定义的显示名应回退为占位文本，保证日志不出现空白。
	_check("空定义 get_display_name() 回退为占位文本", String(empty_definition.call("get_display_name")) == "<未命名物品>")
	# 只有 id、但堆叠上限为 0 的定义：应判定为无效。
	var zero_stack_definition: Resource = ItemDefinitionScript.new()
	zero_stack_definition.set("id", &"tmp_zero_stack")
	zero_stack_definition.set("max_stack", 0)
	_check("堆叠上限为 0 的定义 is_valid() = false", not bool(zero_stack_definition.call("is_valid")))
	# 合法定义：id 与堆叠上限均有效时判定为可用，且显示名回退为 id。
	var valid_definition: Resource = ItemDefinitionScript.new()
	valid_definition.set("id", &"tmp_valid")
	valid_definition.set("max_stack", 1)
	_check("合法定义 is_valid() = true", bool(valid_definition.call("is_valid")))
	_check("未填显示名时回退为 id", String(valid_definition.call("get_display_name")) == "tmp_valid")
	# 堆叠上限为 1 的定义不应被视为可堆叠。
	_check("堆叠上限为 1 时 is_stackable() = false", not bool(valid_definition.call("is_stackable")))

## 打印物品定义清单：本阶段"打印物品目录"的可读产出，替代尚不存在的背包界面。
func _print_catalog() -> void:
	print("[ITEM-01] ---- 物品定义清单（%s）----" % ITEM_DIR)
	# 固定顺序列目录，保证多次运行日志可比对。
	var paths: Array[String] = [
		ITEM_DIR + "wood.tres",
		ITEM_DIR + "stone.tres",
		ITEM_DIR + "berry.tres",
		ITEM_DIR + "stone_axe.tres",
	]
	# 逐条打印定义名、类型、堆叠上限与标签。
	for path: String in paths:
		var definition: Resource = load(path)
		# 目录打印阶段不再重复计数断言，缺失资源仅以提示行暴露。
		if definition == null:
			print("    %s -> <加载失败>" % path)
			continue
		print("    %s -> id=%s name=%s type=%d max_stack=%d tags=[%s]" % [
			path,
			definition.get("id"),
			definition.call("get_display_name"),
			int(definition.get("type")),
			int(definition.get("max_stack")),
			_tags_to_text(definition.get("tags")),
		])
	# 用一次类型汇总说明"数据驱动"的覆盖范围。
	print("[ITEM-01] 类型汇总：Material / Tool / Consumable 三类均有示例资源，Equipment 按批准暂不使用")
