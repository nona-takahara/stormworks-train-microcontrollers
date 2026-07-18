-- CHUSO1800牽引制御の統合コア。
-- core_tick(stateless_in, state_in) -> stateless_out, state_out は純関数で、
-- 4配列はいずれも8要素。状態はstateだけに保持する。
-- 契約と挙動は../SPEC.md、割付は../SIGNAL_MAP.mdを正典とする。
-- 外部APIをグローバル定義する非モジュール構成はDESIGN_LOG.md #15参照。

--------------------------------------------------------------------------
-- 定数（n409.luaからの逐語コピー）
--------------------------------------------------------------------------

local K = 12.16
local Kmu = 0.00029
local MOT_RES = 0.07
local Ks = 0.85
local PHIs = 150

local MOT_CTRL = 4

local GEAR_RATIO = 5.31
local WHEEL_R = 0.86 / 2
local WEIGHT = 35 * 1000

local SR = { 7.428,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334,     0,2.568,1.734,1.218,0.7570,0.4110,0.1334}
local PR = {     0,5.137,4.157,3.197,2.681,2.178,1.717,1.317,0.9710,0.7570,0.6386,0.3610,0.2276,0.1334, 3.714,2.568,1.734,1.218,0.7570,0.4110,0.1334}

-- Newton反復の初期値。OLD_Iや界磁制御のtarget_iとは別用途。
local NEWTON_SEED = 200

--------------------------------------------------------------------------
-- Stormworks propertyをspawn時に読む。テスト用スタブはtest/run_all.lua側。
--------------------------------------------------------------------------

local OVERSPEED_THRESHOLD = property.getNumber("Over Speed Th. [m/s]")     -- m/s
local POWER_LIMIT_CURRENT = property.getNumber("Power Limit Current [A]") -- A

-- 原型でも調整不可のCONST。
local BRAKE_MIN_PRESSURE = 4         -- atm
local BRAKE_LIMIT_300 = 300
local BRAKE_LIMIT_400 = 400
local REGEN_BC_MIN = -0.1
local BC_TARGET_MIN = -0.05

-- 並列全短絡位置の固着解除をほぼ停止中だけに限定する。
local STUCK_RELEASE_SPEED_THRESHOLD = 3 -- m/s

-- tick数由来のタイマー定数（Stormworksは60tick/秒前提、SPEC §2）。
local CAP_DEBOUNCE_TICKS = 6              -- 0.1sデバウンス、無効化で即0
local CAM_ADVANCE_PERIOD_TICKS = 12       -- 0.1s+0.1s（traction_blinker周期）
local FIELD_CURRENT_EXCESS_PERIOD_TICKS = 30     -- 0.1s+0.4s（同ブリンカ周期）

-- CAPACITOR(0.5s, 10s)を0～600の整数レベルで表す。
local REGEN_DELAY_DISCHARGE_TICKS = 600   -- 10s
local REGEN_DELAY_CHARGE_TICKS = 30       -- 0.5s
local REGEN_DELAY_FULL = REGEN_DELAY_DISCHARGE_TICKS
local REGEN_DELAY_CHARGE_STEP = REGEN_DELAY_FULL // REGEN_DELAY_CHARGE_TICKS -- 20
local REGEN_DELAY_DISCHARGE_STEP = 1

--------------------------------------------------------------------------
-- 小さなヘルパー
--------------------------------------------------------------------------

