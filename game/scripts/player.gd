extends CharacterBody3D
## Robinson —— 第一人称玩家控制器（PLAYER-01：第一人称基础移动与观察；PLAYER-02：普通跳跃；PLAYER-03：按住式蹲伏；PLAYER-04：自然迈步；PLAYER-04.1：竖直分帧；PLAYER-04.2：自然迈步运动；PLAYER-04.3：地面高度连续化）。
## 绑定对象：res://scenes/player.tscn 的根节点 Player（CharacterBody3D）。
## 职责：重力落地、WASD 相对角色朝向的水平移动、Shift 奔跑、固定耗时的线性加减速、
##       鼠标水平转向与摄像机俯仰钳制、Esc 双向切换鼠标捕获、
##       空格起跳与可变跳跃高度、空中有限方向调整、0.10 秒离地宽限、禁止二段跳与长按重复触发、
##       按住 Ctrl 进入蹲伏与松开 Ctrl 请求起身（0.25 秒平滑过渡）、蹲伏移动降速、蹲伏禁跳、
##       起身前的头顶净空检测与空间不足时保持蹲伏、
##       被小型地形障碍挡住时的自然迈步（站立最高 0.20 米、完全蹲伏最高 0.10 米）。
## 原点约定：本节点原点位于玩家脚底，因此站立碰撞体中心在本地 Y = +0.90，
##           摄像机视线高度由头部枢轴的本地 Y = +1.65 决定。
## 跳跃约定：平地全程按住空格的最高高度由 max_jump_height 反解起跳初速得到；由于半隐式欧拉的离散积分偏差，
##           参数值会略低于实际最高点（PLAYER-TUNE-01 取 0.915 米，平地 60Hz 实测最高点约 0.95 米）；
##           轻点即松的最低高度由 min_jump_height 决定，首版测试初值为 0.35 米（可调整，非已批准的最终数值）。
## 蹲伏约定：姿态由单一混合量 _crouch_amount（0 = 完全站立，1 = 完全蹲伏）表示，进/出各 0.25 秒线性过渡；
##           碰撞胶囊中心恒等于"高度的一半"，因此胶囊底面始终落在脚底，全程脚底稳定不跳动；
##           按住 Ctrl 是进入蹲伏的**唯一途径**，系统在任何情况下都不会主动把玩家切成蹲伏；
##           顶部障碍只影响"能否起身"：完全站立时不做净空判定、也不改变姿态，
##           仅在已蹲伏/起身中松开 Ctrl 时，空间不足才保持蹲伏，空间恢复后自动起身；
##           起身采用**承诺式**决策：先用完整站立胶囊检测一次，空间足够才启动 0.25 秒过渡；
##           一旦承诺起身，过渡期间不再重判、不允许中途取消，直到完成，从而不会与几何互相拉扯震荡；
##           蹲伏姿态与过渡期间禁止起跳；空中不改变姿态，只记录"此刻是否仍按住 Ctrl"的蹲伏意图，
##           落地当帧结算一次即清零（刻意区别于跳跃缓冲，不形成动作缓存链）。
## 迈步约定（PLAYER-04）：只处理"被竖直立面挡住"的小台阶、小型岩石与地面接缝，站立最高 0.20 米、完全蹲伏最高 0.10 米；
##           判定顺序为 竖直面筛选 → 上探（抬高后是否与几何相交）→ 前探（前进后是否与几何相交）→ 下探（落脚面是否可行走且高差在界内），
##           三项全部通过才把玩家放到落脚面上方；任何一项不通过都**完全不动作**，因此"失败即被正常挡住"，
##           而不是"被系统抬了一格"；
##           这不是攀爬、不是辅助跳跃：全程不写 velocity、不改胶囊尺寸、空中一律不处理，
##           因此水平速度连续性不被中断、跳跃高度与空中控制完全不受影响；
##           0.30 米及以上障碍、假山岩体、跑酷台面，以及一切坡面（含 30 度连续凸起与 15 度上下坡）都不处理。
## 迈步轨迹约定（PLAYER-04.3）：目标不是模拟真人踩台阶，而是让第一人称下"地面高度连续变化"——
##           消除瞬移感、升降平台感、速度断层与镜头跳动；
##           命中后把整段位移（竖直抬升 + 水平 0.40m 前移）预先算成一张逐帧绝对坐标轨迹，逐帧一次赋值；
##           总帧数按台阶高差自适应（默认 h=0.10→6 帧、h=0.15→8 帧、h=0.20→10 帧，小台阶快速通过、大台阶更平滑）；
##           水平按"缓起—稳定—缓收"的形状权重分配，不做末帧集中补足；
##           竖直不人为设定帧数，而是逐帧用引擎前探反推"放行该帧水平位移所需的最小抬升"（受每帧上限约束），
##           因此自然形成缓入—峰值—缓出的钟形，也不会产生多余抬升；
##           相机**保持刚性**：不做任何提前量、滞后或头部动作模拟，镜头平滑完全由身体轨迹的连续性保证；
##           末帧竖直收口到"落脚面 + step_safe_gap × 收口比例"，消除过渡后被贴地吸附单帧下拉造成的镜头跳动；
##           过渡期间竖直速度钳制为非负，水平速度全程零写入（移动系统零改动）；
##           过渡期间不受理新的迈步触发，避免轨迹被反复重建；轨迹若因瞬移而失效则立即弃用。
## 范围声明：本轮含 PLAYER-03 按住式蹲伏、PLAYER-04 自然迈步、PLAYER-04.1 竖直分帧、PLAYER-04.2 自然迈步运动
##           与 PLAYER-04.3 地面高度连续化；不含匍匐、滑铲、潜行、噪音、战斗、动画系统，
##           也不含下台阶与落步平滑、坡度跳跃衰减、陡坡滑动、蹬坡、攀爬、体力、摔落伤害、镜头晃动等任何未批准功能。

# ==================== 常量 ====================

## 时间参数下限保护值（秒），避免加速/减速时间被调成 0 或负数时出现除零。
const MIN_TIME_SPAN: float = 0.0001

## 起身净空检测的向上余量（米）：把探测胶囊整体抬高该值，避免脚底贴地时因浮点误差把地面误判成阻挡。
const HEADROOM_MARGIN: float = 0.02

## 起身净空检测中"已被蹲姿占据"的参考探测胶囊高度收缩量（米）。
## 该参考胶囊只用于判断"某个物体是不是蹲着时本来就贴着身体的"，收缩后其顶面仍低于蹲伏胶囊顶面，
## 因此参考区域始终完全落在蹲伏身体实际占据的空间之内（物理上站得住的解释成立）。
## 若不收缩，顶棚只要"刚好贴住蹲伏胶囊顶面"就会被差集当作无关物体过滤掉，于是"空间不足"被误判成
## "空间足够"，错误开启起身过渡，进而与几何互相拉扯产生上下震荡。
const HEADROOM_ADJACENT_INSET: float = 0.15

## 迈步高差判定的浮点容差（米）：台阶顶面高度与 step_height 完全相等时，避免因浮点误差被误判为"超出上限"。
## 取值 1 毫米，远小于任何有意义的台阶高差，因此不会把真正超界的台阶放行。
const STEP_HEIGHT_EPSILON: float = 0.001

