# Signal Map — CHUSO1800 Lua Core

`CHUSO1800_Traction_Controller/main.sw-net`／`scripts/n409.lua` の各信号が、
`src/chuso1800_core.lua` の
`calculateTick(stateless_in, state_in) -> stateless_out, state_out` という
契約上のどこに対応するかを示す、一次情報源となる文書。

- 節番号（`SPEC §x.y`）はすべて `../CHUSO1800_Traction_Controller/SPEC.md` を指す。
- 契約そのもの（純関数性・tickモデル・テスト方法）は README.md を参照。
  本文書が扱うのは**スロット/ビット割付**のみ。
- 「なぜこの割付になったか」（当初案・却下した代替案・変更のきっかけ）は
  本文書には書かない。該当箇所には `DESIGN_LOG.md` の番号（`#n`）を添えてある。
- 本ディレクトリは `CHUSO1800_Traction_Controller/` を一切変更しない。
  `main.sw-net` への実配線は今後の別作業（README.md「今後の実配線について」参照）。

## スロットの型

4本の配列（`stateless_in`・`state_in`／`state_out`・`stateless_out`）は
いずれも配列 `[1..8]`、各要素はLua数値1個。tick Nの `state_out` はそのまま
tick N+1の `state_in` として戻ってくる。各スロットは次のどちらか：

- **生のdouble** ─ 1スロット1信号。
- **パック済み32bit整数** ─ `to_u32`/`get_bits`/`put_bits`/`get_bit`/`put_bit`
  （いずれも `src/chuso1800_core.lua` に直接書かれている）でビット位置ごとに
  直接組み立て・分解する。複数のbool・小整数を1スロットに同居させる。
  当初は汎用の「レイアウトテーブル＋`pack_bits(layout, fields)`」方式
  だったが、フィールド名の文字列がstorm-lua-minifyで短縮できず
  Stormworksの8192文字制限を圧迫していたため、ビット位置（shift/width）を
  直接指定する方式に置き換えた（経緯は `DESIGN_LOG.md` #13）。

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
| 7 | `bc_target_smooth`（BC目標平滑値） | 準ステート・生double |
| 8 | 予備（常に0） | ─ |

### `stateless_out[1..8]`（現在tickの出力。8本中5本使用）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | `motor_current` | 生double |
| 2 | `W` | 生double |
| 3 | `bc_target_smooth`（平滑化後） | 生double |
| 4 | `bcT` | 生double |
| 5 | カム/フェーズ状態など8bool | パック済み STATUS_BITS_LAYOUT |
| 6 | 予備（常に0） | ─ |
| 7 | 予備（常に0） | ─ |
| 8 | 予備（常に0） | ─ |

---

## ステートスロットのレイアウト

STATE_LATCHES_LAYOUT／STATE_TIMERS_LAYOUT／STATUS_BITS_LAYOUTという名称は
以下、各ビット群を指す**説明用のラベル**であり、`src/chuso1800_core.lua`
内に同名のLua識別子（テーブル）としては存在しない（`decode_state`/
`encode_state`/`decode_stateless_out`内でビット位置を直接指定して
組み立て・分解している。経緯は `DESIGN_LOG.md` #13）。

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

**周期カウンタの意味論**：`traction_advance_counter`／
`field_current_excess_counter` は `periodic_pulse_step` の経過tickカウンタで、
main.sw-net の `BLINKER`+`PULSE(rise)` ペア（`traction_blinker`＋
`position_tick_pulse`、`field_current_excess_blinker`＋
`field_current_excess_pulse`）の置き換え。`enable` 中は毎tick +1、
`period_ticks`（=on_time+off_time相当。カム進段は12、界磁電流超過検知は30）に
達したら0へ戻しつつパルスを1回発火、`enable` が偽なら即座に0へリセットする。
**元設計との挙動差あり**：最初のパルスが有効化から `period_ticks` 後に来る
（元設計は最短で `off_ticks` 後）。定常状態の周期は同一。実装詳細は
`src/chuso1800_core.lua` の `periodic_pulse_step` のコメント、この置き換えを
選んだ経緯は `DESIGN_LOG.md` #7。

`field_current_excess_*` は旧名 `regen_warning_*`（`main.sw-net`・`SPEC.md`と
合わせて改名。経緯は `DESIGN_LOG.md` #10）。

### `state_in[2]`／`state_out[2]` — STATE_TIMERS_LAYOUT（32bit中19bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `regen_delay_level` | 10 | 0-600（`CAPACITOR(0.5, 10)`相当。詳細下記） |
| 2 | `phase1_cap_counter` | 3 | 0-6 |
| 3 | `phase2_cap_counter` | 3 | 0-6 |
| 4 | `current_below_limit_cap_counter` | 3 | 0-6 |

13bit予備（19-31）。

