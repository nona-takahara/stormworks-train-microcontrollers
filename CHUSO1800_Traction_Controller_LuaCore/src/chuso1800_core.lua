-- CHUSO1800 トラクション制御：状態機械＋物理演算の統合コア。
--
-- 純関数契約：calculateTick(stateless_in, state_in) -> stateless_out, state_out。
-- いずれも要素数8のLua数値配列。tick Nのstate_outはそのままtick N+1の
-- state_inとしてフィードバックされる。制御状態を持つ永続グローバルは
-- 使わない（物理・BC平滑化の準ステートもパック済みラッチ/タイマーも、
-- すべてstate_in/state_outの中だけで完結する）。
--
-- 信号→スロット/ビット割付の一次情報源は ../SIGNAL_MAP.md（各式の由来
-- =SPEC.md節番号もそちら）。
--
-- tickモデル（詳細はREADME.md「tickモデル」）：フィードバック経路を持つ
-- ノード（SRラッチ・デバウンス・周期パルス・物理準ステート・BC平滑化）は
-- OLD値（state_in）を今tickの判断に使い、NEW値をstate_outへ書く。それ以外の
-- 純粋な組み合わせ論理は同tick内で即座に確定させる（元のゲートネットの
-- 「全ゲート1tick遅延」モデルより単純化しているが、SPEC.md自身が許容する
-- 簡略化 ─ 8ステートスロットに収めるために必要）。
--
-- 元のゲート名をそのままローカル変数へ機械移植した1枚の巨大関数にはせず、
-- SPEC.md §3.x各節にほぼ対応する小関数へ分割し、core_tick（末尾）が順に
-- 呼び出す。periodic_pulse_step・regen_delay_stepは、逐語移植より意図的に
-- 単純化した箇所（コーナーケースのtick数がズレる場合があるが定常状態の
-- 挙動は変わらない）。経緯は各関数のコメントと `DESIGN_LOG.md` #6/#7。
--
-- 物理演算（Newton法）は
-- ../../CHUSO1800_Traction_Controller/scripts/n409.lua からの逐語移植
-- （n409.lua自体は無改変。数値回帰は test/scenarios/physics_regression_vs_n409.lua）。
--
-- このファイルはモジュールではない：`local M = {}`を持たず、外部から
-- 呼ばれる関数はすべて`local`なしのグローバルとして定義する。理由・
-- `dofile`での読み込み方はリポジトリ共通指針 `../../LUA_CODING_GUIDE.md`
-- と `DESIGN_LOG.md` #15 を参照。

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

-- Newton法の反復シード。OLD_Iでも界磁電流制御則の`target_i`でもない点に
-- 注意：n409.luaでは外側の`target_i = input.getNumber(6)`とcalc_current_phi
-- 内部の`input.getNumber(6)`が、同じ固定CONST(200)チャンネルを互いに独立に
-- 読んでいる（`target_i`はその後界磁電流則用に再代入されるが、その再代入は
-- Newton法側には反映されない）。同一定数の2箇所独立使用として、この挙動を
-- そのまま保持している。
local NEWTON_SEED = 200

--------------------------------------------------------------------------
-- Stormworksの`property`値。spawn時に1回だけ読む（走行中は変化しないため
-- 毎tick読み直す必要がない）。main.sw-netの対応PROPERTY_NUMBERノードと
-- 同じプロパティ名を使い、車両ごとの調整をゲーム内property panelで
-- 引き続き可能にする（詳細経緯は `DESIGN_LOG.md` #3）。property.get*()は
-- 8+8のcomposite channel予算の外側なので、入力スロットは消費しない。
--
-- `property`グローバルはStormworks実機が提供する。素の`lua`のテスト環境
-- には存在しないため、test/run_all.luaがこのファイルをdofileする前に
-- main.sw-net側の各ノードのデフォルト値（value=属性）と同じ内容のスタブを
-- グローバルとして用意する（このファイル自体にフォールバックを書かない
-- ことで、deployビルドの対象コードから完全に除外する）。
--------------------------------------------------------------------------

local OVERSPEED_THRESHOLD = property.getNumber("Over Speed Th. [m/s]")     -- m/s
local POWER_LIMIT_CURRENT = property.getNumber("Power Limit Current [A]") -- A

