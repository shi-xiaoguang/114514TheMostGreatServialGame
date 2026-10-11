extends Control
class_name InventorySlot
## Robinson —— 背包格（任务编号 UI-01：背包查看系统）。
## 绑定对象：res://scenes/ui/inventory_slot.tscn 的根节点 InventorySlot（Control）。
## 节点结构（固定）：InventorySlot(Control) → Icon(TextureRect) / Name(Label) / Count(Label)。
## 职责：把一个物品堆的数据填进三个子节点，只做显示，不持有任何数据、不回写数据层。
## 预留说明：Icon 位为未来的物品图标预留（当前所有 ItemDefinition.icon 均为空，因此本阶段始终不显示）；
##          多余的空白与固定尺寸也为未来的 tooltip 与选中状态预留，本阶段不实现这两项行为。
## 范围声明：不做拖拽、丢弃、合成、装备、快捷栏。本阶段只显示名称与数量。

# ==================== 节点引用 ====================

## 图标位：未来的物品图标显示区，本阶段保持为空。
@onready var _icon: TextureRect = $Icon

## 名称标签：显示物品显示名。
@onready var _name_label: Label = $Name

## 数量标签：以 "x数量" 形式显示。
@onready var _count_label: Label = $Count

# ==================== 公共方法 ====================

## 用一份物品定义与数量填充本格；定义缺失时显示占位文本，避免出现无法辨认的空白格。
func set_stack(definition: ItemDefinition, amount: int) -> void:
	# 定义缺失属于异常数据，用占位文本标注，便于一眼发现问题。
	if definition == null:
		_name_label.text = "<定义缺失>"
		# 数量位清空：没有定义时数量没有意义。
		_count_label.text = ""
		# 图标位清空。
		_icon.texture = null
		return
	# 名称优先取显示名；未填写显示名时 ItemDefinition.get_display_name() 会自动回退为 id。
	_name_label.text = definition.get_display_name()
	# 数量以 "x数量" 形式显示，便于一眼区分名称与数量。
	_count_label.text = "x%d" % amount
	# 图标位接上物品定义的图标字段：当前该字段恒为空，因此本阶段不会显示任何图标。
	_icon.texture = definition.icon
