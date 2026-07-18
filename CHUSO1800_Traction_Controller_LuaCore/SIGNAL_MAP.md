# Signal Map — CHUSO1800 Lua Core

`core_tick(stateless_in, state_in) -> stateless_out, state_out`のスロットと
ビット割付を定義する一次情報源。挙動は[`SPEC.md`](./SPEC.md)、判断理由は
[`DESIGN_LOG.md`](./DESIGN_LOG.md)を参照する。

## スロットの型

4本の配列（`stateless_in`・`state_in`／`state_out`・`stateless_out`）は
いずれも配列 `[1..8]`、各要素はLua数値1個。tick Nの `state_out` はそのまま
tick N+1の `state_in` として戻ってくる。各スロットは次のどちらか：

- **生のdouble** ─ 1スロット1信号。
- **パック済み32bit整数** ─ `to_u32`/`get_bits`/`put_bits`/`get_bit`/`put_bit`
  でビット位置を直接指定する。複数のbool・小整数を1スロットに同居させる。

---

## 全体像：4本の配列×8スロット 早見表

細部を読まずに全体を把握するための一覧。ビット単位の内訳は後続の各節、
割付に至った経緯は `DESIGN_LOG.md` を参照。

### `stateless_in[1..8]`（現在tickのセンサ相当・都度計算に使う入力。8本すべて使用、予備なし）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | `speed`（m/s） | 生double |
| 2 | `catenary_voltage_sw`（V） | 生double |
| 3 | `brake_pressure_sw`（ゲート側で最終値まで解決済み） | 生double |
| 4 | `sap_pressure_sw`（ゲート側で最終値まで解決済み） | 生double |
| 5 | `direction`（-1/0/+1、ゲート側で解決済み） | 生double |
| 6 | `notch_pos`（0-7、Simple IFの数値そのまま） | 生double |
| 7 | `controller_stop`（0/1） | 生double（bool） |
| 8 | `regen_flag`（0/1） | 生double（bool） |

### `state_in[1..8]` ／ `state_out[1..8]`（tickをまたいで持ち越す状態。8本中7本使用、1本予備）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | カム段＋3個のSRラッチ＋2個の周期カウンタ | パック済み STATE_LATCHES_LAYOUT |
| 2 | `regen_delay`レベル＋3個のデバウンスカウンタ | パック済み STATE_TIMERS_LAYOUT |
| 3 | `OLD_I`（前tickの電機子電流） | 準ステート・生double |
| 4 | `OLD_IF_A`（前tickの界磁電流） | 準ステート・生double |
| 5 | `OLD_PHI`（前tickの磁束） | 準ステート・生double |
| 6 | `regen_bc_smooth`（回生BC平滑値） | 準ステート・生double |
| 7 | `bc_target_smooth`（自車平滑加速度） | 準ステート・生double |
| 8 | 予備（常に0） | ─ |

### `stateless_out[1..8]`（現在tickの出力。8本中5本使用）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | `motor_current` | 生double |
| 2 | `W` | 生double |
| 3 | `bc_target_smooth`（自車平滑加速度） | 生double |
| 4 | `bcT`（空気ブレーキ補完減速度要求） | 生double |
| 5 | カム/フェーズ状態など8bool | パック済み STATUS_BITS_LAYOUT |
| 6 | 予備（常に0） | ─ |
| 7 | 予備（常に0） | ─ |
| 8 | 予備（常に0） | ─ |

---

## ステートスロットのレイアウト

STATE_LATCHES_LAYOUT／STATE_TIMERS_LAYOUT／STATUS_BITS_LAYOUTは説明用ラベルで、
実装は`decode_state`／`encode_state`／`decode_stateless_out`にビット位置を
直接記述する。

### `state_in[1]`／`state_out[1]` — STATE_LATCHES_LAYOUT（32bit中17bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `position_counter` | 5 | 0-20（0-31まで表現可） |
| 2 | `phase1_latch` | 1 | bool |
| 3 | `phase2_latch` | 1 | bool |
| 4 | `regen_latch` | 1 | bool |
| 5 | `traction_advance_counter` | 4 | 0-12（`periodic_pulse_step`の経過tick） |
| 6 | `field_current_excess_counter` | 5 | 0-30（`periodic_pulse_step`の経過tick） |

15bit予備（17-31）。