-- main.sw-netでは単純なCONSTノード（PROPERTY_*ではなく元設計でも
-- ゲーム内調整不可）だったため、ソース定数のままにしてある。
local BRAKE_MIN_PRESSURE = 4         -- atm
local BRAKE_LIMIT_300 = 300
local BRAKE_LIMIT_400 = 400
local REGEN_BC_MIN = -0.1
local BC_TARGET_MIN = -0.05

-- 「固着カムからの脱出」（DESIGN_LOG.md #23/#26/#27）の発動をほぼ停止状態
-- （並列の全短絡ステップへ再接続しても実害が出ない速度域）だけに限定する
-- しきい値。8m/s以上では定常電流が自己制御域（200A、POWER_LIMIT_CURRENT
-- 未満）へ収束することを確認済みだが、この値は「巡航中の短い惰性走行では
-- 絶対に解放しない」ための保守的なマージンを取ってある（経緯は
-- `DESIGN_LOG.md` #27）。
local STUCK_RELEASE_SPEED_THRESHOLD = 3 -- m/s

-- tick数由来のタイマー定数（Stormworksは60tick/秒前提、SPEC §0.2）。
local CAP_DEBOUNCE_TICKS = 6              -- 0.1sデバウンス、無効化で即0
local CAM_ADVANCE_PERIOD_TICKS = 12       -- 0.1s+0.1s（traction_blinker周期）
local FIELD_CURRENT_EXCESS_PERIOD_TICKS = 30     -- 0.1s+0.4s（同ブリンカ周期）

-- regen_delayは元CAPACITOR(charge_time=0.5s, discharge_time=10s)。
-- 0.5s=30tick、10s=600tick。levelは大きい方（600）にスケールし、放電は
-- 1/tick、充電は600/30=20/tickの整数刻みにしてある（浮動小数点の
-- 誤差蓄積を避けるため。経緯は `DESIGN_LOG.md` #6）。
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

-- パック済みstate/statusスロット用のビット操作ヘルパー（ビット割付は
-- SIGNAL_MAP.md参照、ここにテーブルとしては持たない。経緯は
-- `DESIGN_LOG.md` #13）。to_u32はstring.pack/unpack("I4",...)の往復で
-- 32bit境界を強制（実機のunsigned 32bitと同じくオーバーフローは
-- wrapする）。get_bits/put_bitsはビット位置指定でフィールドを
-- 取り出し/組み立てる。
function to_u32(value)
    return string.unpack("I4", string.pack("I4", math.floor(value or 0) & 0xFFFFFFFF))
end

-- storm-lua-minify（および元ネタのluamin、上流issue
-- https://github.com/mathiasbynens/luamin/issues/76 参照）は、再出力時に
-- 「本来Luaの演算子優先順位を上書きするために必要な括弧」を、優先順位表を
-- 踏まえずに削ってしまうバグを持つ（例：`(a & b) >> c`のような、通常の
-- 優先順位（`>>`は`&`より高い）とは逆順に評価させるための括弧が、
-- 再出力時に落ちて`a & (b >> c)`相当に化ける）。detail経緯は
-- `DESIGN_LOG.md` #18。以下のビットヘルパーはすべて、二項演算子1個につき
-- 1行の`local`代入に分解してあり、これは見た目の簡潔さのためではなく
-- **上記バグの回避が目的**：どの行も「削られて困る括弧」を含まない形に
-- なっている。1行の複合式へ戻さないこと（今後追加するビット演算コードも
-- 同様に、複数の異なる優先順位の演算子が混在する式を1行にまとめない）。

function get_bits(acc, shift, width)
    local shifted = acc >> shift
    local one_shifted = 1 << width
    local mask = one_shifted - 1
    return shifted & mask
end

-- 1bitフィールドをboolean直接で返す版（state_in[1]/[2]・stateless_out[5]の
-- 大半は1bitラッチ/フラグ）。呼び出し側で get_bits(acc, shift, 1) ~= 0 と
-- 書くより短い。
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

-- get_bitの対:booleanを直接パックする（put_bits(b and 1 or 0, shift, 1)より短い）。
function put_bit(b, shift)
    local bit = b and 1 or 0
    return bit << shift
