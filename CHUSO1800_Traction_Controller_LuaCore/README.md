# CHUSO1800 Lua Core（プロトタイプ）

`CHUSO1800_Traction_Controller` の制御ロジックの大半（main.sw-net の
phase1/phase2/regen 状態機械、カム進段・ホーミング、ノッチ処理、力行カット条件
（eb_condition）、BC/回生BC平滑化、パンタグラフラッチ）と、既存の電流物理演算
（`scripts/n409.lua`）を1つのモジュールに統合し、厳格な純関数契約のもとで
Lua に移植したスタンドアロンのプロトタイプです。

**`CHUSO1800_Traction_Controller/` 配下のファイルは一切変更していません。**
本ディレクトリはあくまで設計・検証用のプロトタイプであり、`main.sw-net` への
実配線はまだ行っていません（詳細は本ファイル末尾の「今後の実配線について」を参照）。

全信号の由来と、スロット/ビットへの割付の詳細は
[`SIGNAL_MAP.md`](./SIGNAL_MAP.md) を参照してください。

## 契約（インターフェース）

```lua
local core = require("chuso1800_core")
local stateless_out, state_out = core.calculateTick(stateless_in, state_in)
```

- `stateless_in`・`stateless_out`：Lua数値の配列 `[1..8]`。現在tickのセンサ値相当の入力／現在tickの出力。
- `state_in`・`state_out`：Lua数値の配列 `[1..8]`。`state_out` はそのまま次tickの
  `state_in` として自己ループで戻ってくる。
- 制御状態の保持にLuaの永続グローバル変数は一切使用していない。tickをまたいで
  持ち越す値はすべて `state_in`/`state_out` に収めており、そのおかげで
  Stormworksの `input`/`output` をモックすることなく、素の `lua` インタプリタから
  モジュール全体を呼び出し・テストできる（「テスト」節を参照）。
- 各スロットは生のdoubleか、`src/chuso1800_core.lua` に直接書かれている
  `pack_bits`/`unpack_bits`（`string.pack("I4",...)`/`string.unpack("I4",...)`
  を用いた実装）で生成・分解される整数のどちらか。後者を使うと複数のbool・
  小さい整数を1つの32bitスロットに同居させられる。**Stormworksにはモジュール
  読み込み機構（`require`）が存在しないため**、当初は別ファイル
  `src/bitpack.lua` を `require` する構成にしていたが、それは実機では動かない
  ─ 現在は `src/chuso1800_core.lua` 単体で完結しており、そのままStormworksの
  LUAノードに貼り付けられる。

## tickモデルについて

sw-net の字面通りのゲートネットモデル（SPEC.md §0.2）では、すべてのゲート出力が
厳密に1tick遅延するとされており、組合せ段がD段連なればD tickかけて伝搬する。
これを文字通り再現しようとすると、~150ノードのグラフ上のあらゆる中間信号ごとに
専用のステートスロットが必要になり、8本という枠に到底収まらない。

そこで本モジュールでは、真にtickをまたいで持ち越されるもの（SRラッチ、
デバウンス／タイマー用のCAPACITOR、ブリンカ、電流物理の準ステート、BC平滑化）
だけを「遅延あり」として扱う：今tickの判断には `state_in` の古い値を読み、
新しい値を `state_out` として書き出す。それ以外（ノッチ処理、力行カット条件、
方向判定、BC目標値の式など）はすべて純粋な組合せ論理として、1回の
`calculateTick` 呼び出し内で完結させている。

SPEC.md 自身も §0.2 の締めくくりで「実機の評価順序が一部同tick伝搬する場合、
過渡（H5/H7）のtick数は短縮されるが、定常状態の結論は不変」と、この種の
「同tick内での圧縮」を許容する注記を残している。具体例として
`test/scenarios/h7_cam_overshoot_homing.lua` では、SPEC.md のH7（カムの
オーバーシュート）がゲート段の追加遅延1tick分に依存する現象であり、本モジュールの
モデルでは再現しないことを、黙って見過ごすのではなく明示的に検証・記述している。

`src/chuso1800_core.lua` 自体の構成も、main.sw-net の各ゲート名を1対1で
同名のローカル変数へ機械的に置き換えただけの1枚の巨大な `calculateTick`
にはしていない。代わりに、SPEC.md の §3.x 各節にほぼ対応する小さな関数
（`eb_and_brake_pressure`／`notch_and_cam_feedback`／`brake_demand`／
`debounce_block`／`regen_warning_block`／`phase_state_machine`／
`advance_cam`／`smooth_bc`／`pantograph_block` 等）に分割し、
`calculateTick` はそれらを順に呼び出して結果を橋渡しするだけの
オーケストレータにしている。観測される挙動・タイミングはこの分割によって
変わらない（純粋なリファクタリング）。