## 迈步水平前探的安全余量（米）：引擎前探结果再收缩该值，避免把胶囊停在"刚好相切"的临界位置。
const STEP_ENVELOPE_MARGIN: float = 0.003

## 迈步轨迹的最大允许偏离（米）：轨迹存的是绝对坐标，若玩家在两帧之间被瞬移（重生、传送、被外力推开等）
## 而偏离上一帧写入位置超过该值，就判定"这段轨迹已失效"并立即弃用，避免把玩家拖回旧目标点。
## 阈值取 0.3m：远大于单帧正常位移（最高奔跑速度 5.2m/s 时约 0.09m），因此不会误弃用正常轨迹。
const STEP_PLAN_MAX_DEVIATION: float = 0.3

## 迈步轨迹竖直反推的二分步数（PLAYER-04.3）：每帧用引擎前探二分出"放行该帧水平位移所需的最小抬升"。
## 8 步可把抬升搜索区间（每帧上限约 0.045m）收敛到约 0.2mm，精度足够而开销极小。
const STEP_HEIGHT_BISECT_STEPS: int = 8

## 水平速度剖面的"缓起"权重（PLAYER-04.3）：前两帧分别只推进比例份额的该倍数，
## 避免迈步第一帧就把水平位移推得过快，并让竖直抬升获得缓入的初始节奏。
const STEP_ADVANCE_RAMP_WEIGHTS: Array[float] = [0.5, 0.8]

## 水平速度剖面的"缓收"权重（PLAYER-04.3）：最后两帧分别推进比例份额的该倍数，
## 使水平速度平滑收住，而不是在最后一帧集中补足（消除"补偿式前冲"）。
const STEP_ADVANCE_TAPER_WEIGHTS: Array[float] = [1.0, 0.85]

# ==================== 导出参数（可在检视面板调整，便于试玩调参） ====================

## 行走目标速度（米/秒）：PLAYER-TUNE-01（平衡型 v1.1）对比实验测试值 3.2，属临时实验值、非最终定稿。
@export var walk_speed: float = 3.2

## 奔跑目标速度（米/秒）：按住奔跑键期间生效；PLAYER-TUNE-01 对比实验测试值 5.2，属临时实验值、非最终定稿。
@export var run_speed: float = 5.2

## 线性加速到目标速度所需的固定耗时（秒）：已批准为 0.15 秒。
@export var acceleration_time: float = 0.15

## 从当前速度线性减速到静止所需的固定耗时（秒）：已批准为 0.12 秒。
@export var deceleration_time: float = 0.12

## 鼠标灵敏度（弧度/像素）：0.0025 约合 0.143 度/像素，水平转满 360 度约需 2513 像素。
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025

## 摄像机俯仰上下限（度）：正数代表抬头、负数代表低头，已批准为 85 度。
@export_range(1.0, 89.0, 1.0) var pitch_limit_deg: float = 85.0

# ==================== 导出参数：跳跃（PLAYER-02，可在检视面板调整以便试玩调参） ====================

## 平地满按跳跃的最高高度（米）：起跳初速由该高度与重力反解得到 v0 = √(2gh)。
## 注意离散积分偏差：半隐式欧拉的实际最高点会略高于本参数值；PLAYER-TUNE-01 取 0.915，
## 对应平地 60Hz 条件下实测最高点约 0.95 米（该参数属临时实验值、非最终定稿）。
@export var max_jump_height: float = 0.915

## 轻点即松时的最低跳跃高度（米）：首版测试初值 0.35 米，可调整，非已批准的最终数值。
@export var min_jump_height: float = 0.35

## 空中方向修正系数（0~1）：首版测试初值 0.30，越小空中操控越弱；1.0 等于地面操控强度。
@export_range(0.0, 1.0, 0.01) var air_control_factor: float = 0.30

## 离地宽限（秒）：已批准为 0.10 秒，离开可站立地面后仍可在该时限内起跳一次。
@export var coyote_time: float = 0.10

# ==================== 导出参数：蹲伏（PLAYER-03，可在检视面板调整以便试玩调参） ====================

## 蹲伏移动目标速度（米/秒）：已批准为 2.0，明显低于行走 3.2，使蹲伏移动更沉稳。
@export var crouch_speed: float = 2.0

## 蹲伏线性加速到目标速度所需的固定耗时（秒）：已批准为 0.25，比站立的 0.15 更慢。
@export var crouch_acceleration_time: float = 0.25

## 蹲伏从当前速度线性减速到静止所需的固定耗时（秒）：已批准为 0.20，比站立的 0.12 更慢。
@export var crouch_deceleration_time: float = 0.20

## 进入蹲伏与退出蹲伏各自的单向过渡耗时（秒）：已批准为 0.25，进/出同为该值因而天然对称。
@export var crouch_transition_time: float = 0.25

## 站立时碰撞胶囊的总高（米）：与场景中 CapsuleShape3D 的初始 height 一致，为 1.8。
@export var stand_height: float = 1.8

## 蹲伏时碰撞胶囊的总高（米）：已批准为 1.2。
@export var crouch_height: float = 1.2

## 站立时摄像机（视线）高度（米）：与场景中头部枢轴的初始本地 Y 一致，为 1.65。
@export var stand_head_height: float = 1.65

## 蹲伏时摄像机（视线）高度（米）：已批准为 1.05。
@export var crouch_head_height: float = 1.05

# ==================== 导出参数：自然迈步（PLAYER-04，可在检视面板调整以便后续平衡调整） ====================

## 站立时允许自动迈上的最大高差（米）：已批准为 0.20；超过该高度的一律不处理，保持阻挡。
@export var step_height: float = 0.20

## 完全蹲伏时允许自动迈上的最大高差（米）：已批准为 0.10，低于站立值，符合低姿态通行的直觉。
## 姿态过渡期间允许高度在两者之间连续取值，不会在过渡中跳变。
@export var crouch_step_height: float = 0.10

## 前探水平距离在胶囊半径之上额外增加的余量（米）：保证迈步落位后脚底确实越过台阶边缘。
@export var step_forward_margin: float = 0.05

## 低于该高差视为微小起伏（米）：不单独做迈步处理，交给既有的 move_and_slide 自然吸收。
@export var step_min_height: float = 0.02

## 迈步落位时在落脚面之上保留的间隙（米）：避免脚底与台阶顶面零距离接触而产生抖动。
@export var step_safe_gap: float = 0.01

# ==================== 导出参数：迈步轨迹（PLAYER-04.3） ====================

## 迈步轨迹总开关：true 启用"按高度自适应时长 + 几何包络反推竖直"的连续化轨迹；
## false 时完全退化为单帧到位（PLAYER-04.1 之前的行为），便于 A/B 对照与一键回退。
## 本开关不参与任何"能否迈步"的判定，只影响迈步发生的过渡表现。
@export var step_motion_enabled: bool = true

## 竖直方向每帧允许的最大上升量（米）：作为"反推抬升"的安全上限（不是定帧依据）。
## 0.045 约合 2.7m/s 的抬升速度，明显低于 PLAYER-04.2 的 0.070（4.18m/s），用于消除单帧抬升感。
@export var step_motion_max_rise_per_frame: float = 0.045

## 过渡总帧数下限：小台阶（约 0.10m）取该值，保证快速通过、不拖慢移动。
@export var step_motion_frames_min: int = 6