end

-- リセット優先SRラッチ（SPEC.md §0.1）。
function sr_latch(old_q, set, reset)
    if reset then return false end
    if set then return true end
    return old_q
end

-- デバウンス（元CAPACITOR(charge_time=0.1s, discharge_time=0)）：
-- 「N tick連続でenable」の単純カウンタ。無効化で即0リセット
-- （discharge_time=0と同じ）。
local function debounce_step(old_counter, enable)
    if enable then
        return math.min(old_counter + 1, CAP_DEBOUNCE_TICKS)
    end
    return 0
end

local function debounce_charged(old_counter)
    return old_counter >= CAP_DEBOUNCE_TICKS
end

-- 周期パルス（元BLINKER(on_ticks, off_ticks)+PULSE(rise)）：`enable`が
-- `period_ticks`連続したら1回パルスを出してカウント再開、無効化で0へ。
-- 生のON/OFF出力を読む箇所がなく周期パルスの方だけが意味を持つため
-- （カム進段・界磁電流超過検知）、1つの経過tickカウンタで代替している。
-- 逐語移植とのタイミング差（初回パルスがoff_ticks後ではなくperiod_ticks後）
-- は `DESIGN_LOG.md` #7・README.md「tickモデル」参照。
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

-- regen_delay（元CAPACITOR(charge_time=0.5s, discharge_time=10s)）。
-- スケーリングの導出は上のREGEN_DELAY_*定数群のコメント参照。
-- 実機CAPACITORの出力はヒステリシス付き（一度満充電でONになったら、放電し
-- 切って0に達するまでONを保持する ─ 「Offでdt秒かけてOff」という挙動。
-- `NITS_Simple_Bridge`がCAPACITOR(0,0.1)を「pulse stretcher」として使える
-- のもこの性質のため）。単純に`level>=FULL`だけを見ると、満充電の1tick後
-- （level=599）には即座に「未充電」に戻ってしまい、10秒保持という実機の
-- 意図（新SPEC.md §10.3）を再現できない。そのため`regen_delay_active`
-- という1bitの状態（前tickにONだったか）を別途持ち、ONだった場合は
-- level>0の間ずっとONを維持する形にしてある。戻り値: regen_delay_level,
-- regen_delay_active（いずれも次tick用）。
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

-- physics_tick：n409.luaのonTick本体を1対1で移植したもの。引数は元の
-- sim_input composite channel/traction_status_boolの並びに対応：
-- speed, vl(=catenary_voltage_sw), position_counter(OLDカム), direction,
-- notch_eff, phase1, phase2, regen(いずれもOLDラッチ), notch_ge1,
-- low_bc_with_regen_flag(いずれも当tickの値), regen_bc_smooth_seed(OLD,
-- ch7), regen_bc_target(当tick, ch8), OLD_I, OLD_IF_A, OLD_PHI(OLD物理
-- 準ステート)。戻り値: motor_current, back_emf, accel, W, iF_a, bcT,
-- OLD_I, OLD_IF_A, OLD_PHI(新しい準ステート)。
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
            if notch_ge1 and notch_eff <= 3 then target_i = OLD_IF_A end
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

    -- 電機子電流のNewton法（元はcalc_current_phiという独立local関数
    -- だった）をphysics_tick本体へ直接インライン化してある
    -- （DESIGN_LOG.md #24参照）。storm-lua-minifyのリネームパスに、
    -- 複数の新規ローカルを宣言する独立local関数の中で、外側スコープの
    -- 定数`K`と同じ短縮名を別の引数へ二重に割り当ててしまうバグがあり
    -- （生成されたLuaが同名引数を複数持つ不正な関数になっていた）、
    -- 結果`K * phi * n`が別の変数の値に化けて高速域で電機子電流の解が
    -- 破綻し、カムが並列以降へ一切進段しなくなっていた（#18とは異なる
    -- 種類のminifierバグ）。`physics_tick`自身は独立local関数ではなく
    -- グローバル関数本体であり、実際にstorm-lua-minifyでこのバグが
    -- 再現しないことを確認済み（同ファイル内の他の`K`使用箇所と同様）。
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
-- ステートの直列化/復元ヘルパー（core_tick自身と、test/harness.luaの
-- 名前付きテーブル変換ラッパー経由でテストスイートから使う。位置引数・
-- 多値返却である理由は下のtickサブステップと同じ ─ `DESIGN_LOG.md` #13）。
--------------------------------------------------------------------------

