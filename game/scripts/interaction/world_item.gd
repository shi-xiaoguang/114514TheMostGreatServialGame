extends Area3D
class_name WorldItem
## Robinson —— 可拾取物（任务编号 INTERACTION-01：最小拾取闭环）。
## 绑定对象：res://scenes/world_item.tscn 的根节点 WorldItem（Area3D）。
## 职责：侦测玩家是否进入范围；玩家在范围内并按下交互键时，把物品加入玩家背包；
##      确认全部放入后把自己从世界中移除。
## 最近者优先：范围内同时有多个可拾取物时，一次按键只允许"距离玩家最近"的那个完成拾取；
##            该判定由各物体自行查询 world_item 分组得出，不引入任何全局交互管理器。
## 防复制：① 写入背包前置位防止重复处理；② 先确认全部容纳，放不下时完全不改背包，
##        保证"物体消失 ⇔ 背包净增，物体保留 ⇔ 背包零变化"。
## 范围声明：本阶段没有界面、没有提示文字、没有制作/建造/对话，也没有通用交互框架。

# ==================== 常量 ====================

## 可拾取物分组名：用于"最近者优先"判定时枚举场上的全部同类物体。
const GROUP_WORLD_ITEM: StringName = &"world_item"

## 玩家分组名：与 player.tscn 中 Player 节点的 groups 保持一致。
const GROUP_PLAYER: StringName = &"player"

## 交互输入动作名：由 project.godot 的 [input] 段定义，本阶段绑定 E 键。
const ACTION_INTERACT: StringName = &"interact"

# ==================== 导出参数（在检视面板配置） ====================

## 本物体代表的物品定义：在检视面板中直接挂 resources/items 下的 .tres 资源。
@export var definition: ItemDefinition = null

## 一个世界物体代表多少件物品：默认 1 件。
@export_range(1, 9999, 1) var amount: int = 1

# ==================== 运行时状态 ====================

## 玩家当前是否在侦测范围内：由 Area3D 的 body_entered / body_exited 信号维护。
var _player_in_range: bool = false

## 范围内的玩家节点：用于计算距离，玩家离开时清空。
var _player: Node3D = null

## 是否已成功拾取：防止同一帧内的连续按键或重复投递把同一个物体拾取多次。
var _picked_up: bool = false

# ==================== 生命周期 ====================

## 节点入树后完成分组注册与信号连接。
func _ready() -> void:
	# 把自己加入可拾取物分组，使"最近者优先"判定能枚举到场上所有同类物体。
	add_to_group(GROUP_WORLD_ITEM)
	# 连接进入/离开范围两个信号，分别维护范围内状态与玩家引用。
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## 处理未被界面消费的输入：只关心交互键，其余事件原样放行。
func _unhandled_input(event: InputEvent) -> void:
	# 已经拾取成功的物体不再响应任何按键。
	if _picked_up:
		return
	# 玩家不在范围内时本物体不参与本次交互，也不消费事件。
	if not _player_in_range or not is_instance_valid(_player):
		return
	# 只响应"交互键按下"；is_action_pressed 默认排除长按自动重复事件(echo)。
	if not event.is_action_pressed(ACTION_INTERACT):
		return
	# 范围内有多个物体时，只有离玩家最近的那个允许拾取，避免一次按键拿走一片。
	if not _is_nearest_in_range():
		return
	# 消费本次按键事件：一次按键只触发一次拾取，避免其它节点重复处理同一个事件。
	get_viewport().set_input_as_handled()
	# 真正执行拾取。
	_try_pick_up()

# ==================== 公共查询（供其它可拾取物比较使用） ====================

## 供其它可拾取物查询：本物体当前是否处于玩家范围内。
func is_player_in_range() -> bool:
	return _player_in_range

## 供其它可拾取物查询：本物体是否已经拾取完成。
func is_picked_up() -> bool:
	return _picked_up

# ==================== 私有方法：侦测 ====================

