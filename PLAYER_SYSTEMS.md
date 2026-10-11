# Robinson 玩家移动系统（PLAYER 系列）冻结文档

- **冻结版本**：PLAYER-04.3 完成态（PLAYER-01 → PLAYER-04.3 全部合入）
- **实现文件**：`scripts/player.gd`（942 行，含中文详尽注释；`CharacterBody3D` 脚本，挂在 `scenes/player.tscn` 根节点）
- **运行环境**：Godot 4.7.2.stable + Jolt Physics，物理帧 60Hz，`floor_max_angle` 45°，`up_direction` 必须为引擎默认 `(0,1,0)`（见 7.3）
- **本轮性质**：只审计与记录，未改动任何代码。文档中的数值均取自 headless 实测日志与逐帧探针。

---

## 1. 模块边界

| 模块 | 职责 | 主要符号（行号取自冻结版本） |
|---|---|---|
| **PLAYER-01** 基础移动与视角 | 重力落地、WASD 相对朝向水平移动、Shift 奔跑、固定耗时线性加减速、鼠标水平转向与俯仰钳制、Esc 切换鼠标捕获 | `_physics_process`(317)、`_apply_horizontal_movement`(385)、`_get_horizontal_speed`(458)、`_handle_mouse_look`(373)、`_toggle_mouse_capture`(463)、常量 `MIN_TIME_SPAN`(49) |
| **PLAYER-TUNE-01** 平衡参数 | 速度/加减速/跳跃高度等数值定稿（注释明示 `walk_speed`/`run_speed` 为**临时实验值、非最终定稿**） | `walk_speed`(88)、`run_speed`(91)、`acceleration_time`(94)、`deceleration_time`(97)、`max_jump_height`(110)、`min_jump_height`(113) |
| **PLAYER-02** 普通跳跃 | 可变跳跃高度（松键削顶）、0.10s 离地宽限、禁二段跳与长按重复触发、空中有限转向 | `_update_coyote_timer`(405)、`_try_start_jump`(419)、`_apply_jump_release_cut`(441)、`coyote_time`(119)、状态 `_coyote_timer`/`_jump_pressed_last_frame`/`_jump_consumed_in_air`/`_max_jump_velocity`/`_min_jump_velocity` |
| **PLAYER-03** 按住式蹲伏 | 按住 Ctrl 为进入蹲伏的唯一途径；0.25s 进/出线性过渡；蹲伏降速（2.0）；蹲伏禁跳；起身前头顶净空检测；空中只记录意图、落地当帧结算一次 | 导出参数(121-145)、`_setup_crouch`(473)、`_update_crouch`(499)、`_apply_crouch_posture`(537)、`_build_probe_query`(552)、`_probe_transform`(568)、`_has_headroom`(578)、常量 `HEADROOM_MARGIN`(52) |
| **PLAYER-03.1** 起身震荡修复 | “承诺式起身”：起身一经启动不再重判/不可取消；净空判定用“站立探测 − 参考探测”**差集**（`HEADROOM_ADJACENT_INSET`），切断“判定→改胶囊→物理推动→再判定”的闭环 | `_update_crouch`(509-522) 的分支结构、`_has_headroom`(578-600)、常量 `HEADROOM_ADJACENT_INSET`(59) |
| **PLAYER-04** 自然迈步 | 被竖直立面挡住时迈上小台阶：门禁一~四 + 三段校验（上探/前探/下探），站立上限 0.20m、完全蹲伏上限 0.10m；失败时完全不动作 | 导出参数(147-163)、`_setup_step_up`(605)、`_current_step_allowed_height`(623)、`_step_probe_intersects`(628)、`_probe_landing_surface`(639)、`_try_step_up`(671)、常量 `STEP_HEIGHT_EPSILON`(63) |
| **PLAYER-04.1** 竖直分帧 | **功能已被 04.2/04.3 取代**；现仅保留其两项产物：门禁五（过渡期间不受理新迈步触发，694-701）与只读计数 `_step_up_retry_blocked`(285) | — |
| **PLAYER-04.2** 逐帧轨迹 | 由“单帧位置写入”改为预计算逐帧轨迹 + 逐帧一次赋值；引擎 `cast_motion` 无穿模包络；轨迹失效守卫（瞬移即弃用） | `_step_up_plan`(273)、`_step_up_plan_index`(276)、`_step_up_frames_left`(279)、`_step_up_reference_position`(282)、`_apply_step_smoothing`(932)、`_step_up_safe_advance`(757)、常量 `STEP_ENVELOPE_MARGIN`(66)、`STEP_PLAN_MAX_DEVIATION`(71) |
| **PLAYER-04.3** 地面高度连续化 | 总帧数按高差自适应；水平按形状权重“缓起—稳定—缓收”；竖直由包络反推（钟形，受每帧上限约束）；相机保持刚性（不参与迈步）；末帧竖直收口贴地 | 导出参数(165-195)、`_step_motion_total_frames`(785)、`_step_motion_shape_weight`(794)、`_step_motion_shape_share`(806)、`_step_up_required_height`(817)、`_build_step_plan`(844)、`_clear_step_plan`(903)、`_apply_step_plan_frame`(917)、常量 `STEP_HEIGHT_BISECT_STEPS`(75)、`STEP_ADVANCE_RAMP_WEIGHTS`(79)、`STEP_ADVANCE_TAPER_WEIGHTS`(83) |