function zero_state()
    return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

-- 以下のビット位置（state_in[1]/[2]、stateless_out[5]）はSIGNAL_MAP.mdと
-- 完全一致させること。

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
-- tickサブステップ群。それぞれおおむねSPEC.md §3.x各節1つに対応。
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

-- SPEC §3.5（EB／power-cut条件）。`power_cut`自体は死コードと証明済み
-- （`DESIGN_LOG.md` #9）でここでは折り畳んで扱わない。
local function eb_and_brake_pressure(speed, brake_pressure_sw, direction, controller_stop)
    local overspeed = math.abs(speed) > OVERSPEED_THRESHOLD
    local brake_below_min = brake_pressure_sw < BRAKE_MIN_PRESSURE
    return controller_stop or (direction == 0) or overspeed or brake_below_min
end

-- SPEC §3.3（notch処理）＋§3.2のカム位置echo（notch_fb）。
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

-- SPEC §3.8（regen-BCターゲット、毎tick再計算）。sap_pressure_swはゲート側で
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

-- SPEC §3.6/§3.7のデバウンスタイマー（電流リミット、phase1/phase2自身の
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

-- motor_currentがほぼ0とみなせるか（SPEC §4.6 neutral_cond由来のしきい値、
-- phase_state_machineと共有。DESIGN_LOG.md #23）。
local function current_near_zero(motor_current)
    return motor_current >= -50 and motor_current <= 50
end

-- SPEC §3.6 界磁電流超過検知チェーン。main.sw-netでは"regen_warning"と
-- 誤命名されていたが回生ブレーキ警告ではない ─ iF_aはここでは界磁電流
-- （n409.luaの"brake_current_fb"/channel=6と同じ値）。「notchは0に落ちたが
-- iF_aがまだ300/400A閾値を超えている」を検知し、coasting_condの自然な
-- 電流減衰を待たずphase1/phase2を早期に畳む（改名の経緯は
-- `DESIGN_LOG.md` #10）。戻り値: brake_current_high_phase1,
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

