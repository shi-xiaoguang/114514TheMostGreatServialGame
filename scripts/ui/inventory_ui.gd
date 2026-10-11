extends CanvasLayer
class_name InventoryUI
## Robinson —— 背包查看界面（任务编号 UI-01：背包查看系统）。
## 绑定对象：res://scenes/ui/inventory_ui.tscn 的根节点 InventoryUI（CanvasLayer），
##          由正式入口 res://scenes/movement_test.tscn 实例化。
## 职责：按 Tab 显示/隐藏面板；监听 Inventory.changed 后重建网格，
##      把每个物品堆渲染为一个 InventorySlot（名称 + 数量）。
## 数据边界（严格只读）：只调用 Inventory.get_stacks() 并订阅 changed 信号；
##                      不调用 add_item / remove_item / clear，不读取 _stacks / capacity / get_used_slots()。
## 刷新策略：changed 触发即整体重建网格（格子数量很小，重建成本可忽略）；
##          面板隐藏时也照常刷新，保证打开瞬间内容就是最新的。
## 范围声明：本阶段不做拖拽、丢弃、合成、装备、快捷栏，也不处理鼠标释放与暂停——
##          鼠标捕获仍只由 player.gd 的 Esc 逻辑控制。

# ==================== 常量 ====================

## 背包格场景：每个物品堆对应一个实例，节点结构由 inventory_slot.tscn 固定。
const SLOT_SCENE: PackedScene = preload("res://scenes/ui/inventory_slot.tscn")

## 界面分组名：供测试与未来的界面管理查找本界面实例，不参与任何业务逻辑。
const GROUP_INVENTORY_UI: StringName = &"inventory_ui"

## 开关背包的输入动作名：由 project.godot 的 [input] 段定义，本阶段绑定 Tab 键。
const ACTION_TOGGLE: StringName = &"toggle_inventory"

# ==================== 导出参数 ====================

## 网格列数：纯布局旋钮，可在检视面板调整，不影响任何数据。
@export var columns: int = 5

# ==================== 节点引用 ====================

## 背包面板：Tab 开关的对象。
@onready var _panel: Control = $InventoryPanel

## 网格容器：每个物品堆对应一个子节点。
@onready var _grid: GridContainer = $InventoryPanel/VBox/ItemGrid

## 空背包提示：仅在没有任何物品堆时显示。
@onready var _empty_hint: Label = $InventoryPanel/VBox/EmptyHint

# ==================== 运行时状态 ====================

## 被观察的背包：只读持有，仅用于取内容副本与订阅变更信号。
var _inventory: Inventory = null

# ==================== 生命周期 ====================

## 节点入树后完成初始化：隐藏面板、应用列数、订阅背包变更并做首次渲染。
func _ready() -> void:
	# 加入界面分组，便于外部查找本界面实例。
	add_to_group(GROUP_INVENTORY_UI)
	# 初始为关闭状态，由玩家按 Tab 打开。
	_panel.visible = false
	# 应用导出参数中的列数。
	_grid.columns = columns
	# 取全局背包入口：数据层不修改，这里只读引用。
	_inventory = InventoryManager.inventory
	# 背包尚未就绪时给出警告并只做一次空渲染，避免空引用导致界面不出现。
	if _inventory == null:
		push_warning("[InventoryUI] InventoryManager.inventory 尚未就绪，界面不会自动刷新。")
		_refresh()
		return
	# 订阅变更信号：这是界面自动刷新的唯一触发来源。
	_inventory.changed.connect(_refresh)
	# 首次渲染，保证打开时看到的就是最新内容。
	_refresh()

## 处理未被界面消费的输入：只关心开关背包的按键。
func _unhandled_input(event: InputEvent) -> void:
	# 只响应"开关背包键按下"；is_action_pressed 默认排除长按自动重复事件。
	if not event.is_action_pressed(ACTION_TOGGLE):
		return
	# 消费本次事件，避免其它节点重复处理同一个按键。
	get_viewport().set_input_as_handled()
	# 在显示与隐藏之间双向切换。
	_panel.visible = not _panel.visible

# ==================== 界面刷新 ====================

## 按背包当前内容重建网格：只读取 get_stacks() 返回的副本，从不改动数据层。
func _refresh() -> void:
	# 清空旧格子：先摘除再释放，保证子节点数量立刻反映最新状态，便于外部核对。
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	# 取当前内容的副本；背包未就绪时按空背包处理。
	var stacks: Array[ItemStack] = []
	if _inventory != null:
		stacks = _inventory.get_stacks()
	# 空背包时只显示提示文本、不显示网格。
	_empty_hint.visible = stacks.is_empty()
	_grid.visible = not stacks.is_empty()
	# 逐堆新建格子并填充内容。
	for stack: ItemStack in stacks:
		# 每个物品堆一个格子实例，节点结构由 inventory_slot.tscn 固定。
		var slot: InventorySlot = SLOT_SCENE.instantiate() as InventorySlot
		_grid.add_child(slot)
		# 用堆的数据填充格子：只读取物品定义与数量，不写回数据层。
		slot.set_stack(stack.definition, stack.get_count())
