extends CharacterBody3D
## Robinson —— 第一人称玩家控制器（PLAYER-01：第一人称基础移动与观察；PLAYER-02：普通跳跃）。
## 绑定对象：res://scenes/player.tscn 的根节点 Player（CharacterBody3D）。
## 职责：重力落地、WASD 相对角色朝向的水平移动、Shift 奔跑、固定耗时的线性加减速、
##       鼠标水平转向与摄像机俯仰钳制、Esc 双向切换鼠标捕获、
##       空格起跳与可变跳跃高度、空中有限方向调整、0.10 秒离地宽限、禁止二段跳与长按重复触发。
## 原点约定：本节点原点位于玩家脚底，因此站立碰撞体中心在本地 Y = +0.90，
##           摄像机视线高度由头部枢轴的本地 Y = +1.65 决定。
## 跳跃约定：平地全程按住空格最高约 0.8 米（已批准）；轻点即松的最低高度由 min_jump_height 决定，
##           首版测试初值为 0.35 米（可调整，非已批准的最终数值）。
## 范围声明：本轮不含蹲伏、自动迈台阶、坡度跳跃衰减、陡坡滑动、蹬坡、攀爬、体力、摔落伤害、镜头晃动等任何未批准功能。

# ==================== 常量 ====================

## 时间参数下限保护值（秒），避免加速/减速时间被调成 0 或负数时出现除零。
const MIN_TIME_SPAN: float = 0.0001

# ==================== 导出参数（可在检视面板调整，便于试玩调参） ====================

## 行走目标速度（米/秒）：已批准的正常行走速度。
@export var walk_speed: float = 4.0

## 奔跑目标速度（米/秒）：按住奔跑键期间生效。
@export var run_speed: float = 6.5

## 线性加速到目标速度所需的固定耗时（秒）：已批准为 0.15 秒。
@export var acceleration_time: float = 0.15

## 从当前速度线性减速到静止所需的固定耗时（秒）：已批准为 0.12 秒。
@export var deceleration_time: float = 0.12

## 鼠标灵敏度（弧度/像素）：0.0025 约合 0.143 度/像素，水平转满 360 度约需 2513 像素。
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025

## 摄像机俯仰上下限（度）：正数代表抬头、负数代表低头，已批准为 85 度。
@export_range(1.0, 89.0, 1.0) var pitch_limit_deg: float = 85.0

# ==================== 导出参数：跳跃（PLAYER-02，可在检视面板调整以便试玩调参） ====================

## 平地满按跳跃的最高高度（米）：已批准为约 0.8 米，起跳初速由该高度与重力反解得到。
@export var max_jump_height: float = 0.8

## 轻点即松时的最低跳跃高度（米）：首版测试初值 0.35 米，可调整，非已批准的最终数值。
@export var min_jump_height: float = 0.35

## 空中方向修正系数（0~1）：首版测试初值 0.30，越小空中操控越弱；1.0 等于地面操控强度。
@export_range(0.0, 1.0, 0.01) var air_control_factor: float = 0.30

## 离地宽限（秒）：已批准为 0.10 秒，离开可站立地面后仍可在该时限内起跳一次。
@export var coyote_time: float = 0.10

# ==================== 节点引用（入树后一次性解析，避免逐帧查找节点） ====================

## 头部枢轴：只承担俯仰，水平转向交给玩家本体。
@onready var _head: Node3D = $Head

## 第一人称摄像机：位于头部枢轴之下，随枢轴一起俯仰。
@onready var _camera: Camera3D = $Head/Camera

# ==================== 运行时状态 ====================

## 重力加速度（米/秒²）：从项目设置读取，不硬编码。
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

## 离地宽限剩余时间（秒）：站在可站立地面时保持为 coyote_time，离地后按物理帧递减。
var _coyote_timer: float = 0.0

## 上一物理帧空格是否处于按下状态：只把"由未按下变为按下"当作一次新的起跳请求，
## 因此持续按住、键盘自动重复、以及长按被系统拆成连续按下事件，都不会重复触发起跳。
var _jump_pressed_last_frame: bool = false

## 本次离地是否已经执行过跳跃：起跳时置真，落地后复位，用于从根本上杜绝二段跳。
var _jump_consumed_in_air: bool = false

## 满按起跳初速（米/秒）：由 max_jump_height 与重力在 _ready 中反解得到。
var _max_jump_velocity: float = 0.0

## 松键削顶后的最低起跳速度（米/秒）：由 min_jump_height 与重力在 _ready 中反解得到。
var _min_jump_velocity: float = 0.0

# ==================== 生命周期 ====================