## 过渡总帧数上限：最大可迈高度（0.20m）取该值，保证足够平滑。
@export var step_motion_frames_max: int = 10

## 过渡总帧数的参考高度（米）：与下面两项共同构成"按高度线性决定总帧数"的规则。
@export var step_motion_frames_base_height: float = 0.10

## 参考高度处的基础帧数：默认配置得到 h=0.10→6 帧、h=0.15→8 帧、h=0.20→10 帧，
## 正好对应主创定稿的"小台阶快速通过、大台阶更平滑"。
@export var step_motion_frames_base: int = 6

## 高度每增加 1 米所增加的过渡帧数：默认 40 帧/米。
@export var step_motion_frames_per_meter: float = 40.0

## 轨迹最终贴地比例：最终脚底高度 = 落脚面 + step_safe_gap × 本比例。
## 实测静置时脚底高度约为"落脚面 + 0.4mm"，因此取 0.05（即 0.5mm）可让轨迹终点直接落在静置高度上，
## 从而彻底消除"过渡后被贴地吸附单帧下拉"造成的镜头跳动；该值可在检视面板微调。
@export var step_motion_settle_ratio: float = 0.05

# ==================== 节点引用（入树后一次性解析，避免逐帧查找节点） ====================

## 头部枢轴：只承担俯仰，水平转向交给玩家本体。
@onready var _head: Node3D = $Head

## 第一人称摄像机：位于头部枢轴之下，随枢轴一起俯仰。
@onready var _camera: Camera3D = $Head/Camera

## 碰撞形状节点：蹲伏过渡时按混合量改写其本地 Y 与胶囊高度，使胶囊底面始终贴住脚底。
@onready var _collision: CollisionShape3D = $Collision

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

## 蹲伏混合量：0 表示完全站立、1 表示完全蹲伏，过渡期间取中间值，是姿态的唯一权威来源。
var _crouch_amount: float = 0.0

## 蹲伏目标：1 表示本帧期望处于蹲伏，0 表示期望起身站立；每物理帧按输入与净空情况刷新。
## 注意这里只有"当前目标"，没有过渡计时器，因此重复按 Ctrl 无法重置过渡进度。
var _crouch_target: float = 0.0

## 空中蹲伏意图：只记录"此刻是否仍持续按住 Ctrl"，松开即清零，落地当帧一次性结算后立即失效。
## 该变量刻意不同于跳跃缓冲，它不保存历史按键、不做延时兑现，只表达当前姿态需求。
var _crouch_intent_in_air: bool = false

## 本玩家自己的碰撞胶囊（_ready 中复制为独立资源后持有）：蹲伏过渡时直接改写它的 height。
var _collision_capsule: CapsuleShape3D = null

## 解析后的站立碰撞胶囊总高（米）：已按引擎约束"总高 ≥ 2 × 半径"钳制，避免参数被调成非法值。
var _stand_collision_height: float = 1.8

## 解析后的蹲伏碰撞胶囊总高（米）：已钳制在 [2 × 半径, 站立总高] 区间内。
var _crouch_collision_height: float = 1.2

## 参考探测胶囊总高（米）：= 蹲伏总高 − HEADROOM_ADJACENT_INSET，用于判定"已被蹲姿占据"的空间。
var _headroom_adjacent_height: float = 1.05

## 站立尺寸的形状查询参数：_ready 中建立并全程复用，每帧只刷新其 transform，避免逐帧新建资源。
var _stand_probe_query: PhysicsShapeQueryParameters3D = null

## 蹲伏尺寸的形状查询参数：用于判定"蹲着时本来就贴着身体的物体"，与站立探测结果做差集。
var _crouch_probe_query: PhysicsShapeQueryParameters3D = null

## 迈步探测胶囊（PLAYER-04）：与玩家**当前实际胶囊**同尺寸，_ready 中建立并全程复用，避免逐帧新建资源。
var _step_probe_shape: CapsuleShape3D = null

## 迈步探测的形状查询参数：复用同一个对象，每次只改写它的 transform。
var _step_probe_query: PhysicsShapeQueryParameters3D = null

## 迈步成功次数（只读计数）：仅供测试与调试观测，不参与任何行为判定。
var _step_up_count: int = 0

## 迈步过渡的最终落点（PLAYER-04.2）：水平越过台阶棱边、竖直到达台面上方间隙处。
## 该点同时是整段轨迹的最后一帧目标，因此落点与 PLAYER-04.1 逐字一致。
var _step_up_final_position: Vector3 = Vector3.ZERO

## 迈步过渡的逐帧目标位置表（绝对世界坐标）：下标即帧序，最后一帧恒等于 _step_up_final_position。
## 整段轨迹在触发当帧一次算好，逐帧只做一次赋值，因此不会出现相对累加造成的浮点漂移。
var _step_up_plan: Array[Vector3] = []

## 迈步过渡已应用到第几帧：等于 _step_up_plan.size() 时表示整段轨迹已走完。
var _step_up_plan_index: int = 0

## 迈步过渡的剩余帧数：大于 0 表示过渡进行中，同时充当"过渡期间不受理新迈步"的门禁条件。
var _step_up_frames_left: int = 0

## 迈步轨迹上一帧写入的位置（米）：用于检测玩家是否在两帧之间被瞬移，从而及时弃用失效轨迹。
var _step_up_reference_position: Vector3 = Vector3.ZERO

## 过渡期间被拦下的重复迈步触发次数（只读计数）：仅供测试证明"过渡中会反复满足迈步条件"这一事实。
var _step_up_retry_blocked: int = 0

# ==================== 生命周期 ====================

## 节点入树后的初始化：确认玩家相机为本场景唯一生效相机、立即捕获鼠标、反解跳跃初速，并准备蹲伏所需资源。
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
	# 准备蹲伏所需的碰撞胶囊、净空探测形状与查询参数。
	_setup_crouch()
	# 准备自然迈步所需的探测胶囊与查询参数（必须放在蹲伏初始化之后：它要读取已复制的碰撞胶囊）。
	_setup_step_up()

## 处理未被界面消费的输入：鼠标视角与 Esc 鼠标捕获切换。
func _unhandled_input(event: InputEvent) -> void:
	# 鼠标移动事件：仅在鼠标处于捕获状态时驱动视角，避免释放鼠标后画面仍在转动。
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event as InputEventMouseMotion)
		return
	# Esc：在"捕获"与"释放"两种状态之间双向切换，释放后再次按下即可恢复捕获。
	if event.is_action_pressed("ui_cancel"):
		_toggle_mouse_capture()