両カウンタは`periodic_pulse_step`の経過tick。enable中に毎tick +1し、
カム進段は12、界磁電流超過は30で0へ戻して1パルス発火する。disableで0へ戻る。
原型との初回位相差は`SPEC.md` §6と`DESIGN_LOG.md` #7を参照する。

`field_current_excess_*` は旧名 `regen_warning_*`（`main.sw-net`・`SPEC.md`と
合わせて改名。経緯は `DESIGN_LOG.md` #10）。

### `state_in[2]`／`state_out[2]` — STATE_TIMERS_LAYOUT（32bit中20bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `regen_delay_level` | 10 | 0-600（`CAPACITOR(0.5, 10)`相当。詳細下記） |
| 2 | `phase1_cap_counter` | 3 | 0-6 |
| 3 | `phase2_cap_counter` | 3 | 0-6 |
| 4 | `current_below_limit_cap_counter` | 3 | 0-6 |
| 5 | `regen_delay_active`（bit19） | 1 | 0/1（ヒステリシス出力ラッチ。詳細下記） |

12bit予備（20-31）。

`regen_delay_level`は`CAPACITOR(0.5, 10)`相当を0～600で表す。充電は
+20/tick、放電は-1/tick。整数演算により境界誤差を避ける。

`regen_delay_active`はヒステリシス出力で、levelが600へ達するとON、0へ達すると
OFFになる。途中の値では前状態を維持する。詳細は`SPEC.md` §10。

### `state_in[3..7]`／`state_out[3..7]` — 生double（準ステート、「分類(b)」参照）

| slot | フィールド |
|---|---|
| 3 | `OLD_I` |
| 4 | `OLD_IF_A` |
| 5 | `OLD_PHI` |
| 6 | `regen_bc_smooth` |
| 7 | `bc_target_smooth` |

**実装上の注意（Newton法のシード）**：Newton法の反復初期値は `OLD_I` では
ない。`n409.lua` は `input.getNumber(6)` から初期値を得ており、これは
`main.sw-net` の `sim_input` で毎tick固定の `CONST(200)` に配線されている。
`physics_tick` は `state.OLD_I` ではなく定数 `200` からシードしなければ
ならない。

### `state_in[8]`／`state_out[8]` — 予備（現状は常に0）

## ステートレス入力スロットのレイアウト（8本すべて使用、予備なし）

| slot | 内容 | 由来 |
|---|---|---|
| 1 | `speed`（m/s） | Physics Sensor ch9 |
| 2 | `catenary_voltage_sw`（V） | ゲート側で計算した値をそのまま入力として受け取る |
| 3 | `brake_pressure_sw` | main.sw-netの`brake_pressure_sw`ノード（SAP/ECBいずれの場合も解決済み） |
| 4 | `sap_pressure_sw` | main.sw-netの`sap_pressure_sw`ノード（同上） |
| 5 | `direction`（-1/0/+1） | main.sw-netの`direction`ノード（forward/backwardから合成済み） |
| 6 | `notch_pos`（0-7、生double） | Simple IF ch2 |
| 7 | `controller_stop`（0/1、生double） | トップレベル `Controller Stop` ポート |
| 8 | `regen_flag`（0/1、生double） | Simple IF ch18 bool |

- 全8スロットとも生double。**入力側にビットパックは使わない**
  （`INPUT_BITS_LAYOUT` を廃止した経緯は `DESIGN_LOG.md` #5）。
- スロット3-5（`brake_pressure_sw`／`sap_pressure_sw`／`direction`）は、
  main.sw-net に既存の同名ノードが計算した**最終値**をそのまま受け取る。
  SAP/ECBの圧力換算（ECB車の「SAP/BP換算値」計算を含む）と
  forward/backward 2boolからの `direction` 合成はすべてゲート側で行われ、
  本モジュールは車両がSAP車かECB車かを一切知らない（生センサ値
  `sap_raw`／`eb_signal`／`forward_signal`／`backward_signal` を受け取る
  設計から変更した経緯は `DESIGN_LOG.md` #4）。
- パンタグラフ関連の6bool（Extended IF由来）はゲート側に残したため、この
  モジュールへは配線していない（下記「ゲートに残すもの」参照）。

## ステートレス出力スロットのレイアウト（8本中5本使用）