---

## 2. 参数总表

### 2.1 导出参数（28 个，均可在检视面板调整）

| 分组 | 参数 | 默认值 | 含义 |
|---|---|---|---|
| 移动 | `walk_speed` | 3.2 | 行走目标速度（米/秒，PLAYER-TUNE-01 临时实验值） |
| 移动 | `run_speed` | 5.2 | 奔跑目标速度（同上） |
| 移动 | `acceleration_time` | 0.15 | 站立线性加速到目标速度的固定耗时（秒） |
| 移动 | `deceleration_time` | 0.12 | 站立减速时间常数（秒）——实现为按当前速度比例的步长，故为**指数衰减** |
| 移动 | `mouse_sensitivity` | （视角） | 鼠标转向灵敏度 |
| 移动 | `air_control_factor` | 0.30 | 空中操控权威系数 |
| 跳跃 | `max_jump_height` | 0.915 | 平地满按最高高度（反解初速 v0=√(2gh)，实测最高点约 0.95m） |
| 跳跃 | `min_jump_height` | 0.35 | 轻点即松的最低高度 |
| 跳跃 | `coyote_time` | 0.10 | 离地宽限（秒） |
| 蹲伏 | `crouch_speed` | 2.0 | 蹲伏移动速度 |
| 蹲伏 | `crouch_acceleration_time` | 0.25 | 蹲伏加速耗时 |
| 蹲伏 | `crouch_deceleration_time` | 0.20 | 蹲伏减速时间常数 |
| 蹲伏 | `crouch_transition_time` | 0.25 | 进/出蹲伏的单向过渡耗时（天然对称） |
| 蹲伏 | `stand_height` | 1.8 | 站立胶囊总高 |
| 蹲伏 | `crouch_height` | 1.2 | 蹲伏胶囊总高 |
| 蹲伏 | `stand_head_height` | 1.65 | 站立视线高度（头部枢轴本地 Y） |
| 蹲伏 | `crouch_head_height` | 1.05 | 蹲伏视线高度 |
| 迈步 | `step_height` | 0.20 | 站立可自动迈上的最大高差 |
| 迈步 | `crouch_step_height` | 0.10 | 完全蹲伏可自动迈上的最大高差 |
| 迈步 | `step_forward_margin` | 0.05 | 前探距离在胶囊半径之上的余量（几何必需量 = 半径 + 本值 = 0.40m） |
| 迈步 | `step_min_height` | 0.02 | 低于该高差不做迈步，交给 `move_and_slide` 自然吸收 |
| 迈步 | `step_safe_gap` | 0.01 | 落位时在落脚面之上保留的间隙 |
| 迈步轨迹 | `step_motion_enabled` | true | 轨迹总开关（false 时退化为单帧到位，便于 A/B 与回退） |
| 迈步轨迹 | `step_motion_max_rise_per_frame` | 0.045 | 竖直每帧上限（安全上限，非定帧依据） |
| 迈步轨迹 | `step_motion_frames_min` | 6 | 过渡总帧数下限 |
| 迈步轨迹 | `step_motion_frames_max` | 10 | 过渡总帧数上限 |
| 迈步轨迹 | `step_motion_frames_base_height` | 0.10 | 帧数规则的参考高度 |
| 迈步轨迹 | `step_motion_frames_base` | 6 | 参考高度处的帧数 |
| 迈步轨迹 | `step_motion_frames_per_meter` | 40.0 | 每增加 1 米高差增加的帧数 |
| 迈步轨迹 | `step_motion_settle_ratio` | 0.05 | 末帧贴地比例（最终脚底 = 落脚面 + `step_safe_gap` × 本值） |

