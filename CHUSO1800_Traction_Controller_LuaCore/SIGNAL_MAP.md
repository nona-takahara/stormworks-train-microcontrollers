# Signal Map — CHUSO1800 Lua Core

`CHUSO1800_Traction_Controller/main.sw-net`／`scripts/n409.lua` の各信号が、
`src/chuso1800_core.lua` が実装する
`calculateTick(stateless_in, state_in) -> stateless_out, state_out` という
契約上のどこに対応するかを示す、一次情報源となる文書。以下の節番号
（`SPEC §x.y`）はすべて `../CHUSO1800_Traction_Controller/SPEC.md` を指す。

本ディレクトリは `CHUSO1800_Traction_Controller/` を一切変更しない。あくまで
スタンドアロンのプロトタイプであり、`main.sw-net` への実配線は今後の別作業
（README.md の「今後の実配線について」を参照）。

## 契約の形

```
calculateTick(stateless_in, state_in) -> stateless_out, state_out
```

- `stateless_in`・`stateless_out`：配列 `[1..8]`、各要素はLua数値1個。
- `state_in`・`state_out`：配列 `[1..8]`、各要素はLua数値1個。
  tick Nの `state_out` は、そのままtick N+1の `state_in` として戻ってくる。
- 各スロットは生のdoubleか、`pack_bits(layout, fields)` で生成し
  `unpack_bits(layout, value)` で分解する整数のどちらか。両関数は
  `src/chuso1800_core.lua` に直接書かれている（Stormworksに`require`が
  存在しないため、別ファイルへの切り出しはしていない）。

## 分類(a) — 真のラッチ状態 → パック済みステートビットフィールドへ

| 信号 | sw-net上の由来 | SPEC節 |
|---|---|---|
| `position_counter`（0-20） | `FUNC_NUM_3 position_counter`、`(x+y)%21` の自己ループ | §3.2 |
| `phase1_latch` | `SR_LATCH traction_phase1_latch` | §3.6 |
| `phase2_latch` | `SR_LATCH traction_phase2_latch` | §3.6 |
| `regen_latch` | `SR_LATCH regen_latch` | §3.6 |
| `panta1_latch`／`panta2_latch` | `SR_LATCH panta1_latch`／`panta2_latch` | §3.9 |
| `panta1_en_latch`／`panta2_en_latch` | `SR_LATCH panta1_en_latch`／`panta2_en_latch` | §3.9 |
| `traction_phase1_cap`／`traction_phase2_cap`／`current_below_limit_cap` | `CAPACITOR(0.1, 0)` ×3 | §3.6／§3.7 |
| `traction_blinker`+`position_tick_pulse`（0.1/0.1） | `BLINKER`+`PULSE(rise)` | §3.2 |
| `regen_warning_blinker`+`regen_warning_pulse`（0.1/0.4） | `BLINKER`+`PULSE(rise)` | §3.6 |

`regen_delay_cap`（`CAPACITOR(0.5, 10)`、§3.8）は分類(b)へ、生doubleの
`regen_delay_seconds` として移した（詳細は下記「実装上の見直し」参照）。

`traction_blinker`/`regen_warning_blinker` は `periodic_pulse_step` という
単一の経過tickカウンタに置き換えている：このモジュールのどこも
ブリンカの生のON/OFF出力そのものを読んでおらず、そこから駆動される
周期パルス（カム進段・回生警告パルス）だけが意味を持つため、
`BLINKER`+`PULSE(rise)` のペアより単純な形で表現できる。詳細は下記
「実装上の見直し」を参照。

意図的にステートとして持たせていないもの（README.md「簡略化した点」参照）：

- `power_cut_latch_q`／`startup_delay`／`motor_current_oor` 系
  ─ SPEC §4.4 の通り死コードであることが証明できる。常時 `false` の
  ステータスビットとしてのみ残してある。

## 分類(b) — 準ステート（自己参照して減衰する生double）