## 每物理帧执行：离地宽限维护 → 重力 → 蹲伏姿态维护 → 起跳判定 → 松键削顶 → 读取移动输入 → 固定耗时线性加减速 → 位移与碰撞解算 → 自然迈步。
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
	# 维护蹲伏姿态：读取 Ctrl、结算空中意图、推进混合量并落到碰撞体与摄像机高度上。
	# 放在起跳判定之前，使本帧的"蹲伏禁跳"门禁读到的是最新姿态。
	_update_crouch(delta)
	# 尝试起跳：只有出现新的按下边沿、处于宽限内、且本次离地尚未跳跃时才执行。
	_try_start_jump(jump_pressed_edge)
	# 松键削顶：已松开空格时把上升速度截断到最低起跳速度，实现轻点跳得低、按住跳得高。
	_apply_jump_release_cut()
	# 读取 WASD 输入：get_vector 返回长度不超过 1 的向量，因此斜向移动不会产生额外速度加成。
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	# 本帧移动参数：默认沿用站立的地面加减速时间，只有蹲伏时才换成蹲伏参数。
	var accel_time: float = acceleration_time
	var decel_time: float = deceleration_time
	# 本帧目标速度：按住奔跑键取奔跑速度，否则取行走速度。
	var target_speed: float = run_speed if Input.is_action_pressed("sprint") else walk_speed
	# 蹲伏移动：仅当"处于地面且已进入蹲伏姿态"时改用 2.0 速度与更慢的加减速，并忽略奔跑键。
	# 这样站立的 3.2 / 5.2 与空中控制行为完全不受影响。
	if _crouch_amount > 0.0 and is_on_floor():
		target_speed = crouch_speed
		accel_time = crouch_acceleration_time
		decel_time = crouch_deceleration_time
	# 把输入方向转换到角色自身的水平朝向上：Y 分量取 0，保证只产生水平移动。
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	# 水平移动按所处状态分流：地面给全额操控权威，空中只给有限权威并保留惯性。
	if is_on_floor():
		# 地面：使用默认权威系数 1.0 与上面算出的加减速时间，站立时与 PLAYER-01 的加减速表现逐字一致。
		_apply_horizontal_movement(direction, target_speed, delta, 1.0, accel_time, decel_time)
	else:
		# 空中且有方向输入：按 air_control_factor 削弱操控，使空中转向明显慢于地面（不改动空中控制）。
		if direction != Vector3.ZERO:
			_apply_horizontal_movement(direction, target_speed, delta, air_control_factor)
		# 空中且无方向输入：完全不动水平速度，保留起跳与飞行中的惯性，不会急转或急停。
	# 交给物理引擎做位移与碰撞解算，保证角色站得住、不穿过地面。
	move_and_slide()
	# 迈步轨迹（PLAYER-04.3）：把上一帧留下的整段轨迹推进到下一帧。
	# 必须放在 move_and_slide 之后：位置写入才不会被本帧的碰撞解算覆盖（与迈步落位保持同一时序约束）。
	# 又必须放在 _try_step_up 之前：这样"触发当帧"不会被本帧的轨迹推进多吃掉一帧，
	# 从而保证过渡总帧数精确等于 _step_motion_total_frames() 算出的帧数。
	_apply_step_smoothing()
	# 自然迈步：被竖直立面挡住时尝试迈上小台阶。
	# 必须放在 move_and_slide 之后：此时 is_on_floor / is_on_wall / get_wall_normal 才反映本帧解算结果。
	# 传入本帧输入方向而不是 velocity：顶住台阶时 velocity 会被解算消掉，无法表达"玩家正在往前推"。
	_try_step_up(direction)

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
## accel_time / decel_time 为本次调用的加减速耗时；传负值（默认）表示"未指定"，此时回退到站立的
## acceleration_time / deceleration_time，从而保证既有站立与空中调用的行为逐字不变。
func _apply_horizontal_movement(direction: Vector3, target_speed: float, delta: float, authority: float = 1.0, accel_time: float = -1.0, decel_time: float = -1.0) -> void:
	# 解析本次实际使用的加减速耗时：负值一律视为未指定，回退到站立的地面参数。
	var resolved_accel: float = acceleration_time if accel_time < 0.0 else accel_time
	var resolved_decel: float = deceleration_time if decel_time < 0.0 else decel_time
	# 每帧线性步长 = 速率 × 物理帧时长，因此运动结果与物理帧率无关。
	var speed_step: float = 0.0
	if direction != Vector3.ZERO:
		# 加速段速率：在加速耗时内从静止线性达到目标速度。
		speed_step = (target_speed / maxf(resolved_accel, MIN_TIME_SPAN)) * delta
	else:
		# 减速段速率：以当前水平速度为准，在减速耗时内线性归零。
		speed_step = (_get_horizontal_speed() / maxf(resolved_decel, MIN_TIME_SPAN)) * delta
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
## 另外，蹲伏姿态及姿态过渡期间一律禁止起跳，避免与蹲伏体态发生冲突。
func _try_start_jump(pressed_edge: bool) -> void:
	# 蹲伏禁跳：只要混合量大于 0（处于蹲伏或进/出蹲伏的过渡中）就直接拒绝，
	# 同时覆盖"蹲着走下台阶"的空中蹲伏情形（空中本就不允许二段跳）。
	if _crouch_amount > 0.0:
		return
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

# ==================== 蹲伏实现（PLAYER-03） ====================

## 蹲伏初始化：复制本玩家自己的碰撞胶囊、按引擎约束解析高度、建立净空探测资源，并把姿态对齐到完全站立。
func _setup_crouch() -> void:
	# 取出场景中的碰撞胶囊并复制为独立资源：避免多实例共享同一子资源而互相串改高度。
	var capsule: CapsuleShape3D = _collision.shape as CapsuleShape3D
	# 碰撞体不是胶囊（场景结构异常）时不继续初始化，后续姿态代码会安全降级为不生效。
	if capsule == null:
		return
	# 复制一份独立胶囊并写回节点，之后所有高度改动只作用于本玩家自己。
	_collision_capsule = capsule.duplicate() as CapsuleShape3D
	_collision.shape = _collision_capsule
	# 引擎约束：胶囊总高不得小于两倍半径，因此先把两个高度参数钳制到合法范围。
	var min_height: float = _collision_capsule.radius * 2.0
	_stand_collision_height = maxf(stand_height, min_height)
	_crouch_collision_height = clampf(crouch_height, min_height, _stand_collision_height)
	# 建立站立与"参考（蹲姿已占据）"两套净空探测查询：整场复用，避免逐帧新建资源造成分配抖动。
	_stand_probe_query = _build_probe_query(_stand_collision_height)
	_headroom_adjacent_height = maxf(_crouch_collision_height - HEADROOM_ADJACENT_INSET, 0.0)
	_crouch_probe_query = _build_probe_query(_headroom_adjacent_height)
	# 起始姿态固定为完全站立，保证与 PLAYER-01 / PLAYER-02 的既有站立表现逐字一致。
	_crouch_amount = 0.0
	_crouch_target = 0.0
	_crouch_intent_in_air = false
	_apply_crouch_posture()

