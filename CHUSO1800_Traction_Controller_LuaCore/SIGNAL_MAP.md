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

---

## 全体像：4本の配列×8スロット 早見表

**Stormworksの `setNumber(1..8)`/`getNumber(1..8)` に相当する4本の配列**
（`stateless_in`・`state_in`／`state_out`・`stateless_out`）に何が入って
いるかを、細部を読まずに把握するための一覧。ビット単位の内訳・由来・
実装上の経緯は後続の各節を参照。

### `stateless_in[1..8]`（現在tickのセンサ相当・都度計算に使う入力）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | `speed`（m/s） | 生double |
| 2 | `catenary_voltage_sw`（V） | 生double |
| 3 | `sap_raw` | 生double |
| 4 | notch/EBの5bool＋ノッチ位置3bit | パック済み `INPUT_BITS_LAYOUT` |
| 5 | `"BP [atm]"`（`SAP_ECB_IS_SAP`時のみ使用） | 生double |
| 6 | `"SAP [atm]"`（`SAP_ECB_IS_SAP`時のみ使用） | 生double |
| 7 | 予備（常に0） | ─ |
| 8 | 予備（常に0） | ─ |

### `state_in[1..8]` ／ `state_out[1..8]`（tickをまたいで持ち越す状態。8本中7本使用、1本予備）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | カム段＋3個のSRラッチ＋2個の周期カウンタ | パック済み `STATE_LATCHES_LAYOUT` |
| 2 | `regen_delay`レベル＋3個のデバウンスカウンタ | パック済み `STATE_TIMERS_LAYOUT` |
| 3 | `OLD_I`（前tickの電機子電流） | 準ステート・生double |
| 4 | `OLD_IF_A`（前tickの界磁電流） | 準ステート・生double |
| 5 | `OLD_PHI`（前tickの磁束） | 準ステート・生double |
| 6 | `regen_bc_smooth`（回生BC平滑値） | 準ステート・生double |
| 7 | `bc_target_smooth`（BC目標平滑値） | 準ステート・生double |
| 8 | 予備（常に0） | ─ |

### `stateless_out[1..8]`（現在tickの出力）

| slot | 内容 | 種別 |
|---|---|---|
| 1 | `motor_current` | 生double |
| 2 | `W` | 生double |
| 3 | `bc_target_smooth`（平滑化後） | 生double |
| 4 | `bcT` | 生double |
| 5 | カム/フェーズ状態など8bool | パック済み `STATUS_BITS_LAYOUT` |
| 6 | 予備（常に0） | ─ |
| 7 | 予備（常に0） | ─ |
| 8 | 予備（常に0） | ─ |

---

## 分類(a) — 真のラッチ状態・タイマー → パック済みステートビットフィールドへ