## 今回ゲート側に残したもの（未Lua化）

純粋なデータ整形・muxが中心で、それ自体はラッチ状態を持たないため、Lua化しても
得るものが少ない箇所：

- 架線電圧セレクタ一式（本モジュールの `panta1_1800_active`/`panta2_1800_active`
  ステータスビットを読む形は変わらない）
- Momelink-A のコンポジット整形（1800/1900フレーム選択）
- Rolling Stock Status のコンポジット整形
- `bc_target_read`（編成内Momelinkパススルー。今回の移行とは無関係）

該当ノードの一覧は `SIGNAL_MAP.md` の「ゲートに残すもの」節を参照。

## 簡略化した点（黙って解決していない）

1. **`power_cut_latch`/`startup_delay`/`motor_current_oor` 系は丸ごと削除。**
   `startup_delay` の `enable` は main.sw-net 上未配線かつ `discharge_time=0`
   のため、出力は恒常的に `false`。`motor_current_oor` のしきい値
   `±200000A` はNewton法の実際の電流レンジ（数百A）から到達不能。よって
   下流のリセット優先ラッチの `q` は実行中ずっと `false` であることが証明できる
   ─ これは挙動変更ではなく死コードの証明である。`power_cut` は、ゲート側の
   RSSビットとの整合を取りやすいよう、常時 `false` の定数ステータスビットとして
   だけ残してある。`test/scenarios/power_cut_dead_logic_constant.lua` で保証。

2. **CAPACITORの充放電を線形アキュムレータとしてモデル化。**（enable中は
   charge_time秒で「充電完了」に達し、disable中はdischarge_time秒で0に戻る。
   デバウンス系（`phase1_cap`等）は「N tick連続でenableなら確定」という
   単純な0-6カウンタ、`regen_delay`（0.5秒/10秒ペア）は生の秒数として
   +1/60秒（enable時）・-1/1200秒（disable時）で表現。）これはSPEC.md
   §0.1自体のCAPACITORの説明に基づくものだが、Stormworks実機の内部実装
   そのものと突き合わせたわけではない。この前提が耐えるべき境界値テストは
   `test/scenarios/regen_delay_cap_timing.lua` を参照。

3. **BLINKER+PULSE(rise)のペアを、単一の経過tickカウンタ
   （`periodic_pulse_step`）に置き換えた。** 元のBLINKERはON/OFFを繰り返す
   出力そのものを持つが、本モジュールのどこもその生のON/OFF出力を読まず、
   そこから駆動される周期パルス（カム進段・回生警告パルス）だけが意味を
   持つ。そこで「enable中は経過tickを+1し、period_ticks
   （=on_time+off_time相当）に達したら0に戻しつつパルスを1回発火、
   disableなら即座に0にリセット」という単純な形に置き換えた。位相ビット
   （ON/OFF）も、エッジ検出用の「前回出力」ビットも不要になった。ただし
   挙動は変化する：最初のパルスが有効化から`period_ticks`後に来る
   （元設計は最短で`off_ticks`後）。詳細は `src/chuso1800_core.lua` の
   `periodic_pulse_step` のコメントを参照。

## ライブプロパティの利用（property.get\*）

当初案では SAP/ECB切替・M-type（1800/1900）・過速度しきい値・力行電流リミットを
すべてLuaのソース定数としてハードコードしていたが、Stormworksの
`property.getBool(name)`/`property.getNumber(name)` は8＋8本のコンポジット
スロット予算とは無関係に呼び出せるため、これらは**spawn時に1回だけ
読み込むライブプロパティ**として扱うよう変更した：

- `SAP_ECB_IS_SAP` ← `property.getBool("SAP or ECB")`
- `IS_1800_TYPE` ← `not property.getBool("M type")`
- `OVERSPEED_THRESHOLD` ← `property.getNumber("Over Speed Th. [m/s]")`
- `POWER_LIMIT_CURRENT` ← `property.getNumber("Power Limit Current [A]")`

プロパティ名はすべて main.sw-net 上の対応する `PROPERTY_TOGGLE`/
`PROPERTY_NUMBER` ノードの `n=` 属性とそのまま一致させてある。将来
`main.sw-net` へ実配線する際、これらのノード自体は削除せず残す想定（後述の
「今後の実配線について」参照）なので、Lua側とゲート側とで真実源が二重化する
ことはない ─ 同じ名前のプロパティを両方から参照するだけになる。