**`regen_delay_level` のスケール**：`regen_delay_cap`
（0.5秒充電/10秒放電）を0-600のスケール済み整数として表現する。
600（=10秒相当のtick数）が「満充電」。放電は -1/tick で正確に600 tick
（10秒）かけて0へ、充電は同じ0-600の幅を30 tick（0.5秒）で埋めるため
600/30=+20/tick。両方とも整数の割り算で厳密に割り切れるため浮動小数点誤差が
一切生じず、「充電完了」判定は単純な `>= 600`。定数の導出は
`src/chuso1800_core.lua` の `REGEN_DELAY_*` 定数群・`regen_delay_step`/
`regen_delay_charged` のコメントを参照。生の秒数doubleとして持つ案を却下した
経緯は `DESIGN_LOG.md` #6。

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
| 3 | `bc_target_smooth` | `BC target [atm]` 出力系列へ |
| 4 | `bcT` | 既存の（ラベルは紛らわしいが変更していない）`speed_display`／Momelink ch25 経路へ |
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
| 8 | `power_cut` | 1 | 常時0固定 ─ README.md「意図的な簡略化」参照 |

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
| `position_counter`（0-20） | `FUNC_NUM_3 position_counter`、`(x+y)%21` の自己ループ | §3.2 |
| `phase1_latch` | `SR_LATCH traction_phase1_latch` | §3.6 |
| `phase2_latch` | `SR_LATCH traction_phase2_latch` | §3.6 |
| `regen_latch` | `SR_LATCH regen_latch` | §3.6 |
| `traction_phase1_cap`／`traction_phase2_cap`／`current_below_limit_cap` | `CAPACITOR(0.1, 0)` ×3 | §3.6／§3.7 |
| `regen_delay_cap` | `CAPACITOR(0.5, 10)` | §3.8 |
| `traction_blinker`+`position_tick_pulse`（0.1/0.1） | `BLINKER`+`PULSE(rise)` | §3.2 |
| `field_current_excess_blinker`+`field_current_excess_pulse`（0.1/0.4） | `BLINKER`+`PULSE(rise)` | §3.6 |

2組の `BLINKER`+`PULSE(rise)` ペアは、それぞれ単一の経過tickカウンタ
（`traction_advance_counter`／`field_current_excess_counter`）として
表現している ─ 意味論・挙動差は上記 STATE_LATCHES_LAYOUT 節を参照
（経緯は `DESIGN_LOG.md` #7）。

意図的にステートとして持たせていないもの：

- `power_cut_latch_q`／`startup_delay`／`motor_current_oor` 系
  ─ SPEC §4.4 の通り死コードであることが証明できる。常時 `false` の
  ステータスビットとしてのみ残してある（README.md「意図的な簡略化」1項、
  経緯は `DESIGN_LOG.md` #9）。
- **パンタグラフ4ラッチ**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`、SPEC §3.9）─ ゲート側に残す
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

`notch_eff`、`notch_ge1..4`、`eb_condition`（実機の値である
`direction == 0` のみを用いる ─ SPEC §4.2。storm-mclのシリアライズ不具合と
される sw-net 字面上の `(0,1)` のしきい値は再現しない）、`power_with_regen`、
`coasting_cond`／`neutral_cond`／`phase_reset_cond`、`current_below_limit`
（デバウンス前）、`regen_available`、`brake_below_min`、`overspeed`、
`regen_bc_target`、`current_limit_sw`、`traction_any_active`（周期パルス
反映前）。

`direction`／`brake_pressure_sw`／`sap_pressure_sw` はこのモジュールでは
**計算しない**（最終値のまま受け取る ─ 上記「ステートレス入力スロットの
レイアウト」参照）。

## ゲートに残すもの（今回は未Lua化）

- **SAP/ECBブレーキ圧解決一式**（`sap_ecb_toggle`／`ecb_pressure_sw`／
  `brake_pressure_sw`／`ecb_sap_pressure`／`sap_pressure_sw`とその周辺、
  SPEC §3.8）。このモジュールは最終値の`brake_pressure_sw`／
  `sap_pressure_sw`のみをステートレス入力スロット3・4として受け取る
  （上記「ステートレス入力スロットのレイアウト」参照、経緯は
  `DESIGN_LOG.md` #4）。
- **direction合成**（`forward_flag_sw`／`backward_flag_sw`／`direction`
  SUBTRACTノード）。このモジュールは最終値の`direction`（-1/0/+1）のみを
  ステートレス入力スロット5として受け取る（同 #4）。
- **パンタグラフ4ラッチ一式**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`とその周辺 ─ `panta1_set_cond`／
  `panta2_set_cond`／`is_1800_type`／`panta1_1800_active`等、SPEC §3.9）。
  このモジュールはExtended IFのパンタ関連signal・`property.getBool("M
  type")`のいずれも参照しない（経緯は `DESIGN_LOG.md` #2）。
- **架線電圧セレクタ一式**（`catenary_active_thresh` … `catenary_voltage_sw`）
  ─ パンタグラフラッチがゲート側にあるため、`panta1_1800_active`／
  `panta2_1800_active`はゲート側で計算されたものをそのまま読む
  （このモジュールの出力には依存しない）。
- Momelink-A整形（`momelink_1800_out`／`momelink_1900_out`／
  `momelink_version_sw`／`momelink_src_mux`／`momelink_1900_select`）。
- Rolling Stock Status整形（`rolling_status_bool_write`／
  `rolling_status_write`／`bc_pressure_kpa`等 ─ パンタ関連ビットもゲート側
  計算のものをそのまま使う）。
- `bc_target_read`（編成内Momelinkパススルー ─ 今回の移行とは無関係）。

いずれも純粋なステートレスのデータ整形・muxか、独自に完結するラッチで
あり、本モジュールとの結合度は低い。