> 帧数规则：`frames = clamp(round(6 + (h − 0.10) × 40), 6, 10)` → **h=0.10→6 帧、0.15→8 帧、0.20→10 帧**。

### 2.2 常量（9 个）

| 常量 | 值 | 用途 |
|---|---|---|
| `MIN_TIME_SPAN` | 0.0001 | 时间参数除零保护 |
| `HEADROOM_MARGIN` | 0.02 | 净空探测胶囊抬升余量，避免把地面误判为阻挡 |
| `HEADROOM_ADJACENT_INSET` | 0.15 | 参考探测胶囊的收缩量（差集判定用） |
| `STEP_HEIGHT_EPSILON` | 0.001 | 高差上限判定的浮点容差 |
| `STEP_ENVELOPE_MARGIN` | 0.003 | 引擎前探结果再收缩量，避免停在临界相切位置 |
| `STEP_PLAN_MAX_DEVIATION` | 0.3 | 轨迹失效守卫阈值（米） |
| `STEP_HEIGHT_BISECT_STEPS` | 8 | 竖直反推的二分步数 |
| `STEP_ADVANCE_RAMP_WEIGHTS` | [0.5, 0.8] | 水平缓起权重（前两帧） |
| `STEP_ADVANCE_TAPER_WEIGHTS` | [1.0, 0.85] | 水平缓收权重（末两帧） |

---

## 3. 行为规则

### 3.1 每物理帧的处理顺序（`_physics_process`，317-368）

1. `_update_coyote_timer(delta)`：着地充满宽限并复位跳跃消费标记；离地递减。
2. 读取空格按下边沿（`_jump_pressed_last_frame` 比较）。
3. 未着地时 `velocity.y -= gravity × delta`。
4. `_update_crouch(delta)`：刷新蹲伏目标、推进混合量、落到几何（胶囊高度/中心、视线高度）。
5. `_try_start_jump(边沿)`：蹲伏禁跳 → 需新边沿 → 需宽限 > 0 → 需本次离地未跳过。
6. `_apply_jump_release_cut()`：松键且仍在上升时把 `velocity.y` 截断到最低初速。
7. 读取 WASD（`get_vector`，斜向不加速）。
8. 计算本帧目标速度与加减速时间（蹲伏且着地时切到蹲伏参数）。
9. 水平移动分流：**着地** → 权威 1.0 + 站立/蹲伏参数；**空中且有输入** → 权威 `air_control_factor`；**空中无输入** → 完全不改水平速度（保留惯性）。
10. `move_and_slide()`（唯一碰撞解算点）。
11. `_apply_step_smoothing()`：推进迈步轨迹一帧（位置写入必须在 `move_and_slide` 之后）。
12. `_try_step_up(direction)`：尝试迈步（判定必须读取本帧解算后的 `is_on_floor`/`is_on_wall`/`get_wall_normal`）。

### 3.2 迈步判定链（`_try_step_up`，671-755）

**门禁**：① 必须 `is_on_floor()`；② 必须有移动输入；③ 必须 `is_on_wall()`（平地零查询）；④ 探测资源必须就绪；⑤（04.1 产物）过渡进行中不受理新触发。

**筛选**：墙面法线须陡于 `floor_max_angle`（坡面/地面排除）；输入方向须朝墙（`move_step·wall_normal < 0`）；允许高差 = `lerp(step_height, crouch_step_height, _crouch_amount)`，且须 ≥ `step_min_height`。

**三段校验**（任一失败 → 完全不动作，玩家感受为“被正常挡住”）：
1. **上探**：胶囊抬高 `allowed_height` 后不得与任何实体相交（同时保证蹲伏进低矮空间不会被抬进顶棚）。
2. **前探**：再沿移动方向前进 `胶囊半径 + step_forward_margin`（0.40m）后不得相交（几何必需：胶囊轴必须越过台阶边缘）。
3. **下探**：在前探位置向下打射线找落脚面，命中面法线须可行走，且高差 ∈ `[step_min_height, allowed_height]`。

