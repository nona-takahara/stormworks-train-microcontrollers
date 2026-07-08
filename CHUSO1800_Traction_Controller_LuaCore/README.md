# CHUSO1800 Lua Core（プロトタイプ）

`CHUSO1800_Traction_Controller` の制御ロジックの大半（main.sw-net の
phase1/phase2/regen 状態機械、カム進段・ホーミング、ノッチ処理、力行カット条件
（eb_condition）、BC/回生BC平滑化）と、既存の電流物理演算
（`scripts/n409.lua`）を1つのモジュールに統合し、厳格な純関数契約のもとで
Lua に移植したスタンドアロンのプロトタイプです（パンタグラフラッチは
ユーザーの判断によりゲート側に残しています。「今回ゲート側に残したもの」
節を参照）。

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
`advance_cam`／`smooth_bc` 等）に分割し、
`calculateTick` はそれらを順に呼び出して結果を橋渡しするだけの
オーケストレータにしている。観測される挙動・タイミングはこの分割によって
変わらない（純粋なリファクタリング）。

## 今回ゲート側に残したもの（未Lua化）

- **パンタグラフ4ラッチ**（`panta1_latch`／`panta2_latch`／
  `panta1_en_latch`／`panta2_en_latch`とその周辺）。当初はビット数が小さい
  という理由で本モジュールに含めていたが、ユーザーの判断によりゲート側へ
  戻した。本モジュールはExtended IFのパンタ関連信号も
  `property.getBool("M type")` も一切参照しない。
- 架線電圧セレクタ一式（パンタグラフがゲートに戻ったため、
  `panta1_1800_active`/`panta2_1800_active` はゲート側で計算されたものを
  そのまま読む。本モジュールの出力には依存しない）
- Momelink-A のコンポジット整形（1800/1900フレーム選択）
- Rolling Stock Status のコンポジット整形（パンタ関連ビットもゲート側計算の
  ものをそのまま使う）
- `bc_target_read`（編成内Momelinkパススルー。今回の移行とは無関係）

パンタグラフ以外は純粋なデータ整形・muxが中心で、それ自体はラッチ状態を
持たないため、Lua化しても得るものが少ない箇所。該当ノードの一覧は
`SIGNAL_MAP.md` の「ゲートに残すもの」節を参照。

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
   単純な0-6カウンタ、`regen_delay`（0.5秒/10秒ペア）は0-600のスケール済み
   整数として+20/tick（enable時）・-1/tick（disable時）で表現。）これは
   SPEC.md §0.1自体のCAPACITORの説明に基づくものだが、Stormworks実機の
   内部実装そのものと突き合わせたわけではない。この前提が耐えるべき境界値
   テストは `test/scenarios/regen_delay_cap_timing.lua` を参照。

   `regen_delay`は一度「生の秒数（0〜0.5）」を生doubleスロットで持つ設計も
   試したが、`1/60`を30回加算しても浮動小数点誤差で厳密に`0.5`にならず
   （`0.49999999999999994`止まり）、判定にイプシロン許容が必要になった上、
   ステートスロットを1本余分に消費する欠点があったため、整数スケール方式に
   戻した。詳細は `SIGNAL_MAP.md` の「`regen_delay_level` の設計」節を参照。

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

当初案では過速度しきい値・力行電流リミットをLuaのソース定数として
ハードコードしていたが、Stormworksの `property.getNumber(name)` は8＋8本の
コンポジットスロット予算とは無関係に呼び出せるため、これらは**spawn時に
1回だけ読み込むライブプロパティ**として扱うよう変更した：

- `OVERSPEED_THRESHOLD` ← `property.getNumber("Over Speed Th. [m/s]")`
- `POWER_LIMIT_CURRENT` ← `property.getNumber("Power Limit Current [A]")`

プロパティ名はすべて main.sw-net 上の対応する `PROPERTY_NUMBER` ノードの
`n=` 属性とそのまま一致させてある。将来 `main.sw-net` へ実配線する際、
これらのノード自体は削除せず残す想定（後述の「今後の実配線について」参照）
なので、Lua側とゲート側とで真実源が二重化することはない ─ 同じ名前の
プロパティを両方から参照するだけになる。

（SAP/ECB切替・M-type（1800/1900）を表す `property.getBool` 呼び出しは
このモジュールには存在しない。SAP/ECB切替は下記「ステートレス入力の
簡素化」の通りゲート側で完結させ、M-typeはパンタグラフ関連ロジックごと
ゲート側に残したため。）

素の `lua` から動かすテスト環境（Stormworksの `property` グローバルが
存在しない）では、main.sw-net の各PROPERTY_NUMBERノードが持つデフォルト値
（`value=`属性）と同じ値にフォールバックする。詳細は
`src/chuso1800_core.lua` 冒頭の該当コメントを参照。

## ステートレス入力の簡素化（数値への置換）

当初案では `sap_raw`（数値）・`eb_signal`（bool）・`forward_signal`／
`backward_signal`（bool×2）をそのまま入力し、SAP/ECBの圧力換算や
directionの合成をこのモジュール内部で行っていた。しかし
`brake_pressure_sw`／`sap_pressure_sw`／`direction` はいずれも
main.sw-net に既存の同名ノードがすでに計算している最終値であり、ECB車に
ついても「SAP・BP換算値」をゲート側で計算してから渡せば、このモジュールは
SAP/ECBのどちらの車両かを一切知らなくてよくなる。そこで：