## Area3D 侦测到实体进入范围：只关心玩家，其余实体一律忽略。
func _on_body_entered(body: Node3D) -> void:
	# 用分组判定玩家身份，避免依赖节点名或具体节点类型。
	if not body.is_in_group(GROUP_PLAYER):
		return
	# 记录玩家引用，供距离比较使用。
	_player = body
	# 置为"范围内"，此后按键才可能触发拾取。
	_player_in_range = true

## Area3D 侦测到实体离开范围：只有离开者就是当前记录的玩家时才清除状态。
func _on_body_exited(body: Node3D) -> void:
	# 离开者不是当前玩家（例如其它实体）时不影响状态。
	if body != _player:
		return
	# 玩家离开后不再响应交互键。
	_player_in_range = false
	# 清空玩家引用，避免用已离开的坐标做距离判断。
	_player = null

# ==================== 私有方法：最近者优先 ====================

## 判断本物体是否范围内离玩家最近；距离并列时以实例 ID 较小者为准，保证只选中一个。
func _is_nearest_in_range() -> bool:
	# 本物体到玩家的距离，作为比较基准。
	var my_distance: float = global_position.distance_to(_player.global_position)
	# 枚举场上所有可拾取物，逐一与自身比较。
	for node: Node in get_tree().get_nodes_in_group(GROUP_WORLD_ITEM):
		# 非 WorldItem 节点（例如手工放进分组的其它节点）不参与竞争。
		var other: WorldItem = node as WorldItem
		if other == null or other == self:
			continue
		# 已拾取完成的物体正在等待被释放，不再参与竞争。
		if other.is_picked_up():
			continue
		# 竞争者自己也必须在玩家范围内，才具备参与竞争的资格。
		if not other.is_player_in_range():
			continue
		# 计算竞争者与玩家的距离。
		var other_distance: float = other.global_position.distance_to(_player.global_position)
		# 存在更近的一方时本次不由自己拾取。
		if other_distance < my_distance:
			return false
		# 距离完全并列时用实例 ID 决出唯一胜者，避免两个物体同时拾取。
		# 仅在距离精确相等时比较 ID；近似比较会让略远与略近的对象互相退让。
		if other_distance == my_distance and other.get_instance_id() < get_instance_id():
			return false
	# 没有任何竞争者在距离或并列规则上胜过自己。
	return true

# ==================== 私有方法：拾取 ====================

## 尝试把本物体加入玩家背包；只有全部放入才移除自己。
func _try_pick_up() -> void:
	if _picked_up:
		return
	# 定义缺失属于配置错误：给出警告并保留物体，避免静默丢物。
	if definition == null:
		push_warning("[WorldItem] 节点 %s 未配置 ItemDefinition，本次拾取已忽略。" % name)
		return
	if amount <= 0 or not definition.is_valid():
		push_warning("[WorldItem] 节点 %s 的物品定义或数量无效，本次拾取已忽略。" % name)
		return
	# 玩家背包入口：本阶段唯一允许的取用方式。
	var inventory: Inventory = InventoryManager.inventory
	# 入口尚未就绪时放弃本次拾取，保证不出现空引用。
	if inventory == null:
		push_warning("[WorldItem] InventoryManager.inventory 尚未就绪，本次拾取已忽略。")
		return
	# 容量预检只读；失败不改堆顺序、数量，也不发出 changed 中间状态。
	if not inventory.can_add_item(definition, amount):
		push_warning("[WorldItem] 背包放不下 %s，本次拾取失败，背包未改变。" % definition.get_display_name())
		return
	# 预检与添加之间没有 await 或信号；添加完成后的 changed 回调也不能重复拾取此物。
	_picked_up = true
	var left: int = inventory.add_item(definition, amount)
	if left != 0:
		_picked_up = false
		push_error("[WorldItem] 容量预检与实际添加不一致，物体未移除。")
		return
	# 关闭侦测：本物体在等待释放期间不再参与"最近者"判定。
	set_deferred("monitoring", false)
	# 从世界中移除本物体，完成闭环的最后一步。
	queue_free()