## 每物理帧维护蹲伏姿态：读取 Ctrl → 结算空中意图并刷新目标 → 按固定耗时推进混合量 → 落到几何上。
## 姿态的决定权完全归玩家：Ctrl 是进入蹲伏的唯一途径；系统在任何情况下都不会主动把玩家切成蹲伏。
## 顶部障碍只影响"能否起身"：松开 Ctrl 且已有蹲伏成分时，空间不足则保持蹲伏，空间恢复后自动起身。
func _update_crouch(delta: float) -> void:
	# 按住式蹲伏：只关心"此刻是否按住 Ctrl"，不取边沿、也不是开关切换。
	var crouch_held: bool = Input.is_action_pressed("crouch")
	if is_on_floor():
		# 落地当帧是空中意图的唯一结算点：先消费再清零，绝不保留成可延后兑现的动作缓存。
		_crouch_intent_in_air = false
		if crouch_held:
			# 玩家按住 Ctrl（含"在空中一直按住直到落地"）：进入或保持蹲伏。
			# 这是进入蹲伏的唯一途径——除此之外没有任何分支会把目标置为 1。
			_crouch_target = 1.0
		elif _crouch_amount <= 0.0:
			# 玩家完全站立且未按 Ctrl：姿态只能是站立。
			# 这里刻意不检测净空、也绝不把目标置为 1：系统不得以任何理由主动改变玩家姿态。
			_crouch_target = 0.0
		elif _crouch_target <= 0.0:
			# 已经承诺起身：整个过渡期间不再重新判定，也不允许中途取消，0.25 秒一次走完。
			# 这样"判定 → 改变胶囊 → 物理推动位置 → 判定再次改变"的闭环被彻底切断：
			# 姿态不再与几何互相拉扯，这是消除起身震荡的关键。
			_crouch_target = 0.0
		else:
			# 尚未承诺起身（蹲伏落定态，或进入蹲伏的过渡中）且未按 Ctrl：做完整站立胶囊空间判定。
			# 空间不足 → 保持蹲伏且不启动任何起身过渡；空间足够 → 置 0，开始 0.25 秒线性起身。
			# 蹲伏落定态会持续判定，因此"移出障碍后自动起身"仍然成立。
			_crouch_target = 0.0 if _has_headroom() else 1.0
	else:
		# 空中：不改变身体姿态，只记录"此刻是否仍持续按住 Ctrl"这一当前姿态需求；松开即清零。
		_crouch_intent_in_air = crouch_held
		# 空中且当前完全站立时强制目标为 0，确保空中按 Ctrl 不会立即改变身体。
		if _crouch_amount <= 0.0:
			_crouch_target = 0.0
	# 按固定耗时把混合量线性推进到目标：进/出同为 crouch_transition_time，因此天然对称。
	# 由于没有独立计时器，蹲伏中重复按 Ctrl 既不会重置过程、也不会重新计时；
	# 起身过程中再按 Ctrl 只把目标改回 1，于是立刻转为反向回升，实现"取消起身、重新进入蹲伏"。
	_crouch_amount = move_toward(_crouch_amount, _crouch_target, delta / maxf(crouch_transition_time, MIN_TIME_SPAN))
	# 把混合量落到实际几何：碰撞胶囊高度与中心、摄像机高度同步平滑变化。
	_apply_crouch_posture()

## 把当前蹲伏混合量落到实际几何：胶囊高度/中心与摄像机高度同步变化，且胶囊底面恒等于脚底。
func _apply_crouch_posture() -> void:
	# 碰撞胶囊缺失（初始化异常）时直接返回，避免对空引用赋值导致运行时报错。
	if _collision_capsule == null:
		return
	# 当前胶囊总高：由站立高度与蹲伏高度按混合量线性插值得到。
	var body_height: float = lerpf(_stand_collision_height, _crouch_collision_height, _crouch_amount)
	# 胶囊中心本地 Y 取当前总高的一半，使胶囊底面 = 中心 − 高度/2 恒等于本地 Y = 0（即脚底）。
	# 这是"玩家脚底保持稳定"的关键：无论混合量取何值，脚底都不会上下浮动。
	_collision.position.y = body_height * 0.5
	# 改写胶囊高度：半径保持不变，胶囊只在竖直方向伸缩。
	_collision_capsule.height = body_height
	# 摄像机（视线）高度同步线性插值：过渡期间视角平滑升降，不会瞬跳。
	_head.position.y = lerpf(stand_head_height, crouch_head_height, _crouch_amount)

## 生成一个净空探测查询对象：胶囊使用指定总高、与玩家同半径，并排除玩家自身、只查实体碰撞。
func _build_probe_query(capsule_height: float) -> PhysicsShapeQueryParameters3D:
	# 探测胶囊与玩家同半径，只在竖直方向取目标高度。
	var probe_shape := CapsuleShape3D.new()
	probe_shape.radius = _collision_capsule.radius
	probe_shape.height = capsule_height
	var probe_query := PhysicsShapeQueryParameters3D.new()
	probe_query.shape = probe_shape
	# 排除玩家自身，否则探测胶囊会与自己的碰撞体相交，导致永远无法起身。
	probe_query.exclude = [get_rid()]
	# 只与玩家自身的碰撞层做检测，并忽略纯触发区域。
	probe_query.collision_mask = collision_mask
	probe_query.collide_with_areas = false
	return probe_query

## 生成净空探测胶囊的摆放变换：把指定高度的胶囊底面放在脚底之上一个余量处。
## 余量用于规避脚底贴地时因浮点误差把地面本身判成相交。
func _probe_transform(capsule_height: float) -> Transform3D:
	return Transform3D(Basis(), global_position + Vector3(0.0, capsule_height * 0.5 + HEADROOM_MARGIN, 0.0))

## 起身前的头顶净空检测：判断松开 Ctrl 后是否有空间恢复站立。
## 判定方式为"站立探测 − 参考探测"差集：只被站立胶囊碰到、而参考胶囊碰不到的物体，
## 才是站起来才会撞上的新增障碍。这样判定不依赖接触法线的方向，因此可行走坡面、地面与紧贴的侧墙
## 都不会被误判成"挡头"。
## 参考胶囊的高度为蹲伏总高减去 HEADROOM_ADJACENT_INSET：既保证参考区域完全落在蹲伏身体实际
## 占据的空间内，又避免"刚好贴住蹲伏胶囊顶面"的顶棚被误当成无关物体而错误放行起身。
## 返回 true 表示可以起身；返回 false 表示头顶被顶棚等障碍占据，必须继续保持蹲伏。
func _has_headroom() -> bool:
	# 探测资源未建立（初始化异常）时保守放行，避免玩家被永久锁死在蹲伏状态。
	if _stand_probe_query == null or _crouch_probe_query == null or _stand_collision_height <= 0.0:
		return true
	# 第一步：按站立尺寸做形状查询；完全没有任何相交即表示头顶空旷，直接允许起身。
	_stand_probe_query.transform = _probe_transform(_stand_collision_height)
	var standing_hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(_stand_probe_query)
	if standing_hits.is_empty():
		return true
	# 第二步：按"参考尺寸"（蹲伏总高收缩 HEADROOM_ADJACENT_INSET）做形状查询，
	# 登记"蹲着时本来就贴着身体"的物体（地面、坡面、紧贴的侧墙等）。
	# 参考胶囊刻意比蹲伏胶囊矮一截：这样"刚好贴住蹲伏胶囊顶面"的顶棚不会被误当成无关物体。
	_crouch_probe_query.transform = _probe_transform(_headroom_adjacent_height)
	var crouch_hits: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(_crouch_probe_query)
	var adjacent_rids: Dictionary = {}
	for crouch_hit: Dictionary in crouch_hits:
		adjacent_rids[crouch_hit["rid"]] = true
	# 第三步：只有"只被站立胶囊碰到、蹲伏胶囊碰不到"的物体，才是真正阻挡起身的新增障碍。
	for standing_hit: Dictionary in standing_hits:
		if not adjacent_rids.has(standing_hit["rid"]):
			return false
	# 其余相交物体都是蹲姿本来就接触的东西：空间足够，允许起身。
	return true