### 3.3 迈步轨迹规则（04.2/04.3，`_build_step_plan` 844-900）

- **总帧数**：按高差自适应（见 2.1 帧数规则）。
- **水平**：几何必需量 0.40m 按形状权重分配剩余位移（前两帧缓起 0.5/0.8、末两帧缓收 1.0/0.85），**不做末帧集中补足**。
- **竖直**：逐帧用 `cast_motion` 二分反推“放行该帧水平位移所需的最小脚底高度”（区间 `[上一帧高度, 上一帧高度 + 0.045]` 且不越过最终贴地高度），因此自然形成缓入—峰值—缓出的钟形且无多余抬升。
- **末帧**：水平精确等于几何必需量；竖直收口到 `落脚面 + step_safe_gap × 0.05`（≈ +0.5mm，实测静置高度），用于消除过渡后被贴地吸附单帧下拉的镜头跳动。
- **逐帧应用**（`_apply_step_plan_frame` 917）：写入绝对坐标 → 更新参考位置 → 推进游标与剩余帧数 → `velocity.y = max(velocity.y, 0)`（只升不降）→ 走完清空轨迹。
- **失效守卫**（932-940）：若当前 `global_position` 与上一帧写入位置偏离 > 0.3m（重生/传送/被外力推开），立即弃用整段轨迹。
- **相机**：**零参与**。04.3 起不产生任何迈步相机偏移。

---

## 4. 隐式耦合审计

| 耦合对 | 性质 | 细节与风险 |
|---|---|---|
| 迈步 → 位置 | **写**（2 处） | `global_position` 仅在 `_try_step_up`(748 回退分支) 与 `_apply_step_plan_frame`(918) 写入；其余代码从不直接改位置 |
| 迈步 → 竖直速度 | **写**（1 处，限过渡期） | `velocity.y = maxf(velocity.y, 0)`（924）仅在轨迹推进期间生效（6~10 帧），用于保证只升不降；水平 `velocity` 全程零写入 |
| 迈步 ↔ 蹲伏 | 读 + 几何耦合 | 可迈高度由 `_crouch_amount` 线性插值得到（蹲伏 → 0.10）；轨迹构建时用**站立胶囊**做保守校验，若过渡中蹲伏（胶囊变矮）不会增加穿模风险 |
| 迈步 ↔ 跳跃 | **共用 coyote 窗口（未验证）** | 迈步要求着地，不能在空中触发；但**过渡期间的中间帧 `is_on_floor()` 可能为假（实测 0~1 帧）**，此时按空格可经 coyote 窗口起跳，而轨迹仍会写入绝对位置 → 跳跃在剩余过渡帧内被轨迹覆盖（表现为约 ≤150ms 的“闷跳/延迟起跳”）。**本轮未测试该组合**，列为已知限制（见 7.2） |
| 移动 ↔ 着地状态 | 隐式、高敏感 | “空中且无输入不减速”是 PLAYER-01/02 为保留跳跃惯性所定；因此**任何 floor 误判都会被放大为“松开键仍像冰面一样滑行”**（已由 up_direction 事故实证） |
| 蹲伏 → 相机 | 唯一写入者 | `_head.position.y` 全脚本仅 `_apply_crouch_posture`(549) 一处写入；迈步/跳跃/移动均不触碰 → 无累加、无残留 |
| 跳跃 → 蹲伏 | 单向门禁 | `_try_start_jump` 以 `_crouch_amount > 0` 拒绝起跳（蹲伏禁跳）；反向无耦合 |
| 跳跃 → 水平 | 无 | 水平加减速读写 `velocity.x/z`，与竖直分量互不干扰（`target_velocity` 保留 `velocity.y`） |

---

## 5. 代码质量审计（重复 / 无效参数 / 废弃变量 / 未使用函数 / 调试残留）