| 信号 | 由来 | 式 |
|---|---|---|
| `OLD_I` | `n409.lua` グローバル変数 | 直近tickのNewton法解（電機子電流） |
| `OLD_IF_A` | `n409.lua` グローバル変数 | 直近tickの界磁電流 |
| `OLD_PHI` | `n409.lua` グローバル変数 | 直近tickの磁束 |
| `regen_bc_smooth` | `FUNC_NUM_3` 自己ループ | `min(clamp(x, y-0.1, y+0.02), 0)` |
| `bc_target_smooth` | `FUNC_NUM_3` 自己ループ | `x*0.2 + y*0.8`（EMA） |

**実装上の注意**：Newton法の反復初期値は `OLD_I` ではない。`n409.lua` は
`input.getNumber(6)` から初期値を得ており、これは `main.sw-net` の
`sim_input` で毎tick固定の `CONST(200)` に配線されている。`physics_tick`
は `state.OLD_I` ではなく定数 `200` からシードしなければならない。

## 分類(c) — ステートレス（毎tick再計算）

`notch_eff`、`notch_ge1..4`、`direction`、`eb_condition`（実機の値である
`direction == 0` のみを用いる ─ SPEC §4.2。storm-mclのシリアライズ不具合と
される sw-net 字面上の `(0,1)` のしきい値は再現しない）、`power_with_regen`、
`coasting_cond`／`neutral_cond`／`phase_reset_cond`、`current_below_limit`
（デバウンス前）、`regen_available`、`brake_below_min`、`overspeed`、
`regen_bc_target`、`ecb_sap_pressure`、`current_limit_sw`、
`traction_any_active`（ブリンカ反映前）。

## ステートスロットのレイアウト

### `state_in[1]`／`state_out[1]` — `STATE_LATCHES_LAYOUT`（32bit中21bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `position_counter` | 5 | 0-20（0-31まで表現可） |
| 2 | `phase1_latch` | 1 | bool |
| 3 | `phase2_latch` | 1 | bool |
| 4 | `regen_latch` | 1 | bool |
| 5 | `panta1_latch` | 1 | bool |
| 6 | `panta2_latch` | 1 | bool |
| 7 | `panta1_en_latch` | 1 | bool |
| 8 | `panta2_en_latch` | 1 | bool |
| 9 | `traction_advance_counter` | 4 | 0-12（`periodic_pulse_step`の経過tick） |
| 10 | `regen_warning_counter` | 5 | 0-30（`periodic_pulse_step`の経過tick） |

11bit予備（21-31）。

**実装上の見直し（当初案からの変更点）**：main.sw-net の
`BLINKER`+`PULSE(rise)` ペアを素朴に1:1移植すると、ブリンカの位相ビット
（ON/OFF）＋カウンタ＋エッジ検出用の「前回出力」ビットが必要になり、
かつ「有効化してから最初のパルスまでの遅延」が非対称なon_time/off_timeに
依存して分かりにくくなる。しかしこのモジュールのどこも、ブリンカの生の
ON/OFF出力そのものを他の信号として読んでおらず、そこから駆動される
周期パルス（カム進段・回生警告パルス）だけが意味を持つ。そこで
`periodic_pulse_step` という単一の経過tickカウンタ（`enable`中は+1、
`period_ticks`（=on_time+off_time相当）に達したら0にリセットしつつパルスを
1回発火、`enable`が偽なら即座に0へリセット）に置き換えた。位相ビットも
「前回出力」ビットも不要になり、ビット数を削減できている。ただし
挙動は変化する：最初のパルスが有効化から`period_ticks`後に来る
（元設計は最短で`off_ticks`後）。詳細は `src/chuso1800_core.lua` の
`periodic_pulse_step` のコメントを参照。

### `state_in[2]`／`state_out[2]` — `STATE_TIMERS_LAYOUT`（32bit中9bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `phase1_cap_counter` | 3 | 0-6 |
| 2 | `phase2_cap_counter` | 3 | 0-6 |
| 3 | `current_below_limit_cap_counter` | 3 | 0-6 |