これに伴い、SAP/ECBの分岐も実際に生きるようにした：ECB固定だった頃は
ステートレス入力スロット5・6（`"BP [atm]"`/`"SAP [atm]"`）は配線されていても
未使用のままだったが、現在は `SAP_ECB_IS_SAP` が真のときに実際にこれらの値へ
切り替わる（main.sw-net の `brake_pressure_sw`/`sap_pressure_sw` の
NUM_SWITCHBOXをそのまま踏襲）。

素の `lua` から動かすテスト環境（Stormworksの `property` グローバルが
存在しない）では、main.sw-net の各PROPERTY_\*ノードが持つデフォルト値
（`PROPERTY_NUMBER` の `value=`、および `v=` 省略時オフとなる
`PROPERTY_TOGGLE`）と同じ値にフォールバックする。詳細は
`src/chuso1800_core.lua` 冒頭の該当コメントを参照。

## スロット予算（詳細な内訳はSIGNAL_MAP.mdのビット表を参照）

- ステート：21bit（パック済みラッチ・カウンタ）＋9bit（パック済みデバウンス）＋
  生double6本（`OLD_I`/`OLD_IF_A`/`OLD_PHI`/`regen_bc_smooth`/
  `bc_target_smooth`/`regen_delay_seconds`）＝ **8本中8本を使用、予備0本**。
  （`regen_delay_cap` を可読性のためスケール済み整数から生の秒数へ
  移した分、1本分の予備を使い切った。詳細はSIGNAL_MAP.mdの該当節参照）
- ステートレス入力：8本中4本を使用、4本予備（うち2本は `"BP [atm]"`/
  `"SAP [atm]"` に配線済みで、`SAP_ECB_IS_SAP` が真の間だけ実際に使われる）。
- ステートレス出力：8本中5本を使用、3本予備。

ステートレス入出力については、当初懸念していた「8本の枠に収まらない場合は
相談」に該当するケースはなかった。状態機械と物理演算を統合したことで、
外部からの消費者が実質いなくなったチャンネル（逆起電力・カム段echo・
界磁電流）が消えた分、想定より余裕ができている。ステートは
`regen_delay_seconds` の追加で予備を使い切ったが、8本の枠自体は超えて
いない。

## テスト方法

Stormworks実機は不要、素のLuaだけで動く：

```sh
lua test/run_all.lua
```

13本のシナリオ（`test/scenarios/*.lua`）があり、**未変更の**
`../CHUSO1800_Traction_Controller/scripts/n409.lua` に対する数値回帰
（小さな `input`/`output` シムを介して `loadfile` で直接読み込むため、
このファイルが変更されていないことの受動的な再確認にもなる）、SPEC.md
§3.6の状態遷移図の完全な走査、SPEC.md記載のコーナーケース（H4/H5/H6/H7）の
検証を含む。

## 今後の実配線について（本プロトタイプのスコープ外）

`main.sw-net` へ実際に組み込む場合、以下が必要になる（今回は着手していない）：

1. `LUA current_sim` ノードの `script_ref` を差し替える（あるいは置き換える）。
   本モジュールをStormworksの `onTick()` として再構成し、8＋8本のスロットを
   2組のComposite Read/Write（ステート用は自己ループ、ステートレス入出力用は
   実際のゲートと接続）でパック／アンパックする形にする。
2. 置き換え済みとなるゲート網を削除する：phase1/phase2/regenのSRラッチと
   その set/reset ロジック、`position_counter`／ブリンカ／パルス／
   デバウンスCAPACITOR、`notch_eff`/`notch_ge*`、`eb_condition`、
   `current_src_mux`/`regen_current_write`、`regen_bc_smooth`/
   `bc_target_smooth`、パンタグラフラッチ4個。
3. `catenary_voltage_sw` を新しいLuaノードへの正式な入力として配線する
   （現状は状態機械の入力からの下流専用になっている）。
4. 残すゲート（架線電圧セレクタ・Momelink整形・Rolling Stock Status）を、
   従来読んでいたコンポジットチャンネル／boolの代わりに、新モジュールの
   ステータスビットフィールド出力を読むよう配線し直す。
5. `sap_ecb_toggle`／`mtype_toggle`／`overspeed_threshold`／
   `power_limit_current` の各 `PROPERTY_*` ノード自体は削除せずそのまま
   残す（本モジュールの `property.getBool`/`property.getNumber` 呼び出しが
   これらと同名のプロパティを読みに行くため、ノードを消すとプロパティの
   定義自体がなくなってしまう）。`is_1800_type`／`notch_fb_ge1` など、
   今回Lua側へ吸収された派生ゲートのみ削除対象。