| 检查项 | 结论 |
|---|---|
| **调试残留** | **0 处**。全脚本无 `print` / `print_debug` / `push_error` / `push_warning` / `assert` / `TODO` / `FIXME` / `breakpoint`。所有观测逻辑只以只读成员形式存在（`_step_up_count`、`_step_up_retry_blocked`），由外部探针读取 |
| **废弃变量** | **0 处**。04.1 的一维高度状态（`_step_up_start_y` / `_step_up_step_y` / `_step_up_total_frames`）与 04.2 的相机偏移表（`_step_up_camera_plan`、`step_motion_camera_curve`、`step_motion_bands`）已全部移除，全脚本无残留引用 |
| **未使用函数** | **0 处**。30 个函数全部有调用点（含只被 `_try_step_up` 内部调用的三段校验辅助函数） |
| **无效参数** | **0 处**。28 个导出参数与 9 个常量全部参与实际逻辑；`step_motion_enabled` 为回退开关、`step_motion_settle_ratio` 为收口比例，均有实际作用 |
| **重复代码** | 未见功能重复。存在两处**形似但用途不同**的探测构建：`_build_probe_query`（蹲伏净空，双向差集）与 `_step_up_safe_advance`/`_step_probe_intersects`（迈步，向前/向上单次相交）。两者形状来源、掩码与判定语义不同，合并会降低可读性，故保持独立 |
| **注释与实现不一致（文档性残留，共 3 处）** | ① `_apply_step_plan_frame` 文档注释第 4 条仍写“相机偏移只叠加到 `Head.position.y`”，但 04.3 已移除相机偏移（该条已失效）；② `_apply_step_smoothing` 文档标签仍写“PLAYER-04.2”；③ 文件头“迈步约定（PLAYER-04）”段落中“全程不写 velocity”与 04.3 段落“过渡期间竖直速度钳制为非负”表述不一致（后者准确）。**本轮按“禁止修改代码”未改动，仅记录** |
| **函数命名陈旧** | `_apply_step_smoothing` 名称源自 04.1 的“平滑过渡”，现职责为“推进整段轨迹”，语义略有偏差（功能正确，仅命名历史包袱） |

---

## 6. 已解决问题

| 编号 | 问题 | 结论与证据 |
|---|---|---|
| 1 | **平地滑步 / 松键像冰面（PLAYER-04 之后的回归投诉）** | **不是 PLAYER-04**。根因是 `scenes/movement_test.tscn` 的 Player 节点被后台编辑器写入 `up_direction = (0, 0.0039, 0.99999)`（几乎水平），导致平地永不被判定为 floor → 永远走空中分支 → 无输入时完全不减速。三组对照：A（现状，迈步开）与 B（现状，迈步关）停止距离**逐位相同** 4.8439m/7.8438m；C（仅运行时恢复 `up_direction=(0,1,0)`）恢复为 0.3256m/0.5328m 且 `is_on_floor=true`。**修复**：场景 Player 节点该行恢复 `(0,1,0)`（本提交已确保场景文件中不含任何错误覆盖） |
| 2 | 站立/蹲伏/跳跃全部失效（同源） | 同一根因：跳跃依赖 coyote，蹲伏地面分支与迈步门禁依赖 `is_on_floor()`。修复后 PLAYER-03 回归由 40 项失败恢复为 76/76 |
| 3 | 迈步“瞬移感” | 04.0 单帧 `global_position` 位移（Δ垂直 0.209m + Δ水平 0.433m 同帧）→ 04.1 竖直 3 帧分帧（单帧垂直 0.159→0.053 / 0.209→0.070）→ 04.2 逐帧轨迹 + 引擎前探包络（消除真实穿模 18.3/28.9mm）→ 04.3 竖直缓入缓出钟形 |
| 4 | 第一人称“升降平台感 / 速度断层 / 镜头跳动” | 04.3：竖直峰值 0.070→0.0439（2.5m/s，钟形）；水平峰值 1.77×→1.06× 行走；轨迹内水平单帧变化 0.0217→0.0168；过渡后下沉 8.6mm→**0.0mm**；相机二阶差分 0.036~0.043→0.012~0.014；相机偏移完全移除 |
| 5 | 连续台阶“跳一下→停一下→再跳一下” | 04.3 实测：连续 5 级 0.15m 台阶全部 8 帧/级、每级竖直峰值 0.039~0.044、水平峰值 1.06× 行走、**最长低位移连续帧 0 帧（无停顿）** |
| 6 | 迈步过渡被重复触发打断 | 门禁五：过渡期间不受理新触发（只读计数 `_step_up_retry_blocked` 可证明该情形确实会反复出现） |
| 7 | 轨迹在瞬移后拖人 | 失效守卫：偏离上一帧写入位置 > 0.3m 即弃用整段轨迹（该问题由回归测试实测发现并修复） |
| 8 | 起身与几何互相拉扯产生上下震荡（PLAYER-03.1） | 承诺式起身 + 差集净空判定（`HEADROOM_ADJACENT_INSET`），切断判定闭环 |