# ==================== 自然迈步实现（PLAYER-04） ====================

## 自然迈步初始化：建立与玩家同半径的探测胶囊与查询参数，整场复用；并清零迈步计数。
func _setup_step_up() -> void:
	# 探测胶囊半径与玩家一致；高度每次使用前再同步为"当前实际胶囊高度"，因此蹲伏时会自动改用矮胶囊。
	_step_probe_shape = CapsuleShape3D.new()
	_step_probe_shape.radius = _collision_capsule.radius if _collision_capsule != null else 0.35
	_step_probe_shape.height = _stand_collision_height
	_step_probe_query = PhysicsShapeQueryParameters3D.new()
	_step_probe_query.shape = _step_probe_shape
	# 排除玩家自身，否则探测胶囊必然与自己的身体相交，永远被判定为"被占"。
	_step_probe_query.exclude = [get_rid()]
	# 只与玩家自身的碰撞层做检测，并忽略纯触发区域。
	_step_probe_query.collision_mask = collision_mask
	_step_probe_query.collide_with_areas = false
	# 迈步计数清零，便于测试与调试从 0 起观测。
	_step_up_count = 0

## 当前姿态下允许自动迈上的最大高差（米）。
## 完全站立取 step_height（0.20）、完全蹲伏取 crouch_step_height（0.10）；
## 姿态过渡期间按混合量线性取值，因此不会在过渡中跳变。
func _current_step_allowed_height() -> float:
	return lerpf(maxf(step_height, 0.0), maxf(crouch_step_height, 0.0), clampf(_crouch_amount, 0.0, 1.0))

## 判断"把玩家胶囊摆在给定脚底位置"时是否与任何实体相交（已排除玩家自身）。
## 探针尺寸使用当前实际胶囊尺寸，因此站立与蹲伏判断的都是身体真实占位。
func _step_probe_intersects(feet_position: Vector3) -> bool:
	# 胶囊中心 = 脚底 + 高度/2，与碰撞体节点的本地写法保持一致，保证探针与真实身体同形同位。
	_step_probe_query.transform = Transform3D(
		Basis(),
		feet_position + Vector3.UP * (_step_probe_shape.height * 0.5)
	)
	# 这里只关心"有没有相交"，因此把返回条数限制为 1，命中即提前收敛。
	return not get_world_3d().direct_space_state.intersect_shape(_step_probe_query, 1).is_empty()

## 在给定位置向下探测"落脚面"：命中面必须可行走（法线不过陡）。
## 返回 {"height": 落脚面高度, "normal": 法线}；未命中或命中面不可行走时返回空字典。
func _probe_landing_surface(probe_position: Vector3) -> Dictionary:
	# 起点放在探针脚底之上一点（保证即使台面略高于探针脚底也一定能被向下打到），终点打到探针脚底下方，必定穿过台面。
	var ray_query := PhysicsRayQueryParameters3D.create(
		probe_position + Vector3.UP * (step_safe_gap + 0.05),
		probe_position - Vector3.UP * 0.5
	)
	ray_query.exclude = [get_rid()]
	ray_query.collision_mask = collision_mask
	ray_query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(ray_query)
	# 打不到任何东西 → 前方是悬空，不能作为落脚面。
	if hit.is_empty():
		return {}
	# 落脚面必须可行走：过陡的面（斜坡侧面、竖直面）不能站人，自然也不能迈上去。
	var hit_normal: Vector3 = hit["normal"]
	if hit_normal.y < cos(floor_max_angle):
		return {}
	var hit_position: Vector3 = hit["position"]
	return {"height": hit_position.y, "normal": hit_normal}

## 自然迈步：被竖直立面挡住时，尝试把玩家"迈上"不高于当前允许高差的小台阶。
## move_direction 为本帧的**输入移动方向**（世界空间、Y 分量为 0）；零向量表示本帧没有移动意图。
## 注意：这里刻意不使用 velocity —— 被墙完全挡住时 move_and_slide 会把朝向墙面的速度分量消掉，
## velocity 会接近于零，用它做"是否在推进"的判断会把"顶着台阶"这种最该迈步的情形误判为"没在移动"。
## 判定顺序：竖直面筛选 → 上探（抬高后是否与几何相交）→ 前探（前进后是否与几何相交）→ 下探（落脚面是否可行走且高差在界内）。
## 三项全部通过才把玩家放到落脚面上方；任何一项不通过都**完全不动作**，
## 因此失败时玩家的感受是"被正常挡住"，而不是"被系统抬了一格"。
## 全程不写水平速度、不改胶囊尺寸与头部高度，因此移动速度连续性、跳跃、重力、空中控制与蹲伏系统均不受影响。
## PLAYER-04.3 变化：命中后不再单帧写入落点，而是交给 _build_step_plan() 预计算整段逐帧轨迹，
## 由 _apply_step_smoothing() 逐帧推进（总帧数按高差自适应；水平按形状权重缓起缓收；
## 竖直由几何包络反推、自然缓入缓出；末帧竖直收口贴地）。判定条件与判定结果与改动前完全一致，
## 落点的水平分量也逐字相同（仅竖直终点由"落脚面 + 安全间隙"改为"安全间隙按比例收口后的静置高度"）。
func _try_step_up(move_direction: Vector3) -> void:
	# 门禁一：必须站在地面上。空中一律不处理，绝不触碰跳跃高度、滞空时间与空中转向。
	if not is_on_floor():
		return
	# 门禁二：本帧必须有移动意图；没有输入时不存在"迈步"语义。
	if move_direction.length_squared() < 0.0001:
		return
	# 门禁三：必须"被墙挡住"。平地行走时这里为假，直接返回，迈步逻辑零查询开销。
	if not is_on_wall():
		return
	# 门禁四：探测资源缺失（初始化异常）时不做任何动作，使行为安全降级为"没有迈步"。
	if _step_probe_query == null or _step_probe_shape == null or _collision_capsule == null:
		return
	# 归一化移动方向（调用方传入的已经是归一化向量，这里再兜底一次，避免除零与长度不为 1 的情况）。
	var move_step: Vector3 = move_direction.normalized()
	# 竖直面筛选：只处理陡于可行走坡度的立面。坡面与地面在这里被排除，
	# 因此 30 度连续凸起与 15 度上下坡不会被误判成台阶（对应"不处理坡面调整"）。
	var wall_normal: Vector3 = get_wall_normal()
	if wall_normal.y > cos(floor_max_angle):
		return
	# 必须确实在朝墙面推进：输入方向在墙面法线上的分量为负，才说明玩家是在"顶墙"而不是贴墙滑行。
	if move_step.dot(wall_normal) >= 0.0:
		return
	# 门禁五（PLAYER-04.1）：迈步过渡进行中不再受理新的迈步触发。
	# 原因（已由逐帧推演确认）：过渡的中间帧玩家仍在原水平位置、仍贴着同一台阶，三段校验会再次通过；
	# 若此时按"覆盖目标并重新计帧"处理，帧计数会被逐帧刷新，永远走不到最后一步的水平前移，
	# 角色会原地缓慢上抬而无法真正上台。过渡总共只有约 50ms，其间忽略新触发对玩法没有影响。
	# 这里的计数只读，用于让测试证明"该情形确实会反复出现"，不参与任何判定。
	if _step_up_frames_left > 0:
		_step_up_retry_blocked += 1
		return
	# 本帧允许的最大高差：站立 0.20、完全蹲伏 0.10；参数被调成非正数时视为不具备迈步能力。
	var allowed_height: float = _current_step_allowed_height()
	if allowed_height < step_min_height:
		return
	# 探测胶囊同步为当前实际胶囊尺寸：蹲伏时用的是矮胶囊，站立时用的是高胶囊。
	_step_probe_shape.radius = _collision_capsule.radius
	_step_probe_shape.height = _collision_capsule.height
	var feet_position: Vector3 = global_position
	# 第一步 上探：把玩家胶囊整体抬高 allowed_height，若与任何实体相交（顶棚、狭窄通道等）则放弃。
	# 这一步同时保证蹲伏进入低矮空间时不会被抬进顶棚。
	var raised_position: Vector3 = feet_position + Vector3.UP * allowed_height
	if _step_probe_intersects(raised_position):
		return
	# 第二步 前探：从抬高后的位置沿移动方向前进"半径 + 余量"，仍相交说明前方不是空位，放弃。
	# 前进距离取"半径 + 余量"是几何必需：玩家是竖直胶囊，胶囊轴必须越过台阶边缘才能站到台面上。
	var forward_position: Vector3 = raised_position + move_step * (_collision_capsule.radius + step_forward_margin)
	if _step_probe_intersects(forward_position):
		return
	# 第三步 下探：在前探后的 XZ 向下找落脚面，高差必须落在 [step_min_height, allowed_height] 内。
	var landing: Dictionary = _probe_landing_surface(forward_position)
	if landing.is_empty():
		return
	var landing_height: float = landing["height"]
	var height_difference: float = landing_height - feet_position.y
	if height_difference < step_min_height or height_difference > allowed_height + STEP_HEIGHT_EPSILON:
		return
	# 三项校验全部通过：登记本次迈步的最终落点，并按配置构建整段过渡轨迹。
	# 落点 = 前探后的水平位置 + 落脚面之上的安全间隙高度，与 PLAYER-04.1 逐字一致。
	_step_up_final_position = Vector3(
		forward_position.x,
		landing_height + step_safe_gap,
		forward_position.z
	)
	if step_motion_enabled:
		# 构建"逐帧几何包络推进"的整段轨迹：竖直按每帧上限分帧、水平在总帧数内铺开且每帧都服从无穿模包络。
		_build_step_plan(
			feet_position,
			_step_up_final_position,
			landing_height,
			height_difference
		)
		# 触发当帧立即应用轨迹第 1 帧（竖直与水平都已分帧），其余帧由 _apply_step_smoothing() 逐帧推进。
		_apply_step_plan_frame()
	else:
		# 一键回退：保持 PLAYER-04.1 之前的单帧到位行为，便于 A/B 对照。
		_clear_step_plan()
		global_position = _step_up_final_position
	# 只读计数：仅供测试与调试观测，不参与任何行为判定。
	_step_up_count += 1