## 节点入树后的初始化：确认玩家相机为本场景唯一生效相机、立即捕获鼠标，并反解跳跃初速。
func _ready() -> void:
	# 显式把玩家相机置为当前相机，确保运行时不再由其他相机抢占画面。
	_camera.current = true
	# 运行时捕获鼠标：鼠标被隐藏并锁定在游戏窗口内，使鼠标移动直接驱动视角。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 由满按跳跃高度反解起跳初速：v = √(2gh)，平地即可跳到该高度。
	_max_jump_velocity = sqrt(2.0 * _gravity * maxf(max_jump_height, 0.0))
	# 由最低跳跃高度反解松键后的速度下限：低于该速度不再削顶，保证点按仍有最低高度。
	_min_jump_velocity = sqrt(2.0 * _gravity * maxf(min_jump_height, 0.0))
	# 防御性钳制：若最低高度被调得高于最高高度，则退化为不削顶，避免点按反而跳得更高。
	_min_jump_velocity = minf(_min_jump_velocity, _max_jump_velocity)

## 处理未被界面消费的输入：鼠标视角与 Esc 鼠标捕获切换。
func _unhandled_input(event: InputEvent) -> void:
	# 鼠标移动事件：仅在鼠标处于捕获状态时驱动视角，避免释放鼠标后画面仍在转动。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event as InputEventMouseMotion)
		return
	# Esc：在"捕获"与"释放"两种状态之间双向切换，释放后再次按下即可恢复捕获。
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()

## 每物理帧执行：离地宽限维护 → 重力 → 起跳判定 → 松键削顶 → 读取移动输入 → 固定耗时线性加减速 → 位移与碰撞解算。
func _physics_process(delta: float) -> void:
	# 先维护离地宽限计时器与落地复位，其结果供本帧起跳判定使用。
	_update_coyote_timer(delta)
	# 读取空格是否按下，并与上一物理帧比较得到"新的按下"边沿：按住不放不会产生边沿。
	var jump_held: bool = Input.is_action_pressed("jump")
	var jump_pressed_edge: bool = jump_held and not _jump_pressed_last_frame
	_jump_pressed_last_frame = jump_held
	# 未站在地面上时按重力加速度累积下落速度，使角色最终落回地面。
	if not is_on_floor():
		velocity.y -= _gravity * delta
	# 尝试起跳：只有出现新的按下边沿、处于宽限内、且本次离地尚未跳跃时才执行。
	_try_start_jump(jump_pressed_edge)
	# 松键削顶：已松开空格时把上升速度截断到最低起跳速度，实现轻点跳得低、按住跳得高。
	_apply_jump_release_cut()
	# 读取 WASD 输入：get_vector 返回长度不超过 1 的向量，因此斜向移动不会产生额外速度加成。
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# 本帧目标速度：按住奔跑键取奔跑速度，否则取行走速度。
	var target_speed: float = run_speed if Input.is_action_pressed("sprint") else walk_speed
	# 把输入方向转换到角色自身的水平朝向上：Y 分量取 0，保证只产生水平移动。
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# 水平移动按所处状态分流：地面给全额操控权威，空中只给有限权威并保留惯性。
	if is_on_floor():
		# 地面：使用默认权威系数 1.0，与 PLAYER-01 的加减速表现逐字一致。
		_apply_horizontal_movement(direction, target_speed, delta)
	else:
		# 空中且有方向输入：按 air_control_factor 削弱操控，使空中转向明显慢于地面。
		if direction != Vector3.ZERO:
			_apply_horizontal_movement(direction, target_speed, delta, air_control_factor)
		# 空中且无方向输入：完全不动水平速度，保留起跳与飞行中的惯性，不会急转或急停。
	# 交给物理引擎做位移与碰撞解算，保证角色站得住、不穿过地面。
	move_and_slide()

# ==================== 私有方法 ====================

## 鼠标视角：水平旋转玩家本体（可 360 度自由转向），上下旋转头部枢轴并钳制俯仰角。
func _handle_mouse_look(mouse_event: InputEventMouseMotion) -> void:
	# 水平转向作用在玩家本体上：取负号使鼠标右移时视线向右转。
	rotate_y(-mouse_event.relative.x * mouse_sensitivity)
	# 俯仰作用在头部枢轴上：取负号使鼠标上推时抬头、下推时低头。
	_head.rotate_x(-mouse_event.relative.y * mouse_sensitivity)
	# 把俯仰角限制在 ±85 度之内，避免视线翻转或越过正上方。
	_head.rotation.x = clampf(_head.rotation.x, -deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))