23bit予備（9-31）。

### `state_in[3..8]`／`state_out[3..8]` — 生double

| slot | フィールド |
|---|---|
| 3 | `OLD_I` |
| 4 | `OLD_IF_A` |
| 5 | `OLD_PHI` |
| 6 | `regen_bc_smooth` |
| 7 | `bc_target_smooth` |
| 8 | `regen_delay_seconds`（0-0.5、`CAPACITOR(0.5, 10)`相当。詳細下記） |

**実装上の見直し**：`regen_delay_cap`（0.5秒充電/10秒放電）は、当初は
±20/tick・-1/tickで動く0-600のスケール済み整数としてパック済みビット
フィールドに収めていたが、この×20という倍率は「両方の増減を整数にする
ための帳尻合わせ」でしかなく、可読性が低い。charge_time/discharge_time
というSPEC自体の秒単位の表現に直接合わせ、生の秒数（0〜0.5）として
生doubleスロットへ移した：`enable`中は+1/60秒、`disable`中は
-1/1200秒（0.5秒÷10秒＝20倍遅い減衰）、それぞれ0〜0.5でクランプ。
これにより **ステートスロット8を新たに1本消費**しており、ステート予算は
8本中8本使用（予備0本）に変わった（旧設計は7本中7本使用・1本予備）。
「充電完了」判定は `>= 0.5 - イプシロン` で行う（1/60を30回加算すると
浮動小数点誤差で0.49999999999999994にしかならず、素の `>=0.5` だと
30tick（0.5秒）ではなく31tickかかってしまうため）。詳細は
`src/chuso1800_core.lua` の `regen_delay_step`/`regen_delay_charged` の
コメントを参照。

## ステートレス入力スロットのレイアウト

`SAP_ECB_IS_SAP`（`property.getBool("SAP or ECB")`、sw-netの
`sap_ecb_toggle` と同名のプロパティ）が真のときのみ `brake_pressure_sw`/
`sap_pressure_sw` がスロット5・6（`"BP [atm]"`/`"SAP [atm]"`）を読む。偽
（既定値。`PROPERTY_TOGGLE` に `v=` の指定がなければオフ＝「ECB」ラベル。
`main.sw-net` の102行目付近、およびSPEC §3.8「既定 OFF=ECB」を参照）の間は
ECB経由の計算値を使い、スロット5・6は読まれるが使用されない。

| slot | 内容 | 由来 |
|---|---|---|
| 1 | `speed`（m/s） | Physics Sensor ch9 |
| 2 | `catenary_voltage_sw`（V） | ゲート側で計算した値をそのまま入力として受け取る |
| 3 | `sap_raw` | Simple IF ch1（数値）─ ブレーキハンドル位置、0-8程度 |
| 4 | `INPUT_BITS_LAYOUT` のパック済みビットフィールド（32bit中14bit、下記参照） | Simple IF／Extended IF／Controller Stop |
| 5 | `"BP [atm]"`（`SAP_ECB_IS_SAP`が真の間だけ使用） | BPセンサポート |
| 6 | `"SAP [atm]"`（`SAP_ECB_IS_SAP`が真の間だけ使用） | SAPセンサポート |
| 7-8 | 予備（0） | |

### `INPUT_BITS_LAYOUT`（14bit）

| 順序 | フィールド | bit数 | 由来 |
|---|---|---|---|
| 1 | `notch_pos` | 3 | Simple IF ch2（数値、パック時に0-7へクランプ） |
| 2 | `controller_stop` | 1 | トップレベル `Controller Stop` ポート |
| 3 | `regen_flag` | 1 | Simple IF ch18 bool |
| 4 | `forward_signal` | 1 | Simple IF ch16 bool |
| 5 | `backward_signal` | 1 | Simple IF ch17 bool |
| 6 | `eb_signal` | 1 | Simple IF ch1 bool |
| 7 | `panta_enable_signal` | 1 | Extended IF ch6 bool |
| 8 | `panta_all_down_signal` | 1 | Extended IF ch7 bool |
| 9 | `panta1_up_signal` | 1 | Extended IF ch4 bool |
| 10 | `panta1_down_signal` | 1 | Extended IF ch5 bool |
| 11 | `panta2_up_signal` | 1 | Extended IF ch8 bool |
| 12 | `panta2_down_signal` | 1 | Extended IF ch9 bool |