## 用引擎做一次"水平前探"，得到在指定脚底高度下沿移动方向允许前进的最大无碰撞距离（米）。
## 做法：把玩家胶囊摆在（起点 XZ + 指定脚底高度）处，沿移动方向尝试前进 distance，
##       由引擎的 cast_motion 返回安全比例，再乘回距离并扣除安全余量。
## 之所以交给引擎而不是手写几何公式：玩家的起始站位是被台阶"棱角"顶住而非被立面顶住，
##       起点间隙小于胶囊半径，手写公式若按"起点间隙 = 半径"建模会高估可用前进量并导致真实穿模。
func _step_up_safe_advance(
	start_position: Vector3,
	move_step: Vector3,
	frame_feet_y: float,
	distance: float
) -> float:
	if distance <= 0.0:
		return 0.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_capsule
	# 探测器与玩家同形同位：中心 = 脚底 + 高度/2（与玩家碰撞体的本地写法一致）。
	query.transform = Transform3D(
		Basis(),
		Vector3(start_position.x, frame_feet_y + _collision_capsule.height * 0.5, start_position.z)
	)
	query.motion = move_step * distance
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	var result: Array = get_world_3d().direct_space_state.cast_motion(query)
	# cast_motion 返回 [安全比例, 不安全比例]；取安全比例换算出安全距离并扣除余量。
	var safe_distance: float = float(result[0]) * distance - STEP_ENVELOPE_MARGIN
	return clampf(safe_distance, 0.0, distance)

## 按台阶高差决定本次过渡的总帧数（纯函数，PLAYER-04.3）。
## 规则：以 step_motion_frames_base_height 处的 step_motion_frames_base 为基准，
##       高度每增加 1 米增加 step_motion_frames_per_meter 帧，最后夹在上下限之间。
## 默认参数得到 h=0.10→6、h=0.15→8、h=0.20→10，即"小台阶快速通过、大台阶更平滑"。
func _step_motion_total_frames(height_difference: float) -> int:
	var raw: float = (
		float(step_motion_frames_base)
		+ (height_difference - step_motion_frames_base_height) * step_motion_frames_per_meter
	)
	var lower: int = maxi(step_motion_frames_min, 2)
	return clampi(roundi(raw), lower, maxi(step_motion_frames_max, lower))

## 单帧的形状权重（内部工具，PLAYER-04.3）：前两帧缓起、最后两帧缓收、其余为 1。
func _step_motion_shape_weight(frame: int, total_frames: int) -> float:
	var ramp_count: int = STEP_ADVANCE_RAMP_WEIGHTS.size()
	var taper_count: int = STEP_ADVANCE_TAPER_WEIGHTS.size()
	if frame <= ramp_count:
		return STEP_ADVANCE_RAMP_WEIGHTS[frame - 1]
	var taper_start: int = total_frames - taper_count + 1
	if frame >= taper_start and taper_start > ramp_count:
		return STEP_ADVANCE_TAPER_WEIGHTS[frame - taper_start]
	return 1.0

## 水平速度剖面的形状份额（纯函数，PLAYER-04.3）：返回"本帧应占剩余水平位移的比例"。
## 权重按"剩余帧权重之和"归一化，因此各帧份额天然平滑，不需要在末帧集中补足。
func _step_motion_shape_share(frame: int, total_frames: int) -> float:
	var remaining_weight: float = 0.0
	for index: int in range(frame, total_frames + 1):
		remaining_weight += _step_motion_shape_weight(index, total_frames)
	if remaining_weight <= 0.0:
		return 1.0
	return _step_motion_shape_weight(frame, total_frames) / remaining_weight

## 几何包络反推（PLAYER-04.3）：在 [low_y, high_y] 二分出"允许从起点累计前进 target_advance"的最小脚底高度。
## 依据：脚底越低，台阶棱角挡得越多、允许的前进量越小（单调关系），因此可以直接用引擎前探做二分。
## 若上限高度仍不足以放行目标前进量，则返回上限高度，由调用方把该帧的水平目标顺延到后续帧。
func _step_up_required_height(
	start_position: Vector3,
	move_step: Vector3,
	advance_total: float,
	target_advance: float,
	low_y: float,
	high_y: float
) -> float:
	var low: float = low_y
	var high: float = maxf(high_y, low_y)
	if _step_up_safe_advance(start_position, move_step, high, advance_total) < target_advance:
		return high
	for _i in range(STEP_HEIGHT_BISECT_STEPS):
		var mid: float = (low + high) * 0.5
		if _step_up_safe_advance(start_position, move_step, mid, advance_total) >= target_advance:
			high = mid
		else:
			low = mid
	return high