-- SPEC §3.6 中核の状態機械：phase1/phase2/regenのSRラッチ。戻り値:
-- phase1_latch, phase2_latch, regen_latch, traction_any_active。
local function phase_state_machine(phase1_latch, phase2_latch, regen_latch,
    notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
    motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
    phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged, speed)
    local phase1_notch_active = phase1_latch and notch_ge1
    local phase1_regen_active = phase1_latch and notch_fb_ne14 and regen_latch
    local power_with_regen = notch_ge1 and notch_fb_ge1

    -- ほぼ停止状態（STUCK_RELEASE_SPEED_THRESHOLD未満）かどうか。
    -- stuck_at_top_idleとphase_reset_condの双方で共有する（#28）。
    local near_stop = math.abs(speed) < STUCK_RELEASE_SPEED_THRESHOLD
    local neutral_cond = current_near_zero(motor_current) and not (notch_ge1 or low_bc_with_regen_flag)
    local coasting_cond = neutral_cond and (not regen_latch)
    -- 【#28で修正】`field_current_excess_pulse and (not regen_flag)`は元々
    -- 「DB自動OFF中に界磁電流超過を検知したら直列へ降格させず中立へ全解放
    -- する」という意図だったが、iF_a（界磁電流相当値）はnotch=0後も電流が
    -- 完全に0でない限り毎tick`+ (OLD_I - target_i) * 0.1`ずつ際限なく増え
    -- 続ける式になっており（物理的には巡航中の並列全短絡ステップでは速度
    -- 低下とともに電流がわずかに上がり続けるため、OLD_Iが正である限り
    -- 止まらない）、notch-off直後の一時的な高電流だけでなく、巡航中の
    -- 通常の惰性走行でも数秒〜十数秒後に必ず300/400Aしきい値を超えてしまう
    -- （速度9m/s前後、電流はまだ一桁A程度でも発火することを診断で確認）。
    -- ユーザー確認済み仕様：惰性走行中は速度に関わらず並列＋界磁制御を
    -- 維持し電機子電流を界磁制御で0A近辺に保つのが正常動作であり、pulseが
    -- 発火しても並列→直列への正しい降格（phase1_set経由）に繋がるべきで、
    -- 中立への全解放は本来「ほぼ停止していて再接続の危険がある」場合
    -- （stuck_at_top_idleと同じ`near_stop`）に限定すべきだった。near_stopを
    -- 追加したことで、巡航中はphase1_setのみが有効になり（phase1_resetは
    -- この項からは発生しないため）、意図通りParallel→Seriesへ正しく降格
    -- する（phase2はその1tick後、`phase1_latch and not(...)`経由で自然に
    -- リセットされる）。
    local phase_reset_cond = coasting_cond or (field_current_excess_pulse and (not regen_flag) and near_stop)

    -- 「固着カムからの脱出」（DESIGN_LOG.md #23/#26/#27/#28）：カム0で並列
    -- (phase2)＋界磁制御(regen_latch)だけが立ったまま直列(phase1)が一度も
    -- 立たない状態は、coasting_condが要求する`not regen_latch`が恒久的に
    -- 満たせないため、界磁電流が閾値を超えない限り自然には解けない。
    -- しかしnotch/回生要求ともに無く電流もほぼ0まで収束しているなら
    -- 「単に停止している」だけなので、phase2_resetへ直接合流させて中立へ
    -- 解放する。
    -- 【#26で修正】当初はこれをfield_current_excess_pulse経由で
    -- phase1_set（並列→直列の降格SET）にも合流させていたが、
    -- `regen_flag`（DB自動）がONの間はphase_reset_condのpulse項が
    -- `not regen_flag`で無効化されるため、phase1_setだけが素通りして
    -- 直列が誤ってSETされ、その後`phase1_regen_active`
    -- （phase1_latch and notch_fb_ne14 and regen_latch）がtraction_any_active
    -- を持ち上げカムが勝手に回り出す実機バグを引き起こした。phase1_setには
    -- 一切合流させず、直接phase2_resetにのみ作用させることでこの経路自体を
    -- 断つ。
    -- 【#27で修正】`neutral_cond`（電流ほぼ0・notch/回生要求なし）だけを
    -- 条件にすると、高速巡航中の数秒程度の通常の惰性走行（電流は界磁制御
    -- 自体によってすぐ0Aへ収束する─ユーザー確認済みの仕様）でも即座に解放
    -- してしまい、並列＋界磁制御まで積み上げた進行状態を毎回失っていた
    -- （再力行のたび直列0から登り直しになり、かつ回生制動の前提となる
    -- `regen_latch`も失われ回生が一切発生しなくなる実機バグ）。実際に
    -- 再接続が危険なのは、並列の全短絡ステップ（`PR[1]=0Ω`）へほぼ停止
    -- 状態から再接続する場合だけ（`STUCK_RELEASE_SPEED_THRESHOLD`＝3m/s
    -- 未満、経緯は同定数のコメント参照）なので、速度条件を追加して
    -- 高速巡航中は解放しないようにした。
    local stuck_at_top_idle = regen_latch and phase2_latch and (not phase1_latch) and notch_fb_ge1
        and neutral_cond and near_stop

    local phase1_set_cond = notch_ge2 and notch_fb_range_low
        and phase1_cap_charged and current_below_limit_cap_charged
    local phase1_set = (power_with_regen and (not phase2_latch))
        or (field_current_excess_pulse and phase2_latch)

    local phase2_blinker_cond = notch_ge3 and notch_fb_range_high
        and phase2_cap_charged and current_below_limit_cap_charged
    local phase2_set_cond = notch_ge3 and notch_fb_eq14 and current_below_limit_cap_charged
    local phase2_reset = phase_reset_cond or (phase1_latch and not (notch_ge3 and notch_fb_eq14)) or stuck_at_top_idle

    -- phase2_set_condは追加のphase1リセットトリガも兼ねる（直列→並列の
    -- 遷移で、phase2がセットされる同tickにphase1をリセットする）。
    local phase1_reset = phase_reset_cond
        or (field_current_excess_pulse and phase1_cap_charged)
        or phase2_set_cond

    local traction_all_off = (not phase1_latch) and (not phase2_latch)
    local regen_off_all = (not notch_fb_ge1) and traction_all_off

    return sr_latch(phase1_latch, phase1_set, phase1_reset),
        sr_latch(phase2_latch, phase2_set_cond, phase2_reset),
        sr_latch(regen_latch, phase2_latch and notch_fb_ge1, phase1_notch_active or traction_all_off),
        phase1_set_cond or phase2_blinker_cond or regen_off_all or phase1_regen_active