- `brake_pressure_sw`／`sap_pressure_sw` を生doubleとしてそのまま受け取る
  よう変更した（ゲート側でSAPセンサ直結／ECBオフセット換算のどちらであっても
  最終値まで解決してから渡す）。これにより `sap_raw`／`eb_signal`／
  `SAP_ECB_IS_SAP`プロパティの読み込みが不要になった。
- `forward_signal`／`backward_signal` の2boolも、ゲート側で`direction`
  （-1/0/+1）まで合成してから1本の生doubleとして渡すよう変更した。

残った `notch_pos`／`controller_stop`／`regen_flag` も、当初は
`INPUT_BITS_LAYOUT`（5bit）にビットパックしていたが、これも見直した。
`notch_pos` はSimple IFから生doubleとして届く数値であり、
`controller_stop`／`regen_flag` も各1boolに過ぎない。空いていた予備
スロットがちょうど3本だったため、3フィールドを1スロットへパックしても
スロット数は節約できず、`pack_bits`/`unpack_bits`往復のコストと
可読性の低下だけが残る。そこで `INPUT_BITS_LAYOUT` を廃止し、3フィールド
それぞれに生doubleスロットを割り当てた。結果、ステートレス入力に残る
パック済みフィールドはゼロになった（パックが残るのはステートの2スロット
と出力の`STATUS_BITS_LAYOUT`のみ）。詳細は `SIGNAL_MAP.md` の
「ステートレス入力スロットのレイアウト」を参照。

## スロット予算（詳細な内訳はSIGNAL_MAP.mdのビット表を参照）

- ステート：17bit（パック済みラッチ・周期カウンタ）＋19bit（パック済み
  `regen_delay_level`＋3個のデバウンスカウンタ）＋生double5本
  （`OLD_I`/`OLD_IF_A`/`OLD_PHI`/`regen_bc_smooth`/`bc_target_smooth`）＝
  8本中7本を使用、1本予備。
- ステートレス入力：8本すべてを生doubleとして使用（`speed`/
  `catenary_voltage_sw`/`brake_pressure_sw`/`sap_pressure_sw`/`direction`/
  `notch_pos`/`controller_stop`/`regen_flag`）、予備なし。ビットパックは
  使用していない。
- ステートレス出力：8本中5本を使用、3本予備。

いずれも、当初懸念していた「8本の枠に収まらない場合は相談」に該当する
ケースはなかった。状態機械と物理演算を統合したことで、外部からの消費者が
実質いなくなったチャンネル（逆起電力・カム段echo・界磁電流）が消えた分、
各カテゴリで想定より余裕ができている。

## テスト方法

Stormworks実機は不要、素のLuaだけで動く：

```sh
lua test/run_all.lua
```

12本のシナリオ（`test/scenarios/*.lua`）があり、**未変更の**
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
2. `catenary_voltage_sw`／`brake_pressure_sw`／`sap_pressure_sw`／
   `direction` を新しいLuaノードへの正式な入力として配線する（いずれも
   既存の main.sw-net ノードの出力をそのまま使えるが、現状はLua側の
   入力としては未配線）。`brake_pressure_sw`/`sap_pressure_sw`の解決に
   使う `sap_ecb_toggle`／`ecb_pressure_sw`／`ecb_sap_pressure`と、
   `direction`合成に使う`forward_flag_sw`／`backward_flag_sw`は、
   このモジュールへの入力を作るゲートとして残す（削除対象ではない）。
3. 置き換え済みとなるゲート網を削除する（2で残すと明記したもの以外）：
   phase1/phase2/regenのSRラッチとその set/reset ロジック、
   `position_counter`／ブリンカ／パルス／デバウンスCAPACITOR、
   `notch_eff`/`notch_ge*`、`eb_condition`、`current_src_mux`/
   `regen_current_write`、`regen_bc_smooth`/`bc_target_smooth`。
   **パンタグラフラッチ4個は削除対象ではない**（ゲート側に残す設計に
   変更したため）。
4. 残すゲート（パンタグラフラッチ・架線電圧セレクタ・Momelink整形・
   Rolling Stock Status）を、従来読んでいたコンポジットチャンネル／bool
   （パンタグラフ以外は新モジュールのステータスビットフィールド出力）を
   読むよう配線し直す。パンタグラフ自体は今回一切変更していないため、
   その配線は元のままでよい。
5. `overspeed_threshold`／`power_limit_current` の各 `PROPERTY_NUMBER`
   ノード自体は削除せずそのまま残す（本モジュールの `property.getNumber`
   呼び出しがこれらと同名のプロパティを読みに行くため、ノードを消すと
   プロパティの定義自体がなくなってしまう）。`sap_ecb_toggle`／
   `mtype_toggle`／`is_1800_type`／`notch_fb_ge1` など、今回Lua側へ
   吸収されなかった／されたゲートの扱いは上記2・3・4の通り。