## ステートレス出力スロットのレイアウト

`current_src_mux` のch2（逆起電力）・ch5（カム段echoである `notch_fb`）・
ch6（`iF_a`）は、それらの唯一の読み手だった状態機械が本モジュールに
吸収されたことで、`main.sw-net` 上に消費者が1つも残っていない
（`current_src_mux_out`／`traction_status_bool_out` に対する
`COMPOSITE_READ_NUMBER`／`COMPOSITE_READ_BOOLEAN` を総ざらいして確認済み）
─ そのため出力しない。ch3（`accel`）も `bc_target_raw` のEMA計算のみに
使われていたが、そのEMA自体が内部化された（分類b）ため、生値ではなく
平滑化後の値を出力する。

| slot | 内容 | 外部に出す理由 |
|---|---|---|
| 1 | `motor_current` | DANRYUゲート、Momelink-1900のch24 |
| 2 | `W` | 出力ポート `W` へ直結 |
| 3 | `bc_target_smooth` | `BC target [atm]` 出力系列へ |
| 4 | `bcT` | 既存の（ラベルは紛らわしいが変更していない）`speed_display`／Momelink ch25 経路へ |
| 5 | `STATUS_BITS_LAYOUT` のパック済みビットフィールド（32bit中12bit、下記参照） | RSS／Momelink／架線電圧mux側のゲート |
| 6-8 | 予備（0） | |

### `STATUS_BITS_LAYOUT`（12bit）

| 順序 | フィールド | bit数 | 現状ゲート側で消費されているか |
|---|---|---|---|
| 1 | `cam_pulse` | 1 | される ─ 出力ポート `cam` に直結 |
| 2 | `panta1_1800_active` | 1 | される ─ RSS ch6、架線電圧の `panta_up` mux |
| 3 | `panta2_1800_active` | 1 | される ─ RSS ch8、架線電圧の `panta_up` mux |
| 4 | `panta1_1800_latched` | 1 | される ─ RSS ch5 |
| 5 | `panta2_1800_latched` | 1 | される ─ RSS ch7 |
| 6 | `phase1_latch` | 1 | されない ─ 予備／デバッグ用 |
| 7 | `phase2_latch` | 1 | されない ─ 予備／デバッグ用 |
| 8 | `regen_latch` | 1 | されない ─ 予備／デバッグ用 |
| 9 | `notch_ge1` | 1 | されない ─ 予備／デバッグ用 |
| 10 | `low_bc_with_regen_flag` | 1 | されない ─ 予備／デバッグ用 |
| 11 | `regen_warning_cond` | 1 | されない ─ 予備／デバッグ用 |
| 12 | `power_cut` | 1 | 常時0固定 ─ README.md「簡略化した点」参照 |

## ゲートに残すもの（今回は未Lua化）

- 架線電圧セレクタ一式（`catenary_active_thresh` … `catenary_voltage_sw`）
  ─ 本モジュールの `panta1_1800_active`／`panta2_1800_active` 出力ビットを
  読む形は変わらない。
- Momelink-A整形（`momelink_1800_out`／`momelink_1900_out`／
  `momelink_version_sw`／`momelink_src_mux`／`momelink_1900_select`）。
- Rolling Stock Status整形（`rolling_status_bool_write`／
  `rolling_status_write`／`bc_pressure_kpa`等）。
- `bc_target_read`（編成内Momelinkパススルー ─ 今回の移行とは無関係）。

いずれも純粋なステートレスのデータ整形・muxであり、独自のラッチ状態を
持たない。Lua化しても得るものは特にない。