end

-- SPEC §3.2 カム進段（traction_any_active中の周期パルス）。戻り値:
-- position_counter, cam_pulse, traction_advance_counter_next。
local function advance_cam(position_counter, traction_advance_counter, traction_any_active)
    local counter_next, pulse = periodic_pulse_step(
        traction_advance_counter, traction_any_active, CAM_ADVANCE_PERIOD_TICKS)
    local new_position = (position_counter + (pulse and 1 or 0)) % 21
    local delta = new_position - position_counter
    return new_position, delta ~= 0, counter_next -- cam_pulseはカム位置が変化した(通常の+1進段も20->0の折返しも)tickでtrue
end

-- SPEC §3.8 BC／regen-BC平滑化。戻り値: bc_target_smooth,
-- regen_bc_smooth, regen_delay_level, regen_delay_active。
local function smooth_bc(bc_target_smooth, regen_bc_smooth, regen_delay_level, regen_delay_active,
    accel, regen_bc_target, regen_flag, brake_current_high_phase1)
    local regen_bc_enable = regen_delay_active or (not regen_flag)
    local regen_bc_sw = regen_bc_enable and 0 or regen_bc_target
    local regen_delay_level_next, regen_delay_active_next =
        regen_delay_step(regen_delay_level, regen_delay_active, brake_current_high_phase1)
    return accel * 0.2 + bc_target_smooth * 0.8,
        math.min(clamp(regen_bc_sw, regen_bc_smooth - 0.1, regen_bc_smooth + 0.02), 0),
        regen_delay_level_next, regen_delay_active_next
end

--------------------------------------------------------------------------
-- tick本体
--------------------------------------------------------------------------

-- 名前は`calculateTick`ではなく`core_tick`（deploy/main.lua側のグローバル
-- `calculateTick`との衝突回避。経緯は `DESIGN_LOG.md` #15）。
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

    -- 物理演算は常にOLDのphase1/phase2/regenを使う（physics<->状態機械の
    -- 循環参照を断ち切るため。ファイル冒頭「tickモデル」参照）。physics_tick
    -- の戻り値9個の並び: motor_current, back_emf（ここでは未使用 ─
    -- physics_regression_vs_n409.luaがphysics_tick直接呼び出しで使うのみ）,
    -- accel, W, iF_a, bcT, OLD_I, OLD_IF_A, OLD_PHI。
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

    local phase1_latch, phase2_latch, regen_latch, traction_any_active = phase_state_machine(
        st_phase1_latch, st_phase2_latch, st_regen_latch,
        notch_ge1, notch_ge2, notch_ge3, notch_fb_ge1, notch_fb_range_low, notch_fb_range_high, notch_fb_eq14, notch_fb_ne14,
        motor_current, low_bc_with_regen_flag, field_current_excess_pulse, regen_flag,
        phase1_cap_charged, phase2_cap_charged, current_below_limit_cap_charged, speed)

    local position_counter, cam_pulse, traction_advance_counter_next =
        advance_cam(st_position_counter, st_traction_advance_counter, traction_any_active)
    local bc_target_smooth, regen_bc_smooth, regen_delay_level, regen_delay_active =
        smooth_bc(st_bc_target_smooth, st_regen_bc_smooth, st_regen_delay_level, st_regen_delay_active,
            elec_accel, regen_bc_target, regen_flag, brake_current_high_phase1)

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
        -- power_cut（bit 7）は常時0。README「意図的な簡略化」参照

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