| slot | 内容 | 外部に出す理由 |
|---|---|---|
| 1 | `motor_current` | DANRYUゲート、Momelink-1900のch24 |
| 2 | `W` | 出力ポート `W` へ直結 |
| 3 | `bc_target_smooth`（自車平滑加速度） | Momelink-A ch2／ch26へ |
| 4 | `bcT`（空気ブレーキ補完減速度要求） | `x*3.6+1`でBC絶対圧目標へ変換し、Momelink ch25へ |
| 5 | STATUS_BITS_LAYOUT のパック済みビットフィールド（32bit中8bit、下記参照） | RSS／Momelink側のゲート |
| 6-8 | 予備（0） | |

元 `current_src_mux` チャンネルとの対応：

- ch2（逆起電力）・ch5（カム段echoである `notch_fb`）・ch6（`iF_a`）は
  **出力しない** ─ 唯一の読み手だった状態機械が本モジュールに吸収された
  ことで、`main.sw-net` 上に消費者が1つも残っていないため（消費者ゼロを
  `COMPOSITE_READ_*` の総ざらいで確認した経緯は `DESIGN_LOG.md` #8）。
- ch3（`accel`）は生値を出力せず、平滑化後の `bc_target_smooth`（スロット3）
  に置き換わっている ─ `accel` の唯一の用途だった `bc_target_raw` のEMA計算が
  本モジュールに内部化された（分類(b)）ため。

### STATUS_BITS_LAYOUT（8bit）

| 順序 | フィールド | bit数 | 現状ゲート側で消費されているか |
|---|---|---|---|
| 1 | `cam_pulse` | 1 | される ─ 出力ポート `cam` に直結 |
| 2 | `phase1_latch` | 1 | されない ─ 予備／デバッグ用 |
| 3 | `phase2_latch` | 1 | されない ─ 予備／デバッグ用 |
| 4 | `regen_latch` | 1 | されない ─ 予備／デバッグ用 |
| 5 | `notch_ge1` | 1 | されない ─ 予備／デバッグ用 |
| 6 | `low_bc_with_regen_flag` | 1 | されない ─ 予備／デバッグ用 |
| 7 | `field_current_excess_cond` | 1 | されない ─ 予備／デバッグ用 |
| 8 | `power_cut` | 1 | 常時0固定 ─ `SPEC.md` §11参照 |

パンタグラフの状態ビット（`panta1_1800_active` 等）はこのレイアウトには
**存在しない** ─ パンタグラフラッチそのものがゲート側にあり、架線電圧
セレクタ・RSSはゲート側で計算された `panta*_1800_active`/
`panta*_1800_latched` を直接読むため（下記「ゲートに残すもの」参照、
経緯は `DESIGN_LOG.md` #2）。

---

## 信号の由来と分類（sw-net → 本モジュールの対応）

各信号がsw-net上のどのノードに由来し、上記レイアウトのどの区分に
収まっているかの対応表。

### 分類(a) — 真のラッチ状態・タイマー → パック済みステートビットフィールドへ

| 信号 | sw-net上の由来 | SPEC節 |
|---|---|---|
| `position_counter`（0-20） | `FUNC_NUM_3 position_counter`、`(x+y)%21` の自己ループ | §6.2 |
| `phase1_latch`（直列） | `SR_LATCH traction_phase1_latch` | §7.1／§7.2 |
| `phase2_latch`（並列） | `SR_LATCH traction_phase2_latch` | §7.1／§7.2 |
| `regen_latch`（界磁制御。力行・回生の両方で使う） | `SR_LATCH regen_latch` | §7.1／§7.2 |
| `traction_phase1_cap`／`traction_phase2_cap`／`current_below_limit_cap` | `CAPACITOR(0.1, 0)` ×3 | §7.2／§7.3 |
| `regen_delay_cap` | `CAPACITOR(0.5, 10)` | §10.3 |
| `traction_blinker`+`position_tick_pulse`（0.1/0.1） | `BLINKER`+`PULSE(rise)` | §6.2 |
| `field_current_excess_blinker`+`field_current_excess_pulse`（0.1/0.4） | `BLINKER`+`PULSE(rise)` | §7.5 |

2組の `BLINKER`+`PULSE(rise)` ペアは、それぞれ単一の経過tickカウンタ
（`traction_advance_counter`／`field_current_excess_counter`）として
表現している ─ 意味論・挙動差は上記 STATE_LATCHES_LAYOUT 節を参照
（経緯は `DESIGN_LOG.md` #7）。

意図的にステートとして持たせていないもの：

- `power_cut_latch_q`／`startup_delay`／`motor_current_oor` 系
  ─ 到達不能な死コードとしてLua化せず、常時`false`のstatus bitだけを残す
  （`DESIGN_LOG.md` #9）。
