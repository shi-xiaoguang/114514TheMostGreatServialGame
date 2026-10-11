extends Resource
class_name ItemDefinition
## Robinson —— 物品定义（任务编号 ITEM-01：数据驱动物品定义体系）。
## 绑定对象：res://resources/items/ 目录下的 *.tres 资源文件（如 wood.tres、stone.tres）。
## 职责：用"一份数据资源描述一种物品"替代"每种物品一个专属脚本"；物品的身份与能力
##       全部落在下面的导出字段里，使用方只按 type 与 tags 判定行为，不对物品 id 写分支。
## 数据流：本类型是全局共享的只读定义；"某定义 + 数量"的实例组合由 INVENTORY-01 的
##         ItemStack 承担，本次不实现实例类。
## 范围声明：本阶段不含拾取、制作、装备、消耗、背包与任何界面；metadata 只是扩展槽位，
##           本文件既不读取也不写入它的内容。

# ==================== 类型枚举 ====================

## 物品类型：描述"这一大类物品能提供什么"，供使用方做粗粒度分流。
## 注意：具体用途判定一律用 tags，不要在业务代码里对 id 做判断。
enum ItemType {
	## 材料：只作为制作与建造的原料（木头、石头）。
	MATERIAL,
	## 工具：提供某种能力的工具（石斧）；装备槽位等留给 EQUIPMENT。
	TOOL,
	## 消耗品：使用后生效或消失的物资（浆果）。
	CONSUMABLE,
	## 装备：预留给未来装备系统（衣服、护甲、背包、装备槽），本阶段不使用。
	EQUIPMENT,
}

# ==================== 导出字段（在检视面板中数据化配置） ====================

## 物品唯一标识：仅用于存档键与跨系统查表；禁止作为行为分支的判定条件。
@export var id: StringName = &""

## 物品显示名（对应需求中的 name）：取名 display_name 以避开 Resource 自身的命名语义。
@export var display_name: String = ""

## 物品图标：本阶段仅预留字段，默认空，不加载任何外部贴图。
@export var icon: Texture2D = null

## 物品描述：本阶段仅预留字段，用多行文本便于在检视面板中书写说明。
@export_multiline var description: String = ""

## 物品类型：只做粗粒度分流；细粒度用途一律交给 tags。
@export var type: ItemType = ItemType.MATERIAL

## 单堆叠上限：需求中的"stack 数量"按此解读，取 1 表示不可堆叠。
@export_range(1, 9999, 1) var max_stack: int = 99

## 用途标签集合：如 wood、fuel、building、food；支持"按能力查询"而不依赖 id。
@export var tags: Array[StringName] = []

## 扩展字段：为未来属性（耐久、回复量、预制体路径等）预留；本阶段不读取其内容。
@export var metadata: Dictionary = {}

# ==================== 公共方法（只读查询） ====================

## 判断本物品是否带有指定标签：比较时大小写不敏感，避免检视面板手填 "Wood" 导致查询失效。
func has_tag(tag: StringName) -> bool:
	# 把待查标签归一化为小写字符串，作为后续逐项比较的基准。
	var wanted: String = String(tag).to_lower()
	# 逐个比较已配置标签：标签数量极少，线性遍历足够，不做索引缓存以免引入多余结构。
	for existing: StringName in tags:
		# 把已配置标签同样归一化为小写再比较，从而实现大小写不敏感匹配。
		if String(existing).to_lower() == wanted:
			# 命中任意一项即可确定为真，无需继续遍历剩余标签。
			return true
	# 遍历结束仍未命中，判定为不带该标签。
	return false

## 判断本物品是否可堆叠：堆叠上限大于 1 即视为可堆叠。
func is_stackable() -> bool:
	# 只以堆叠上限为唯一判据，避免出现第二个真相来源。
	return max_stack > 1

## 取用于显示的物品名：未填写 display_name 时回退为 id，保证日志与调试信息不出现空白。
func get_display_name() -> String:
	# display_name 已填写时直接使用策划配置的名称。
	if display_name != "":
		return display_name
	# 未填写显示名时以 id 兜底；id 也为空则返回占位文本，便于一眼看出配置缺失。
	return String(id) if id != &"" else "<未命名物品>"

## 校验本定义是否可用：id 非空且堆叠上限至少为 1；供测试与未来的资源校验调用。
func is_valid() -> bool:
	# id 是跨系统唯一标识，为空即视为无效定义。
	if id == &"":
		return false
	# 堆叠上限小于 1 的定义无法参与任何数量运算，同样视为无效。
	if max_stack < 1:
		return false
	# 两项必要条件均已满足。
	return true
