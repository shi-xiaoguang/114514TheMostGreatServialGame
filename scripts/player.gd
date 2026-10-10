extends CharacterBody3D
## Robinson —— 第一人称玩家控制器（任务编号 PLAYER-01：第一人称基础移动与观察）。
## 绑定对象：res://scenes/player.tscn 的根节点 Player（CharacterBody3D）。
## 职责：重力落地、WASD 相对角色朝向的水平移动、Shift 奔跑、固定耗时的线性加减速、
##       鼠标水平转向与摄像机俯仰钳制、Esc 双向切换鼠标捕获。
## 原点约定：本节点原点位于玩家脚底，因此站立碰撞体中心在本地 Y = +0.90，
##           摄像机视线高度由头部枢轴的本地 Y = +1.65 决定。
## 范围声明：本轮不含跳跃、蹲伏、迈台阶、陡坡、攀爬、体力等任何未批准功能。

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

# ==================== 节点引用（入树后一次性解析，避免逐帧查找节点） ====================

## 头部枢轴：只承担俯仰，水平转向交给玩家本体。
@onready var _head: Node3D = $Head

## 第一人称摄像机：位于头部枢轴之下，随枢轴一起俯仰。
@onready var _camera: Camera3D = $Head/Camera

# ==================== 运行时状态 ====================

## 重力加速度（米/秒²）：从项目设置读取，不硬编码。
var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

# ==================== 生命周期 ====================

## 节点入树后的初始化：确认玩家相机为本场景唯一生效相机，并立即捕获鼠标。
func _ready() -> void:
	# 显式把玩家相机置为当前相机，确保运行时不再由其他相机抢占画面。
	_camera.current = true
	# 运行时捕获鼠标：鼠标被隐藏并锁定在游戏窗口内，使鼠标移动直接驱动视角。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## 处理未被界面消费的输入：鼠标视角与 Esc 鼠标捕获切换。
func _unhandled_input(event: InputEvent) -> void:
	# 鼠标移动事件：仅在鼠标处于捕获状态时驱动视角，避免释放鼠标后画面仍在转动。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event as InputEventMouseMotion)
		return
	# Esc：在"捕获"与"释放"两种状态之间双向切换，释放后再次按下即可恢复捕获。
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()

## 每个物理帧执行：重力 → 读取移动输入 → 固定耗时线性加减速 → 位移与碰撞解算。
func _physics_process(delta: float) -> void:
	# 未站在地面上时按重力加速度累积下落速度，使角色最终落回地面。
	if not is_on_floor():
		velocity.y -= _gravity * delta
	# 读取 WASD 输入：get_vector 返回长度不超过 1 的向量，因此斜向移动不会产生额外速度加成。
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# 本帧目标速度：按住奔跑键取奔跑速度，否则取行走速度。
	var target_speed: float = run_speed if Input.is_action_pressed("sprint") else walk_speed
	# 把输入方向转换到角色自身的水平朝向上：Y 分量取 0，保证只产生水平移动。
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# 按固定耗时的线性过渡更新水平速度，使不同物理帧率下运动表现一致。
	_apply_horizontal_movement(direction, target_speed, delta)
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
func _apply_horizontal_movement(direction: Vector3, target_speed: float, delta: float) -> void:
	# 每帧线性步长 = 速率 × 物理帧时长，因此运动结果与物理帧率无关。
	var speed_step: float = 0.0
	if direction != Vector3.ZERO:
		# 加速段速率：在 acceleration_time 秒内从静止线性达到目标速度。
		speed_step = (target_speed / maxf(acceleration_time, MIN_TIME_SPAN)) * delta
	else:
		# 减速段速率：以当前水平速度为准，在 deceleration_time 秒内线性归零。
		speed_step = (_get_horizontal_speed() / maxf(deceleration_time, MIN_TIME_SPAN)) * delta
	# 目标速度向量保留当前垂直分量，使水平处理不影响重力下落。
	var target_velocity: Vector3 = Vector3(direction.x * target_speed, velocity.y, direction.z * target_speed)
	# move_toward 以线性方式逼近目标：到达后精确停住，不会过冲。
	velocity = velocity.move_toward(target_velocity, speed_step)

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