- **パンタグラフ4ラッチ**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`、SPEC §12）─ ゲート側に残す
  （下記「ゲートに残すもの」参照、経緯は `DESIGN_LOG.md` #2）。

### 分類(b) — 準ステート（自己参照して減衰する生double）

| 信号 | 由来 | 式 |
|---|---|---|
| `OLD_I` | `n409.lua` グローバル変数 | 直近tickのNewton法解（電機子電流） |
| `OLD_IF_A` | `n409.lua` グローバル変数 | 直近tickの界磁電流 |
| `OLD_PHI` | `n409.lua` グローバル変数 | 直近tickの磁束 |
| `regen_bc_smooth` | `FUNC_NUM_3` 自己ループ | `min(clamp(x, y-0.1, y+0.02), 0)` |
| `bc_target_smooth` | `FUNC_NUM_3` 自己ループ | `x*0.2 + y*0.8`（EMA） |

いずれもステートスロット3-7の生double（Newton法の反復初期値が `OLD_I` では
ない点は、上記 `state_in[3..7]` 節の実装上の注意を参照）。

`regen_delay_cap`（分類(a)の`regen_delay_level`）はここには**含まれない**
─ 平滑化用の自己参照ではなく、単純な充放電タイマーなのでパック済み整数
フィールド（STATE_TIMERS_LAYOUT）に収めている。

### 分類(c) — ステートレス（毎tick再計算）

`notch_eff`、`notch_ge1..4`、`eb_condition`（`SPEC.md` §5の牽引禁止）、
`power_with_regen`、
`coasting_cond`／`neutral_cond`／`phase_reset_cond`、`current_below_limit`
（デバウンス前）、`regen_available`、`brake_below_min`、`overspeed`、
`regen_bc_target`、`current_limit_sw`、`traction_any_active`（周期パルス
反映前）。

`direction`／`brake_pressure_sw`／`sap_pressure_sw` はこのモジュールでは
**計算しない**（最終値のまま受け取る ─ 上記「ステートレス入力スロットの
レイアウト」参照）。

## ゲートに残すもの

以下は`main.sw-net`上の現在名で記載する。

- **SAP/ECBブレーキ管圧解決一式**（`brake_system_is_sap`／
  `ecb_virtual_brake_pipe`／`brake_pipe_for_inhibit`／
  `ecb_brake_demand_pressure`／`brake_demand_pressure`とその周辺、
  SPEC §9）。このモジュールは最終値の`brake_pipe_for_inhibit`／
  `brake_demand_pressure`のみをステートレス入力スロット3・4として受け取る
  （上記「ステートレス入力スロットのレイアウト」参照、経緯は
  `DESIGN_LOG.md` #4）。
- **direction合成**（`forward_direction_value`／`reverse_direction_value`／
  `direction_sign` SUBTRACTノード）。このモジュールは最終値の
  `direction_sign`（-1/0/+1）のみをステートレス入力スロット5として
  受け取る（同 #4）。
- **パンタグラフ4ラッチ一式**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`とその周辺 ─ `panta1_set_cond`／
  `panta2_set_cond`／`vehicle_type_1800`／`panta1_1800_active`等、
  SPEC §12）。このモジュールはExtended IFのパンタ関連signal・
  `property.getBool("M type")`のいずれも参照しない（経緯は
  `DESIGN_LOG.md` #2）。
- **架線電圧セレクタ一式**（`catenary_input_zero` … `traction_supply_voltage`）
  ─ パンタグラフラッチがゲート側にあるため、`panta1_1800_active`／
  `panta2_1800_active`はゲート側で計算されたものをそのまま読む
  （このモジュールの出力には依存しない）。
- Momelink-A整形（`momelink_1800_frame`／`momelink_advanced_frame`／
  `momelink_output_frame_mux`／`status_data_source`／
  `use_1900_advanced_frame`）。
- Rolling Stock Status整形（`rolling_stock_status_bool`／
  `rolling_stock_status`／`bc_gauge_pressure_kpa`等 ─ パンタ関連ビットも
  ゲート側計算のものをそのまま使う）。
- `status_bc_target`（編成内Momelinkパススルー ─ 今回の移行とは無関係）。

いずれも純粋なステートレスのデータ整形・muxか、独自に完結するラッチで
あり、本モジュールとの結合度は低い。