local function clamp(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end

-- state/status用。to_u32はunsigned 32bit境界を強制する。
function to_u32(value)
    return string.unpack("I4", string.pack("I4", math.floor(value or 0) & 0xFFFFFFFF))
end

-- minifierの括弧削除バグ回避: 異なる優先順位の演算子を1式へまとめない。
-- この分解を短い複合式へ戻さないこと（DESIGN_LOG.md #18）。

function get_bits(acc, shift, width)
    local shifted = acc >> shift
    local one_shifted = 1 << width
    local mask = one_shifted - 1
    return shifted & mask
end

function get_bit(acc, shift)
    local shifted = acc >> shift
    local bit = shifted & 1
    return bit ~= 0
end

function put_bits(value, shift, width)
    local one_shifted = 1 << width
    local mask = one_shifted - 1
    local floored = math.floor(value or 0)
    local masked = floored & mask
    return masked << shift
end

function put_bit(b, shift)
    local bit = b and 1 or 0
    return bit << shift
end

-- リセット優先。
function sr_latch(old_q, set, reset)
    if reset then return false end
    if set then return true end
    return old_q
end

-- CAPACITOR(0.1s, 0)相当。disableで即0。
local function debounce_step(old_counter, enable)
    if enable then
        return math.min(old_counter + 1, CAP_DEBOUNCE_TICKS)
    end
    return 0
end

local function debounce_charged(old_counter)
    return old_counter >= CAP_DEBOUNCE_TICKS
end

-- BLINKER+PULSEの定常周期だけを表す。disableで0、初回位相は原型と異なる。
local function periodic_pulse_step(old_counter, enable, period_ticks)
    if not enable then
        return 0, false
    end
    local counter = old_counter + 1
    if counter >= period_ticks then
        return 0, true
    end
    return counter, false
end

-- CAPACITOR(0.5s, 10s)相当。満充電でactive、完全放電まで保持する。
local function regen_delay_step(old_level, old_active, enable)
    local new_level = enable
        and math.min(old_level + REGEN_DELAY_CHARGE_STEP, REGEN_DELAY_FULL)
        or math.max(old_level - REGEN_DELAY_DISCHARGE_STEP, 0)
    local new_active = old_active and (new_level > 0) or (new_level >= REGEN_DELAY_FULL)
    return new_level, new_active
end

--------------------------------------------------------------------------
-- 物理演算（n409.luaからの移植）
--------------------------------------------------------------------------

local function calc_phi(iF)
    return iF * Kmu * Ks * PHIs / (Ks * math.abs(iF) + PHIs)
end

local function deriv_phi(iF)
    return Kmu * Ks * PHIs * PHIs / ((Ks * math.abs(iF) + PHIs) * (Ks * math.abs(iF) + PHIs))
end

-- 戻り値: motor_current, back_emf, accel, W, iF_a, bcT,
-- new_I, new_IF_A, new_PHI。原型はscripts/n409.lua。
function physics_tick(speed, vl, position_counter, direction, notch_eff, phase1, phase2, regen,
    notch_ge1, low_bc_with_regen_flag, regen_bc_smooth_seed, regen_bc_target, OLD_I, OLD_IF_A, OLD_PHI)
    local rpm = speed * 9.55 * GEAR_RATIO / WHEEL_R
    local notch = position_counter + 1 -- n409.lua's "notch" var is actually cam-position+1
    local res = 100000
    local srsmtr = 4
    local iF_a = 150
    local target_i = NEWTON_SEED

    if (not phase1) and (not phase2) then vl = 0 end
    if phase1 then srsmtr = 8 end
    if phase2 and notch == 1 then srsmtr = 4 end

    if regen then
        if low_bc_with_regen_flag then
            local oldtrq = direction * (MOT_CTRL * 9.55 * K * OLD_PHI * OLD_I * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT)
            iF_a = OLD_IF_A + (oldtrq - regen_bc_smooth_seed) * 20
            iF_a = iF_a * math.min(1, (470 / (K * math.abs(rpm))) / calc_phi(iF_a + OLD_I * 0.15))
        else
            -- 弱め界磁力行: ノッチ1～3は界磁電流追従、4以上は電機子電流を限流値へ追従。
            if notch_ge1 and notch_eff <= 3 then target_i = OLD_IF_A end
            if notch_ge1 and notch_eff > 3 then target_i = POWER_LIMIT_CURRENT end
            if not notch_ge1 then target_i = 0 end
            if target_i == 0 then target_i = math.max(math.min(0, OLD_I + 20), OLD_I - 20) end
            iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        end
    else
        target_i = OLD_IF_A
        if notch_eff == 0 then target_i = 0 end
        iF_a = OLD_IF_A + (OLD_I - target_i) * 0.1
        if notch_eff ~= 0 and iF_a > 180 then iF_a = 180 end
    end

    if srsmtr == 8 then res = SR[notch] end
    if srsmtr == 4 then res = PR[notch] end

    if iF_a < 20 then iF_a = 20 elseif iF_a > 500 then iF_a = 500 end

    -- minifierの変数名衝突を避けるため、Newton反復を独立local関数へ戻さない。
    local newton_vt, newton_n, newton_rpn, newton_pf, newton_ifa = vl / srsmtr, rpm, res / srsmtr, direction * 0.2, iF_a * direction
    local i = NEWTON_SEED
    local phi = 0
    for _ = 1, 5 do
        local iF = i * newton_pf + newton_ifa
        phi = calc_phi(iF)
        local dphi = deriv_phi(iF)
        local ndf = K * dphi * newton_pf * newton_n + MOT_RES + newton_rpn
        local fx = K * phi * newton_n - newton_vt + (MOT_RES + newton_rpn) * i
        if math.abs(ndf) >= 0.000001 then
            i = i - fx / ndf
        else
            if ndf > 0 then
                i = i - fx
            elseif ndf < 0 then
                i = i + fx
            end
        end
    end
    phi = calc_phi(i * newton_pf + newton_ifa)
    if vl == 0 then i = 0; phi = 0 end

    local trqN = 9.55 * K * phi * i
    local bcT = math.min(direction * MOT_CTRL * trqN * GEAR_RATIO / WHEEL_R / WEIGHT, 0) - regen_bc_target
    if bcT < 0.01 and i < 0 then bcT = 0 end

    return i, K * phi * rpm, MOT_CTRL * trqN * GEAR_RATIO * 0.99 / WHEEL_R / WEIGHT, vl * i * (MOT_CTRL / srsmtr) * 2,
        iF_a, bcT, i, iF_a, phi
end

--------------------------------------------------------------------------
-- ステートの直列化/復元。割付はSIGNAL_MAP.mdと同時に更新する。
--------------------------------------------------------------------------

function zero_state()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

-- 戻り値: position_counter, phase1_latch, phase2_latch, regen_latch,
-- traction_advance_counter, field_current_excess_counter,
-- regen_delay_level, regen_delay_active, phase1_cap_counter,
-- phase2_cap_counter, current_below_limit_cap_counter, OLD_I, OLD_IF_A,
-- OLD_PHI, regen_bc_smooth, bc_target_smooth。
function decode_state(state_in)
    local latches = to_u32(state_in[1])
    local timers = to_u32(state_in[2])
    return get_bits(latches, 0, 5), get_bit(latches, 5), get_bit(latches, 6), get_bit(latches, 7),
        get_bits(latches, 8, 4), get_bits(latches, 12, 5),
        get_bits(timers, 0, 10), get_bit(timers, 19), get_bits(timers, 10, 3), get_bits(timers, 13, 3), get_bits(timers, 16, 3),
        state_in[3], state_in[4], state_in[5], state_in[6], state_in[7]
end

-- 引数の並びはdecode_stateの戻り値と同じ順序。
function encode_state(position_counter, phase1_latch, phase2_latch, regen_latch,
    traction_advance_counter, field_current_excess_counter,
    regen_delay_level, regen_delay_active, phase1_cap_counter, phase2_cap_counter, current_below_limit_cap_counter,
    OLD_I, OLD_IF_A, OLD_PHI, regen_bc_smooth, bc_target_smooth)
    local slot1 = put_bits(position_counter, 0, 5)
        | put_bit(phase1_latch, 5)
        | put_bit(phase2_latch, 6)
        | put_bit(regen_latch, 7)
        | put_bits(traction_advance_counter, 8, 4)
        | put_bits(field_current_excess_counter, 12, 5)
    local slot2 = put_bits(regen_delay_level, 0, 10)
        | put_bits(phase1_cap_counter, 10, 3)
        | put_bits(phase2_cap_counter, 13, 3)
        | put_bits(current_below_limit_cap_counter, 16, 3)
        | put_bit(regen_delay_active, 19)
    return {
        slot1, slot2,
        OLD_I or 0, OLD_IF_A or 0, OLD_PHI or 0,
        regen_bc_smooth or 0, bc_target_smooth or 0,
        0, -- spare
    }
end

-- 引数: speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw,
-- direction, notch_pos, controller_stop, regen_flag。
function encode_stateless_in(speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw,
    direction, notch_pos, controller_stop, regen_flag)
    return {
        speed or 0, catenary_voltage_sw or 0, brake_pressure_sw or 0, sap_pressure_sw or 0,
        direction or 0, notch_pos or 0,
        (controller_stop and 1) or 0,
        (regen_flag and 1) or 0,
    }
end

-- 戻り値: motor_current, W, bc_target_smooth, bcT, cam_pulse,
-- phase1_latch, phase2_latch, regen_latch, notch_ge1,
-- low_bc_with_regen_flag, field_current_excess_cond, power_cut。
function decode_stateless_out(stateless_out)
    local status = to_u32(stateless_out[5])
    return stateless_out[1], stateless_out[2], stateless_out[3], stateless_out[4],
        get_bit(status, 0), get_bit(status, 1), get_bit(status, 2), get_bit(status, 3),
        get_bit(status, 4), get_bit(status, 5), get_bit(status, 6), get_bit(status, 7)
end

--------------------------------------------------------------------------
-- tickサブステップ群。それぞれおおむねSPEC.md各節1つに対応（各関数の
-- コメントに個別の§を記載）。
-- 位置引数・多値返却である理由は `DESIGN_LOG.md` #13（storm-lua-minifyは
-- テーブルキー文字列を短縮できないため）。test/harness.luaの名前付き
-- テーブルラッパーはテスト境界だけの変換で、deployビルドには含まれない。
--------------------------------------------------------------------------

local function decode_inputs(stateless_in)
    -- 戻り値: speed, catenary_voltage_sw, brake_pressure_sw（SAP直結/ECB
    -- オフセット換算いずれもゲート側で解決済みの値。本モジュールはSAP車か
    -- ECB車かを知らない）, sap_pressure_sw（同）, direction（ゲート側で
    -- forward/backwardから合成済みの-1/0/+1）, notch_pos, controller_stop,
    -- regen_flag。
    return stateless_in[1], stateless_in[2], stateless_in[3], stateless_in[4], stateless_in[5],
        clamp(math.floor(stateless_in[6] or 0), 0, 7),
        (stateless_in[7] or 0) ~= 0,
        (stateless_in[8] or 0) ~= 0
end

-- SPEC §11（traction_inhibit／牽引故障ラッチ）。`power_cut`自体は死コードと証明済み
-- （`DESIGN_LOG.md` #9）でここでは折り畳んで扱わない。
local function eb_and_brake_pressure(speed, brake_pressure_sw, direction, controller_stop)
    local overspeed = math.abs(speed) > OVERSPEED_THRESHOLD
    local brake_below_min = brake_pressure_sw < BRAKE_MIN_PRESSURE
    return controller_stop or (direction == 0) or overspeed or brake_below_min
end

-- SPEC §6.1（notch処理）＋§6.2のカム位置echo（notch_fb）。
-- 戻り値: notch_eff, notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1,
-- notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14。
local function notch_and_cam_feedback(notch_pos, position_counter, eb_condition)
    local notch_eff = notch_pos * (eb_condition and 0 or 1)
    -- カム位置echoはEB下で0（元のcurrent_src_muxの置換 ─ EB時はch7のみ生存）。
    local notch_fb = eb_condition and 0 or position_counter
    return notch_eff,
        notch_eff >= 1 and notch_eff <= 7,
        notch_eff >= 2 and notch_eff <= 7,
        notch_eff >= 3 and notch_eff <= 7,
        notch_fb == 0,
        notch_fb >= 0 and notch_fb <= 13,
        notch_fb >= 14 and notch_fb <= 20,
        notch_fb == 14,
        notch_fb ~= 14
end

-- SPEC §10.1（regen-BCターゲット、毎tick再計算）。sap_pressure_swはゲート側で
-- 解決済み（decode_inputs参照）。戻り値: regen_bc_target,
-- low_bc_with_regen_flag, regen_current。
local function brake_demand(sap_pressure_sw, regen_flag)
    local regen_bc_target = -math.floor((sap_pressure_sw - 1) * 2) / 7.2
    return regen_bc_target, regen_bc_target < BC_TARGET_MIN and regen_flag, math.max(-regen_bc_target, 0)
end

-- current_src_mux のEB置換：EB下ではch7（bcT、ここではregen_currentを保持）
-- のみ生存、他は0。引数・戻り値ともphysics_tickと同じ並び:
-- motor_current, W, accel, iF_a, bcT。
local function eb_substitute(motor_current, W, accel, iF_a, bcT, eb_condition, regen_current)
    if eb_condition then
        return 0, 0, 0, 0, regen_current
    end
    return motor_current, W, accel, iF_a, bcT
end

-- SPEC §7.2/§7.3のデバウンスタイマー（電流リミット、phase1/phase2自身の
-- 「0.1s継続でON」ゲート）。`*_charged`はOLDカウンタ（今tickの判断用）、
-- `*_next`は次tick保存用。戻り値: current_below_limit_cap_charged,
-- current_below_limit_cap_counter_next, phase1_cap_charged,
-- phase1_cap_counter_next, phase2_cap_charged, phase2_cap_counter_next。
local function debounce_block(phase1_latch, phase2_latch, current_below_limit_cap_counter,
    phase1_cap_counter, phase2_cap_counter, motor_current)
    local current_limit_sw = phase2_latch and (POWER_LIMIT_CURRENT - 20) or POWER_LIMIT_CURRENT
    local current_below_limit = motor_current < current_limit_sw
    return debounce_charged(current_below_limit_cap_counter), debounce_step(current_below_limit_cap_counter, current_below_limit),
        debounce_charged(phase1_cap_counter), debounce_step(phase1_cap_counter, phase1_latch),
        debounce_charged(phase2_cap_counter), debounce_step(phase2_cap_counter, phase2_latch)
end

-- 中立判定の電流許容範囲。
local function current_near_zero(motor_current)
    return motor_current >= -50 and motor_current <= 50
end

-- ノッチOFF後の界磁電流超過。戻り値: brake_current_high_phase1,
-- field_current_excess_cond, field_current_excess_counter_next,
-- field_current_excess_pulse。
local function field_current_excess_block(phase1_latch, regen_bc_smooth, field_current_excess_counter,
    iF_a, notch_ge1, phase1_cap_charged)
    local phase1_low_bc = phase1_latch and regen_bc_smooth < REGEN_BC_MIN
    local brake_limit_sw = phase1_low_bc and BRAKE_LIMIT_400 or BRAKE_LIMIT_300
    local brake_current_above_300 = iF_a > BRAKE_LIMIT_300
    local field_current_excess_cond = (iF_a > brake_limit_sw) and (not notch_ge1)
    local counter_next, pulse = periodic_pulse_step(
        field_current_excess_counter, field_current_excess_cond, FIELD_CURRENT_EXCESS_PERIOD_TICKS)
    return brake_current_above_300 and phase1_cap_charged, field_current_excess_cond, counter_next, pulse
end

-- 直列/並列/界磁制御の状態機械。戻り値:
-- phase1_latch, phase2_latch, regen_latch, traction_any_active,
-- output_zero_this_tick。
local function phase_state_machine(phase1_latch, phase2_latch, regen_latch,
    notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
    motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
    phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged, speed, eb_condition)
    local phase1_notch_active = phase1_latch and notch_ge1
    local phase1_regen_active = phase1_latch and notch_fb_ne14 and regen_latch
    local power_with_regen = notch_ge1 and notch_fb_ge1

    local near_stop = math.abs(speed) < STUCK_RELEASE_SPEED_THRESHOLD
    local neutral_cond = current_near_zero(motor_current) and not (notch_ge1 or low_bc_with_regen_flag)
    local coasting_cond = neutral_cond and (not regen_latch)
    -- DB自動OFF時の界磁電流超過は速度に関係なく全解放する。
    local phase_reset_cond = coasting_cond or (field_current_excess_pulse and (not regen_flag))

    -- カム0の並列＋界磁制御固着を低速中立時だけ解放する。
    -- 共有パルスへ合流すると直列を誤SETするため、phase2_reset専用とする。
    local stuck_at_top_idle = regen_latch and phase2_latch and (not phase1_latch) and notch_fb_ge1
        and neutral_cond and near_stop

    local phase1_set_cond = notch_ge2 and notch_fb_range_low
        and phase1_cap_charged and current_below_limit_cap_charged
    -- 界磁電流超過による並列→直列降格はDB自動ON時だけ。
    local phase1_set = (power_with_regen and (not phase2_latch))
        or (field_current_excess_pulse and phase2_latch and regen_flag)

    local phase2_blinker_cond = notch_ge3 and notch_fb_range_high
        and phase2_cap_charged and current_below_limit_cap_charged
    local phase2_set_cond = notch_ge3 and notch_fb_eq14 and current_below_limit_cap_charged

    -- 牽引禁止、またはDB自動OFF中の直列＋界磁制御は無条件に全解放する。
    local db_auto_off_in_series_field_control = (not regen_flag) and phase1_latch and regen_latch
    local force_full_disconnect = eb_condition or db_auto_off_in_series_field_control

    local phase2_reset = phase_reset_cond or (phase1_latch and not (notch_ge3 and notch_fb_eq14))
        or stuck_at_top_idle or force_full_disconnect

    -- 並列セットと同tickに直列をリセットする。
    local phase1_reset = phase_reset_cond
        or (field_current_excess_pulse and phase1_cap_charged)
        or phase2_set_cond
        or force_full_disconnect

    local traction_all_off = (not phase1_latch) and (not phase2_latch)
    local regen_off_all = (not notch_fb_ge1) and traction_all_off

    local phase1_latch_next = sr_latch(phase1_latch, phase1_set, phase1_reset)
    local phase2_latch_next = sr_latch(phase2_latch, phase2_set_cond, phase2_reset)

    -- 旧ラッチで計算済みの同tick出力を安全側へ0化するための遷移フラグ。
    local output_zero_this_tick = (phase1_latch or phase2_latch) and (not phase1_latch_next) and (not phase2_latch_next)

    return phase1_latch_next,
        phase2_latch_next,
        sr_latch(regen_latch, phase2_latch and notch_fb_ge1, phase1_notch_active or traction_all_off or force_full_disconnect),
        phase1_set_cond or phase2_blinker_cond or regen_off_all or phase1_regen_active,
        output_zero_this_tick
end

-- SPEC §6.2/§7.4 カム進段（traction_any_active中の周期パルス）。戻り値:
-- position_counter, cam_pulse, traction_advance_counter_next。
local function advance_cam(position_counter, traction_advance_counter, traction_any_active)
    local counter_next, pulse = periodic_pulse_step(
        traction_advance_counter, traction_any_active, CAM_ADVANCE_PERIOD_TICKS)
    local new_position = (position_counter + (pulse and 1 or 0)) % 21
    local delta = new_position - position_counter
    return new_position, delta ~= 0, counter_next -- cam_pulseはカム位置が変化した(通常の+1進段も20->0の折返しも)tickでtrue
end

-- 回生指令と自車加速度の平滑化。force時はMomelink-A用EMA状態も即時0化する。
-- 戻り値: bc_target_smooth, regen_bc_smooth, regen_delay_level, regen_delay_active。
local function smooth_bc(bc_target_smooth, regen_bc_smooth, regen_delay_level, regen_delay_active,
    accel, regen_bc_target, regen_flag, brake_current_high_phase1, force_bc_target_zero)
    local regen_bc_enable = regen_delay_active or (not regen_flag)
    local regen_bc_sw = regen_bc_enable and 0 or regen_bc_target
    local regen_delay_level_next, regen_delay_active_next =
        regen_delay_step(regen_delay_level, regen_delay_active, brake_current_high_phase1)
    local bc_target_smooth_next = force_bc_target_zero and 0 or (accel * 0.2 + bc_target_smooth * 0.8)
    return bc_target_smooth_next,
        math.min(clamp(regen_bc_sw, regen_bc_smooth - 0.1, regen_bc_smooth + 0.02), 0),
        regen_delay_level_next, regen_delay_active_next
end

--------------------------------------------------------------------------
-- tick本体
--------------------------------------------------------------------------

-- calculateTickはdeploy/main.luaのstate_sync境界が使う。
function core_tick(stateless_in, state_in)
    local st_position_counter, st_phase1_latch, st_phase2_latch, st_regen_latch,
        st_traction_advance_counter, st_field_current_excess_counter,
        st_regen_delay_level, st_regen_delay_active, st_phase1_cap_counter, st_phase2_cap_counter, st_current_below_limit_cap_counter,
        st_OLD_I, st_OLD_IF_A, st_OLD_PHI, st_regen_bc_smooth, st_bc_target_smooth = decode_state(state_in)
    local speed, catenary_voltage_sw, brake_pressure_sw, sap_pressure_sw, direction,
        notch_pos, controller_stop, regen_flag = decode_inputs(stateless_in)

    local eb_condition = eb_and_brake_pressure(speed, brake_pressure_sw, direction, controller_stop)
    local notch_eff, notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1,
        notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14 =
        notch_and_cam_feedback(notch_pos, st_position_counter, eb_condition)
    local regen_bc_target, low_bc_with_regen_flag, regen_current = brake_demand(sap_pressure_sw, regen_flag)

    -- 物理演算は循環参照を避けるためOLDラッチを使う。
    local physics_motor_current, _back_emf, accel, physics_W, physics_iF_a, physics_bcT,
        phys_OLD_I, phys_OLD_IF_A, phys_OLD_PHI =
        physics_tick(speed, catenary_voltage_sw, st_position_counter, direction, notch_eff,
            st_phase1_latch, st_phase2_latch, st_regen_latch, notch_ge1, low_bc_with_regen_flag,
            st_regen_bc_smooth, regen_bc_target, st_OLD_I, st_OLD_IF_A, st_OLD_PHI)
    local motor_current, elec_W, elec_accel, iF_a, bcT = eb_substitute(
        physics_motor_current, physics_W, accel, physics_iF_a, physics_bcT, eb_condition, regen_current)

    local current_below_limit_cap_charged, current_below_limit_cap_counter_next,
        phase1_cap_charged, phase1_cap_counter_next, phase2_cap_charged, phase2_cap_counter_next =
        debounce_block(st_phase1_latch, st_phase2_latch, st_current_below_limit_cap_counter,
            st_phase1_cap_counter, st_phase2_cap_counter, motor_current)

    local brake_current_high_phase1, field_current_excess_cond,
        field_current_excess_counter_next, field_current_excess_pulse =
        field_current_excess_block(st_phase1_latch, st_regen_bc_smooth, st_field_current_excess_counter,
            iF_a, notch_ge1, phase1_cap_charged)

    local phase1_latch, phase2_latch, regen_latch, traction_any_active, output_zero_this_tick = phase_state_machine(
        st_phase1_latch, st_phase2_latch, st_regen_latch,
        notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
        motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
        phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged, speed, eb_condition)

    -- このtickで全解放した場合、OLDラッチ由来の電気出力を残さない。
    if output_zero_this_tick then
        motor_current, elec_W = 0, 0
    end

    local position_counter, cam_pulse, traction_advance_counter_next =
        advance_cam(st_position_counter, st_traction_advance_counter, traction_any_active)
    local bc_target_smooth, regen_bc_smooth, regen_delay_level, regen_delay_active =
        smooth_bc(st_bc_target_smooth, st_regen_bc_smooth, st_regen_delay_level, st_regen_delay_active,
            elec_accel, regen_bc_target, regen_flag, brake_current_high_phase1,
            eb_condition or output_zero_this_tick)

    ----------------------------------------------------------------
    -- 出力の組み立て
    ----------------------------------------------------------------

    local status_bits = put_bit(cam_pulse, 0)
        | put_bit(phase1_latch, 1)
        | put_bit(phase2_latch, 2)
        | put_bit(regen_latch, 3)
        | put_bit(notch_ge1, 4)
        | put_bit(low_bc_with_regen_flag, 5)
        | put_bit(field_current_excess_cond, 6)
        -- power_cut（bit 7）は死コード互換の常時0

    local stateless_out = {
        motor_current,
        elec_W,
        bc_target_smooth,
        bcT,
        status_bits,
        0, 0, 0,
    }

    local state_out = encode_state(
        position_counter, phase1_latch, phase2_latch, regen_latch,
        traction_advance_counter_next, field_current_excess_counter_next,
        regen_delay_level, regen_delay_active, phase1_cap_counter_next, phase2_cap_counter_next, current_below_limit_cap_counter_next,
        phys_OLD_I, phys_OLD_IF_A, phys_OLD_PHI, regen_bc_smooth, bc_target_smooth)

    return stateless_out, state_out
end