## 构建整段迈步轨迹（PLAYER-04.3）：一次性把逐帧目标位置算好，逐帧只做一次赋值（相机保持刚性、不参与）。
## 总帧数：按台阶高差自适应（小台阶 6 帧快速通过、0.20m 台阶 10 帧更平滑）。
## 水平：几何必需量（胶囊半径 + 前探余量）按"缓起—稳定—缓收"的形状权重分配，不做末帧集中补足。
## 竖直：不人为设定帧数，逐帧由几何包络反推"放行该帧水平位移所需的最小抬升"（受每帧上限约束），
##       因此自然形成缓入—峰值—缓出的钟形；也不会产生多余抬升（多余抬升正是"升降平台感"的来源）。
## 末帧：竖直收口到"落脚面 + step_safe_gap × 收口比例"，消除过渡后被贴地吸附单帧下拉的镜头跳动；
##       水平仍精确等于几何必需量，因此落点的水平分量与既有实现逐字一致。
func _build_step_plan(
	start_position: Vector3,
	final_position: Vector3,
	landing_height: float,
	height_difference: float
) -> void:
	# 先清空上一段轨迹（正常情况下此时没有残留，属防御性）。
	_clear_step_plan()
	var total_frames: int = _step_motion_total_frames(height_difference)
	# 水平总前移量与方向（几何必需量 = 胶囊半径 + 前探余量，与台阶高度无关）。
	var horizontal_delta: Vector3 = Vector3(
		final_position.x - start_position.x,
		0.0,
		final_position.z - start_position.z
	)
	var advance_total: float = horizontal_delta.length()
	var advance_step: Vector3 = horizontal_delta.normalized() if advance_total > 0.0 else Vector3.ZERO
	# 轨迹最终贴地高度：把安全间隙在末段收口掉，使过渡结束即处于静置高度。
	var settle_y: float = landing_height + step_safe_gap * clampf(step_motion_settle_ratio, 0.0, 1.0)
	var rise_cap: float = maxf(step_motion_max_rise_per_frame, 0.001)
	var used_advance: float = 0.0
	var previous_y: float = start_position.y
	for frame: int in range(1, total_frames + 1):
		# 本帧水平目标：按形状权重分配剩余位移（前两帧缓起、末两帧缓收）。
		var shape_share: float = _step_motion_shape_share(frame, total_frames)
		var desired_advance: float = (advance_total - used_advance) * shape_share
		var target_advance: float = used_advance + desired_advance
		# 几何包络反推本帧抬升：在"上一帧高度 ~ 上一帧高度 + 每帧上限"之间二分；
		# 上限同时不超过最终贴地高度，保证竖直单调上升且不会抬过头。
		var frame_feet_y: float = _step_up_required_height(
			start_position,
			advance_step,
			advance_total,
			target_advance,
			previous_y,
			minf(previous_y + rise_cap, settle_y)
		)
		# 该高度下实际允许的累计前进量：若上限高度仍不足以放行目标，则本帧水平顺延到后续帧。
		var allowed_total: float = _step_up_safe_advance(
			start_position,
			advance_step,
			frame_feet_y,
			advance_total
		)
		var frame_advance: float = clampf(allowed_total - used_advance, 0.0, desired_advance)
		used_advance += frame_advance
		previous_y = frame_feet_y
		# 目标位置 = 起点沿移动方向前进 used_advance + 竖直取本帧绝对高度。
		var frame_position: Vector3 = start_position + advance_step * used_advance
		frame_position.y = frame_feet_y
		_step_up_plan.append(frame_position)
	# 末帧强制对齐：水平补足到几何必需量，竖直为收口后的贴地高度。
	var last_position: Vector3 = start_position + advance_step * advance_total
	last_position.y = settle_y
	_step_up_plan[total_frames - 1] = last_position
	_step_up_plan_index = 0
	_step_up_frames_left = total_frames

## 清空整段迈步轨迹数据（不改变任何位置）：同时把剩余帧数归零，从而解除"过渡期间不受理新迈步"的门禁。
func _clear_step_plan() -> void:
	_step_up_plan.clear()
	_step_up_plan_index = 0
	_step_up_frames_left = 0

## 应用轨迹中的当前帧：写入目标位置与相机视觉偏移，并推进帧游标与剩余帧数；走完最后一帧后清理轨迹。
## 设计要点与理由：
##   1) 目标位置是预先算好的**绝对坐标**，逐帧只做一次赋值，不累加、不漂移，
##      即使引擎在同一帧内因贴地吸附把玩家往下拉过，也会被这次写入覆盖；
##   2) 水平与竖直同时推进，且每一帧都服从无穿模包络，因此观感是"贴着台阶棱角绕上去"，
##      不会出现"先抬到顶、再横向瞬移"的传送感；
##   3) 水平 velocity 全程零写入（位置预算不改速度）；竖直 velocity 钳制为非负，保证只升不降；
##   4) 相机偏移只叠加到 Head.position.y：该值每帧都会被蹲伏姿态逻辑重写为基准值，
##      因此直接叠加不会累积，过渡结束时偏移恰好为 0，视线精确回到基准高度。
func _apply_step_plan_frame() -> void:
	global_position = _step_up_plan[_step_up_plan_index]
	# 记录本帧写入位置，供下一帧检测"玩家是否被瞬移"。
	_step_up_reference_position = global_position
	_step_up_plan_index += 1
	_step_up_frames_left = _step_up_plan.size() - _step_up_plan_index
	# 过渡期间禁止向下速度：保证只升不降，避免重力与过渡位移"抢位"产生抖动。
	velocity.y = maxf(velocity.y, 0.0)
	# 整段轨迹走完：清理轨迹数据（剩余帧数随之为 0，门禁五随之解除）。
	if _step_up_frames_left <= 0:
		_clear_step_plan()

## 逐帧推进迈步轨迹（PLAYER-04.2）：由 _physics_process() 在 move_and_slide() 之后、_try_step_up() 之前调用。
## 之所以必须放在 move_and_slide 之后：位置写入不会被本帧的碰撞解算覆盖（与迈步落位保持同一时序约束）。
## 之所以必须放在 _try_step_up 之前：触发当帧不会被本帧的轨迹推进多吃掉一帧。
func _apply_step_smoothing() -> void:
	# 没有进行中的轨迹（绝大多数帧）时直接返回，保持零额外开销。
	if _step_up_frames_left <= 0 or _step_up_plan_index >= _step_up_plan.size():
		return
	# 失效守卫：轨迹存的是绝对坐标，一旦玩家在两帧之间被瞬移（重生、传送、被外力推开等），
	# 继续推进就会把玩家拖回旧目标点。此处检测偏离量，超限则直接弃用整段轨迹。
	if global_position.distance_to(_step_up_reference_position) > STEP_PLAN_MAX_DEVIATION:
		_clear_step_plan()
		return
	_apply_step_plan_frame()