| 信号 | sw-net上の由来 | SPEC節 |
|---|---|---|
| `position_counter`（0-20） | `FUNC_NUM_3 position_counter`、`(x+y)%21` の自己ループ | §3.2 |
| `phase1_latch` | `SR_LATCH traction_phase1_latch` | §3.6 |
| `phase2_latch` | `SR_LATCH traction_phase2_latch` | §3.6 |
| `regen_latch` | `SR_LATCH regen_latch` | §3.6 |
| `traction_phase1_cap`／`traction_phase2_cap`／`current_below_limit_cap` | `CAPACITOR(0.1, 0)` ×3 | §3.6／§3.7 |
| `regen_delay_cap` | `CAPACITOR(0.5, 10)` | §3.8 |
| `traction_blinker`+`position_tick_pulse`（0.1/0.1） | `BLINKER`+`PULSE(rise)` | §3.2 |
| `regen_warning_blinker`+`regen_warning_pulse`（0.1/0.4） | `BLINKER`+`PULSE(rise)` | §3.6 |

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
- **パンタグラフ4ラッチ**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`、SPEC §3.9）─ 当初はビット数が
  小さいという理由でこのモジュールに含めていたが、ユーザーの判断により
  ゲート側に残すことにした。以降は「ゲートに残すもの」節を参照。

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

`regen_delay_cap`（分類(a)の`regen_delay_level`）はここには**含まれない**
─ 平滑化用の自己参照ではなく、単純な充放電タイマーなのでパック済み整数
フィールドに収めている（詳細は下記のステートスロットのレイアウト参照）。

## 分類(c) — ステートレス（毎tick再計算）

`notch_eff`、`notch_ge1..4`、`direction`、`eb_condition`（実機の値である
`direction == 0` のみを用いる ─ SPEC §4.2。storm-mclのシリアライズ不具合と
される sw-net 字面上の `(0,1)` のしきい値は再現しない）、`power_with_regen`、
`coasting_cond`／`neutral_cond`／`phase_reset_cond`、`current_below_limit`
（デバウンス前）、`regen_available`、`brake_below_min`、`overspeed`、
`regen_bc_target`、`ecb_sap_pressure`、`current_limit_sw`、
`traction_any_active`（周期パルス反映前）。

## ステートスロットのレイアウト

### `state_in[1]`／`state_out[1]` — `STATE_LATCHES_LAYOUT`（32bit中17bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `position_counter` | 5 | 0-20（0-31まで表現可） |
| 2 | `phase1_latch` | 1 | bool |
| 3 | `phase2_latch` | 1 | bool |
| 4 | `regen_latch` | 1 | bool |
| 5 | `traction_advance_counter` | 4 | 0-12（`periodic_pulse_step`の経過tick） |
| 6 | `regen_warning_counter` | 5 | 0-30（`periodic_pulse_step`の経過tick） |

15bit予備（17-31）。

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

### `state_in[2]`／`state_out[2]` — `STATE_TIMERS_LAYOUT`（32bit中19bit使用）

| 順序 | フィールド | bit数 | 範囲 |
|---|---|---|---|
| 1 | `regen_delay_level` | 10 | 0-600（`CAPACITOR(0.5, 10)`相当。詳細下記） |
| 2 | `phase1_cap_counter` | 3 | 0-6 |
| 3 | `phase2_cap_counter` | 3 | 0-6 |
| 4 | `current_below_limit_cap_counter` | 3 | 0-6 |

13bit予備（19-31）。

**`regen_delay_level` の設計**：`regen_delay_cap`（0.5秒充電/10秒放電）は
0-600のスケール済み整数として表現している。600（=10秒相当のtick数）を
「満充電」とし、放電は -1/tickで正確に600 tick（10秒）かけて0へ、
充電は同じ0-600の幅を30 tick（0.5秒）で埋める必要があるため
600/30=+20/tickとする。両方とも整数の割り算で厳密に割り切れるため、
浮動小数点誤差が一切生じない（「充電完了」判定は単純な `>= 600`）。

一度は「生の秒数（0〜0.5）」を生doubleスロットに持たせる設計も試したが、
`1/60`を30回加算しても浮動小数点誤差で厳密に`0.5`にならず
（`0.49999999999999994`止まり）、イプシロン許容判定が必要になった上、
ステートスロットを1本余分に消費する（8本中8本使用・予備0本になる）
欠点があったため、現在の整数スケール方式に戻した。詳細は
`src/chuso1800_core.lua` の `REGEN_DELAY_*` 定数群・`regen_delay_step`/
`regen_delay_charged` のコメントを参照。

### `state_in[3..7]`／`state_out[3..7]` — 生double（準ステート、分類(b)参照）

| slot | フィールド |
|---|---|
| 3 | `OLD_I` |
| 4 | `OLD_IF_A` |
| 5 | `OLD_PHI` |
| 6 | `regen_bc_smooth` |
| 7 | `bc_target_smooth` |

### `state_in[8]`／`state_out[8]` — 予備（現状は常に0）

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
| 4 | `INPUT_BITS_LAYOUT` のパック済みビットフィールド（32bit中8bit、下記参照） | Simple IF／Controller Stop |
| 5 | `"BP [atm]"`（`SAP_ECB_IS_SAP`が真の間だけ使用） | BPセンサポート |
| 6 | `"SAP [atm]"`（`SAP_ECB_IS_SAP`が真の間だけ使用） | SAPセンサポート |
| 7-8 | 予備（0） | |

### `INPUT_BITS_LAYOUT`（8bit）

パンタグラフ関連の6bool（Extended IF由来）はゲート側に残したため、この
モジュールへは配線していない（下記「ゲートに残すもの」参照）。

| 順序 | フィールド | bit数 | 由来 |
|---|---|---|---|
| 1 | `notch_pos` | 3 | Simple IF ch2（数値、パック時に0-7へクランプ） |
| 2 | `controller_stop` | 1 | トップレベル `Controller Stop` ポート |
| 3 | `regen_flag` | 1 | Simple IF ch18 bool |
| 4 | `forward_signal` | 1 | Simple IF ch16 bool |
| 5 | `backward_signal` | 1 | Simple IF ch17 bool |
| 6 | `eb_signal` | 1 | Simple IF ch1 bool |

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
| 5 | `STATUS_BITS_LAYOUT` のパック済みビットフィールド（32bit中8bit、下記参照） | RSS／Momelink側のゲート |
| 6-8 | 予備（0） | |

### `STATUS_BITS_LAYOUT`（8bit）

パンタグラフの状態ビット（`panta1_1800_active`等）はパンタグラフラッチ
そのものがゲート側に残ったため、このモジュールからは出力しない
（下記「ゲートに残すもの」参照 ─ 架線電圧セレクタ・RSSは引き続き
ゲート側で計算された `panta*_1800_active`/`panta*_1800_latched` を直接読む）。

| 順序 | フィールド | bit数 | 現状ゲート側で消費されているか |
|---|---|---|---|
| 1 | `cam_pulse` | 1 | される ─ 出力ポート `cam` に直結 |
| 2 | `phase1_latch` | 1 | されない ─ 予備／デバッグ用 |
| 3 | `phase2_latch` | 1 | されない ─ 予備／デバッグ用 |
| 4 | `regen_latch` | 1 | されない ─ 予備／デバッグ用 |
| 5 | `notch_ge1` | 1 | されない ─ 予備／デバッグ用 |
| 6 | `low_bc_with_regen_flag` | 1 | されない ─ 予備／デバッグ用 |
| 7 | `regen_warning_cond` | 1 | されない ─ 予備／デバッグ用 |
| 8 | `power_cut` | 1 | 常時0固定 ─ README.md「簡略化した点」参照 |

## ゲートに残すもの（今回は未Lua化）

- **パンタグラフ4ラッチ一式**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`とその周辺 ─ `panta1_set_cond`／
  `panta2_set_cond`／`is_1800_type`／`panta1_1800_active`等、SPEC §3.9）。
  以前はこのモジュールに含めていたが、ユーザーの判断によりゲート側へ戻した。
  このモジュールはExtended IFのパンタ関連signal・`property.getBool("M
  type")`のいずれも参照しない。
- 架線電圧セレクタ一式（`catenary_active_thresh` … `catenary_voltage_sw`）
  ─ **パンタグラフがゲートに戻ったため**、`panta1_1800_active`／
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