---

## 7. 已知限制与未验证项

### 7.1 减速是“指数衰减”而非“线性归零”
`_apply_horizontal_movement` 的减速步长按**当前速度比例**计算，因此 `deceleration_time` 实际是时间常数 τ（离散实现 τ≈0.111s），速度数学上永不精确归零，滑行距离 ≈ v₀×τ：实测行走 0.3256m / 奔跑 0.5328m（设计初值 v₀×`deceleration_time` = 0.384m / 0.624m）。与文件内“线性归零”的注释表述不符，属 PLAYER-01 既有实现，**待裁决**。

### 7.2 过渡期间的跳跃（未测试）
见 4 节“迈步 ↔ 跳跃”：过渡中间帧可能 `is_on_floor()=false`，此时经 coyote 窗口起跳会被剩余轨迹覆盖。提示：若实机出现“台阶边缘跳不起来”，优先检查该组合。

### 7.3 场景 `up_direction` 与后台编辑器
Playe r 节点的 `up_direction` **不得**存在非默认覆盖；一个长期运行的 Godot 编辑器进程内存中若持有旧值，保存场景时会把错误覆盖写回。本提交的场景文件已确认**不含**任何 `up_direction` 行（即使用引擎默认）。**建议**：实机试玩前关闭该编辑器或在其内 Revert。

### 7.4 几何必然：水平位移的“入场边界”
台阶入口处，竖直每帧上限（0.045）与低处包络斜率（`dy/dp ≈ 1.6`）联立，决定首帧水平位移最多约 0.023m ⇒ 若玩家以满速（0.053m/帧）撞上台阶，**触发帧会出现一次约 −47% 的单帧水平速度变化**（实测 0.15m 档 0.053→0.028；0.20m 档因动量对齐而仅 −0.4%）。轨迹内部相邻帧变化为 0.013~0.017（无断层）。这是“竖直缓入”的几何代价，**待实机体感裁决**；唯一调节旋钮是 `step_motion_max_rise_per_frame`（放宽则入口更顺、抬升更陡）。

### 7.5 长过渡的两个操作代价
- 迈步后速度恢复帧数：0.15m 档 10→12 帧、0.20m 档 12→13 帧（过渡更长，进入空中分支的帧数略增）。
- 连续 5 级 0.15m 台阶总时长：50→65 帧（+30%），源于按高差自适应到 8 帧/级。

### 7.6 未覆盖
下台阶与落步平滑、坡度跳跃衰减、镜头晃动、匍匐/滑铲/潜行等均未实现（范围声明如此）；真实键盘手感（蹲伏、停止、迈步体感）仍需人手确认。

---

## 8. 回归与验证基线（冻结版本实测）

| 套件 | 结果 | 关键数据 |
|---|---|---|
| PLAYER-03 全回归 | **76 / 76 通过** | 平地 `is_on_floor=true`；行走 3.200 / 奔跑 5.200；跳跃峰值 0.9504m；蹲伏 0.25s 过渡；15°/30°/44° 坡面站立正常 |
| PLAYER-04 AreaE 回归 | **19 / 19 通过** | 0.05/0.10m 引擎自然骑过；0.15/0.20m 自动迈上；0.30m 及以上保持阻挡；60° 陡坡与凸起不误触发；接缝正常 |
| PLAYER-04.3 地面高度连续化 | **32 / 32 通过** | 单级 0.15m：竖直峰值 0.0425、水平峰值 1.05×、下沉 0.0mm、相机二阶差分 0.0142；单级 0.20m：0.0439 / 0.82× / 0.0mm / 0.0118；连续 5 级：竖直 0.0438、水平 1.06×、停顿 0 帧、末帧脚底 0.7505 |
| 主场景冒烟 | 通过 | headless 240 帧无报错；MCP `run_project` + `get_debug_output` → `errors: []` |

> 复现方式：临时探针置于 `tests/`（用后整目录删除、不提交），以 `godot --headless --path <工程> res://tests/<探针>.tscn` 运行，输出 PASS/FAIL 文本日志。