## 水平速度的固定耗时线性过渡：有输入时按加速时间逼近目标速度，无输入时按减速时间归零。
## authority 为操控权威系数：1.0 表示地面全额操控，小于 1.0 表示空中有限操控（过渡更慢、转向更迟钝）。
func _apply_horizontal_movement(direction: Vector3, target_speed: float, delta: float, authority: float = 1.0) -> void:
	# 每帧线性步长 = 速率 × 物理帧时长，因此运动结果与物理帧率无关。
	var speed_step: float = 0.0
	if direction != Vector3.ZERO:
		# 加速段速率：在 acceleration_time 秒内从静止线性达到目标速度。
		speed_step = (target_speed / maxf(acceleration_time, MIN_TIME_SPAN)) * delta
	else:
		# 减速段速率：以当前水平速度为准，在 deceleration_time 秒内线性归零。
		speed_step = (_get_horizontal_speed() / maxf(deceleration_time, MIN_TIME_SPAN)) * delta
	# 按操控权威缩放本帧步长：地面传 1.0，与 PLAYER-01 的行为完全一致；空中传 air_control_factor。
	speed_step *= maxf(authority, 0.0)
	# 目标速度向量保留当前垂直分量，使水平处理不影响重力下落。
	var target_velocity: Vector3 = Vector3(direction.x * target_speed, velocity.y, direction.z * target_speed)
	# move_toward 以线性方式逼近目标：到达后精确停住，不会过冲。
	velocity = velocity.move_toward(target_velocity, speed_step)

## 维护离地宽限计时器：站在可站立地面时充满、离地后按物理帧递减；落地同时复位跳跃消费标记。
func _update_coyote_timer(delta: float) -> void:
	# 站立状态取自上一物理帧的碰撞解算结果，与 move_and_slide 的判定完全一致。
	if is_on_floor():
		# 站在可站立地面：离地宽限充满，表示眼下随时可以起跳。
		_coyote_timer = coyote_time
		# 站在可站立地面：复位跳跃消费标记，使下一次离地能重新获得一次起跳机会。
		_jump_consumed_in_air = false
	else:
		# 已离地：宽限按物理帧时长递减，减到 0 即表示超过 0.10 秒，不再允许离地起跳。
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

## 起跳判定：只有出现新的按下边沿、处于离地宽限之内、且本次离地尚未跳跃时，才执行一次起跳。
## 本函数不再有任何"提前按键预约落地起跳"的逻辑：空中按下空格不会在落地时被兑现。
func _try_start_jump(pressed_edge: bool) -> void:
	# 本帧没有出现新的按下边沿（例如一直按住不放）：不顺延、不补跳，直接不起跳。
	if not pressed_edge:
		return
	# 宽限已耗尽：既不站在地面、离开地面也超过 0.10 秒，本帧不起跳。
	if _coyote_timer <= 0.0:
		return
	# 本次离地已经跳过：直接拒绝，从根本上杜绝二段跳与重复触发。
	if _jump_consumed_in_air:
		return
	# 起跳：把垂直速度直接置为满按初速，跳跃高度由该初速与重力共同决定。
	velocity.y = _max_jump_velocity
	# 记录本次离地已用掉跳跃机会，落地前不再允许第二次。
	_jump_consumed_in_air = true
	# 消费离地宽限：避免同一帧或紧随其后的帧被再次判定为可起跳。
	_coyote_timer = 0.0

## 松键削顶：未按住空格且仍在上升时，把上升速度截断到最低起跳速度，实现可变跳跃高度。
func _apply_jump_release_cut() -> void:
	# 站在地面时不存在上升过程，无需处理。
	if is_on_floor():
		return
	# 仍按住空格：保持满按初速继续上升，不做任何削减，因此按住会跳得更高。
	if Input.is_action_pressed("jump"):
		return
	# 本次离地未执行过跳跃（例如直接走下台阶）：不参与削顶。
	if not _jump_consumed_in_air:
		return
	# 速度已降到最低起跳速度及以下（接近最高点或正在下落）：不再削减，保证点按仍有最低高度。
	if velocity.y <= _min_jump_velocity:
		return
	# 把上升速度截断到最低起跳速度：只改速度不改位置，因此不会出现任何瞬间位移。
	velocity.y = _min_jump_velocity

## 取当前水平速度大小（米/秒）：只算 XZ 分量，下落速度不参与减速计算。
func _get_horizontal_speed() -> float:
	# Vector2 长度即为水平面上的速度大小。
	return Vector2(velocity.x, velocity.z).length()

## 在"捕获鼠标"与"释放鼠标"之间双向切换。
func _toggle_mouse_capture() -> void:
	# 当前已捕获则释放鼠标；否则（含已释放状态）重新捕获，保证 Esc 可反复双向切换。
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
