extends Node
## PLAYER-04.3 当前参数基线；运行真实主场景与引擎物理帧，不手动调用玩家回调。
## godot --headless --path <正式仓库> res://tests/movement_test.tscn
## 本套件不覆盖已知的迈步中起跳、蹲伏过渡中离地缺陷，也不判定真人手感。

const ACTIONS: Array[StringName] = [
	&"move_forward", &"move_backward", &"move_left", &"move_right",
	&"sprint", &"jump", &"crouch",
]

@onready var _player: CharacterBody3D = $World/Player

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[MOVEMENT-BASELINE] 引擎 = %s；物理 Hz = %d" % [
		Engine.get_version_info()["string"], Engine.physics_ticks_per_second,
	])
	_check("当前基线使用 60Hz", Engine.physics_ticks_per_second == 60)
	await _place_player(Vector3(0.0, 0.1, 10.0))
	_check("平地稳定落地", _player.is_on_floor())
	var start: Vector3 = _player.global_position
	Input.action_press(&"move_forward")
	await _tick(30)
	_check_close("行走速度 m/s", _horizontal_speed(), 3.2, 0.02)
	_check("W 输入确实向前移动", _player.global_position.z < start.z - 1.0)
	Input.action_press(&"sprint")
	await _tick(30)
	_check_close("奔跑速度 m/s", _horizontal_speed(), 5.2, 0.02)
	await _jump_case()
	await _crouch_case()
	await _step_case()
	_release_all()
	print("[MOVEMENT-BASELINE] 汇总：PASS = %d，FAIL = %d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _jump_case() -> void:
	await _place_player(Vector3(0.0, 0.1, 10.0))
	_check("满按跳跃前已落地", _player.is_on_floor())
	var base: float = _player.global_position.y
	var peak: float = base
	var airborne: bool = false
	Input.action_press(&"jump")
	for _frame: int in range(100):
		await _tick()
		peak = maxf(peak, _player.global_position.y)
		airborne = airborne or not _player.is_on_floor()
	_check("空格输入确实起跳", airborne)
	_check_close("满按跳跃实测高度 m", peak - base, 0.951, 0.025)
	_check("长按跳跃结束后已落地", _player.is_on_floor())
	_check_close("落地回到原高度 m", _player.global_position.y, base, 0.02)
	Input.action_release(&"jump")


func _crouch_case() -> void:
	await _place_player(Vector3(0.0, 0.1, 10.0))
	var base: float = _player.global_position.y
	Input.action_press(&"crouch")
	await _tick(18)
	var collision: CollisionShape3D = _player.get_node("Collision") as CollisionShape3D
	var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
	_check("玩家胶囊存在", capsule != null)
	if capsule != null:
		_check_close("蹲伏胶囊高度 m", capsule.height, 1.2, 0.001)
	_check_close("蹲伏脚底保持原高度 m", _player.global_position.y, base, 0.02)
	Input.action_release(&"crouch")
	await _tick(18)
	if capsule != null:
		_check_close("净空足够时恢复站立高度 m", capsule.height, 1.8, 0.001)


func _step_case() -> void:
	await _place_player(Vector3(0.0, 0.1, -18.5))
	var count_before: int = int(_player.get("_step_up_count"))
	Input.action_press(&"move_forward")
	await _tick(70)
	Input.action_release(&"move_forward")
	_check("0.15m 台阶触发自动迈步", int(_player.get("_step_up_count")) > count_before)
	_check("越过台阶前缘并站在台面范围内",
		_player.global_position.z < -20.6 and _player.global_position.z > -23.4)
	_check_close("台面脚底高度 m", _player.global_position.y, 0.15, 0.025)
	_check("迈步后在台面稳定接地", _player.is_on_floor())


func _place_player(position: Vector3) -> void:
	_release_all()
	_player.global_position = position
	_player.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	await _tick(35)


func _tick(count: int = 1) -> void:
	for _frame: int in range(count):
		await get_tree().physics_frame
		# physics_frame 在节点物理回调前发出；等待处理帧后才读取本物理帧结果。
		await get_tree().process_frame


func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _release_all() -> void:
	for action: StringName in ACTIONS:
		Input.action_release(action)


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		print("[FAIL] ", label)


func _check_close(label: String, actual: float, expected: float, tolerance: float) -> void:
	_check("%s：实测 %.4f，预期 %.4f ± %.4f" % [label, actual, expected, tolerance],
		absf(actual - expected) <= tolerance)
