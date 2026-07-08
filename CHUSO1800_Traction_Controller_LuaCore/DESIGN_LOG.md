# 設計変更の経緯（意思決定ログ）— CHUSO1800 Lua Core

本ファイルは「なぜ現在の設計になったか」を記録する意思決定ログ。
**現在の姿**だけを知りたい場合は [`README.md`](./README.md)（概要・契約）と
[`SIGNAL_MAP.md`](./SIGNAL_MAP.md)（信号割付の一次情報源）を読めば足りる。
ここは、当初案・却下した代替案・変更のきっかけを残しておく場所であり、
同じ検討を将来繰り返さないためのもの。

各エントリの形式：**当初案 → 現在の設計 / 変更のきっかけ / 理由 / 影響箇所**。
番号は README.md からの参照（`DESIGN_LOG.md #n`）に使う。

---

## #1 `src/bitpack.lua` の分離をやめ、単一ファイルに統合

- **当初案**：ビットパック補助関数（`pack_bits`/`unpack_bits`）を別ファイル
  `src/bitpack.lua` に切り出し、`require("bitpack")` で読み込む構成。
- **現在の設計**：`src/chuso1800_core.lua` 単体で完結（`require` なし）。
- **理由**：Stormworksのlua環境にはモジュール読み込み機構（`require`）が
  存在しない。別ファイル構成はテスト環境では動くが**実機では動かない**。
  実機のLUAノードへそのまま貼り付けられる形を最優先した。
- **影響箇所**：`src/chuso1800_core.lua` 冒頭コメント、README「契約」節。

## #2 パンタグラフ4ラッチをLua化対象から外し、ゲート側に残す

- **当初案**：`panta1_latch`／`panta2_latch`／`panta1_en_latch`／
  `panta2_en_latch`（SPEC §3.9）は必要ビット数が小さいため、本モジュールに
  含めていた。
- **現在の設計**：4ラッチとその周辺（`panta*_set_cond`／`is_1800_type`／
  `panta*_1800_active` 等）はすべてゲート側に残す。本モジュールは
  Extended IFのパンタ関連信号も `property.getBool("M type")` も参照しない。
- **変更のきっかけ**：ユーザーの判断（レビュー時の指示）。
- **波及した変更**：
  - 架線電圧セレクタは `panta1_1800_active`/`panta2_1800_active` をゲート側
    計算値のまま読む（本モジュールの出力に依存しない）。
  - Rolling Stock Statusのパンタ関連ビットもゲート側計算値をそのまま使う。
  - `STATUS_BITS_LAYOUT` からパンタ状態ビットが不要になった。
  - M-type（1800/1900）判別が不要になり、`property.getBool` の呼び出しが
    モジュールからゼロになった。
  - 実配線時の削除対象リストからパンタグラフラッチ4個を除外
    （README「今後の実配線について」3項）。
- **影響箇所**：README「スコープ」節、`SIGNAL_MAP.md`「ゲートに残すもの」節。

## #3 過速度しきい値・力行電流リミットをハードコード定数からライブプロパティへ

- **当初案**：`OVERSPEED_THRESHOLD`／`POWER_LIMIT_CURRENT` をLuaソース内の
  定数としてハードコード。
- **現在の設計**：spawn時に1回だけ `property.getNumber(...)` で読み込む。
  プロパティ名は main.sw-net の対応する `PROPERTY_NUMBER` ノードの `n=`
  属性と完全一致。
- **理由**：`property.getNumber` は8＋8本のコンポジットスロット予算とは
  無関係に呼べる（入力スロットを消費しない）ため、車両ごとの調整可能性を
  タダで維持できる。実配線時も `PROPERTY_NUMBER` ノード自体を残す想定
  なので、Lua側とゲート側で真実源が二重化することもない ─ 同名プロパティを
  両方から参照するだけになる。
- **影響箇所**：README「チューニング可能なプロパティ」節、
  `src/chuso1800_core.lua` のproperty読み込みブロック。

## #4 ステートレス入力を「生センサ値」から「ゲート側で解決済みの最終値」へ

- **当初案**：`sap_raw`（数値）・`eb_signal`（bool）・`forward_signal`／
  `backward_signal`（bool×2）を入力し、`SAP_ECB_IS_SAP` プロパティで分岐
  しつつSAP/ECBの圧力換算やdirection合成を**モジュール内部で**行う。
- **現在の設計**：`brake_pressure_sw`／`sap_pressure_sw`／`direction` を
  ゲート側で最終値まで解決してから生doubleで受け取る。
- **変更のきっかけ**：ユーザーの提案。
- **理由**：これらはいずれも main.sw-net に既存の同名ノードがすでに計算
  している最終値。ECB車についても「SAP・BP換算値」をゲート側で計算してから
  渡せば、本モジュールはSAP/ECBのどちらの車両かを**一切知らなくてよくなる**。
  結果として `sap_raw`／`eb_signal`／`SAP_ECB_IS_SAP` プロパティの読み込みが
  不要になった。
- **影響箇所**：README「入力の前提」節、`SIGNAL_MAP.md`「ステートレス入力
  スロットのレイアウト」節、`decode_inputs` のコメント。

## #5 `INPUT_BITS_LAYOUT`（入力側ビットパック）の廃止

- **当初案**：`notch_pos`／`controller_stop`／`regen_flag` の3フィールドを
  5bitの `INPUT_BITS_LAYOUT` として1スロットにビットパック。
- **現在の設計**：3フィールドそれぞれに生doubleスロット（6-8）を割り当て。
  ステートレス入力に残るパック済みフィールドはゼロ（パックが残るのは
  ステート2スロットと出力の `STATUS_BITS_LAYOUT` のみ）。
- **変更のきっかけ**：ユーザーの指摘。
- **理由**：`notch_pos` はSimple IFから生doubleで届く数値、残り2つも各1bool。
  空いていた予備スロットがちょうど3本だったため、パックしてもスロットは
  1本も節約できず、`pack_bits`/`unpack_bits` 往復のコストと可読性の低下
  だけが残っていた（3フィールドに3予備スロット＝そもそも余っていた）。
  副作用として、ステートレス入力は8本すべて使用・予備0本になった。
- **影響箇所**：`SIGNAL_MAP.md`「ステートレス入力スロットのレイアウト」節。

## #6 `regen_delay` の表現：生の秒数double案を却下し、0-600整数スケールへ

- **試した案**：`regen_delay`（CAPACITOR 0.5秒充電/10秒放電）の水位を
  「生の秒数（0〜0.5）」として生doubleスロット1本に持たせる。
- **現在の設計**：0-600のスケール済み整数（充電+20/tick、放電-1/tick）を
  `STATE_TIMERS_LAYOUT` の10bitフィールドに収める。「充電完了」判定は
  単純な `>= 600`。
- **却下の理由**（2点）：
  1. `1/60` を30回加算しても浮動小数点誤差で厳密に `0.5` にならない
     （`0.49999999999999994` 止まり）。判定にイプシロン許容が必要になる。
     整数スケールなら +20/-1 とも厳密に割り切れ、誤差が一切生じない。
  2. 生doubleスロットを1本余分に消費し、ステートが8本中8本使用・予備0本に
     なってしまう。
- **影響箇所**：`SIGNAL_MAP.md`「`regen_delay_level` の設計」節、
  `src/chuso1800_core.lua` の `REGEN_DELAY_*` 定数群と
  `regen_delay_step`/`regen_delay_charged` のコメント。
  境界値テスト：`test/scenarios/regen_delay_cap_timing.lua`。

## #7 BLINKER+PULSE(rise) ペアを `periodic_pulse_step` に置換（挙動差を許容）

- **素朴な移植案**：main.sw-net の `BLINKER`+`PULSE(rise)` ペアを1:1で
  持ち込むと、ブリンカの位相ビット（ON/OFF）＋カウンタ＋エッジ検出用の
  「前回出力」ビットが必要になり、かつ「有効化から最初のパルスまでの遅延」
  が非対称な on_time/off_time に依存して分かりにくい。
- **現在の設計**：単一の経過tickカウンタ `periodic_pulse_step`
  （enable中+1、`period_ticks`=on+off相当に達したら0に戻しつつパルス1回発火、
  disableで即0リセット）。位相ビットも「前回出力」ビットも不要。
- **根拠**：本モジュールのどこもブリンカの生のON/OFF出力そのものを読んで
  おらず、そこから駆動される周期パルス（カム進段・界磁電流超過検知パルス）
  だけが意味を持つ。
- **許容した挙動差**：最初のパルスが有効化から `period_ticks` 後に来る
  （元設計は最短で `off_ticks` 後）。定常状態の周期は同一。
- **影響箇所**：README「意図的な簡略化」3項、`SIGNAL_MAP.md` の
  `STATE_LATCHES_LAYOUT` 節、`src/chuso1800_core.lua` の
  `periodic_pulse_step` コメント。

## #8 スロット予算：当初の「8本に収まらないかもしれない」懸念は解消

- **当初の懸念**：状態・入力・出力それぞれ8本の枠に収まらない場合は設計を
  相談する、という前提で着手した。
- **結果**：どのカテゴリも枠内に収まった（ステート7/8、入力8/8、出力5/8）。
  状態機械と物理演算を1モジュールに統合したことで、外部からの消費者が
  実質いなくなったチャンネル（逆起電力・カム段echo・界磁電流）が消えた分、
  想定より余裕ができた。`current_src_mux` のch2/ch5/ch6に消費者が残って
  いないことは、`current_src_mux_out`／`traction_status_bool_out` に対する
  `COMPOSITE_READ_*` の総ざらいで確認済み（`SIGNAL_MAP.md`「ステートレス
  出力スロットのレイアウト」節）。
- **影響箇所**：README「スロット予算（概要）」節、`SIGNAL_MAP.md` の早見表。

## #9 `power_cut_latch`/`startup_delay`/`motor_current_oor` 系の削除（死コードの証明）

- **判断**：これらを移植対象から丸ごと外し、`power_cut` は常時 `false` の
  定数ステータスビットとしてのみ残す。
- **証明の要点**：`startup_delay` の `enable` は main.sw-net 上未配線かつ
  `discharge_time=0` のため出力は恒常 `false`。`motor_current_oor` の
  しきい値 `±200000A` はNewton法の実電流レンジ（数百A）から到達不能。
  よって下流のリセット優先ラッチの `q` は実行中ずっと `false` ─
  これは挙動変更ではなく**死コードの証明**（SPEC §4.4 も同旨）。
- **定数ビットとして残した理由**：ゲート側のRSSビットとの整合を取りやすく
  するため。
- **保証**：`test/scenarios/power_cut_dead_logic_constant.lua`。
- **影響箇所**：README「意図的な簡略化」1項、`STATUS_BITS_LAYOUT` の
  `power_cut` フィールド。

## #10 `regen_warning_*` を `field_current_excess_*` へ改名（誤命名の修正）

- **当初案**：main.sw-net由来の `regen_warning_cond`/`regen_warning_blinker`/
  `regen_warning_pulse` という名前をそのまま踏襲していた。
- **現在の設計**：`field_current_excess_cond`/`field_current_excess_blinker`/
  `field_current_excess_pulse`（関数名 `regen_warning_block` も
  `field_current_excess_block` へ、定数 `REGEN_WARNING_PERIOD_TICKS` も
  `FIELD_CURRENT_EXCESS_PERIOD_TICKS` へ、状態フィールド
  `regen_warning_counter` も `field_current_excess_counter` へ改名）。
- **変更のきっかけ**：ユーザーが別セッションでのClaudeとの分析結果を
  共有。main.sw-netの`brake_current_fb`（channel=6読み込み）は実際には
  `n409.lua`の`output.setNumber(6, iF_a)`＝**界磁電流**を読んでいるだけで
  「ブレーキ電流」ではなく、`regen_warning_cond = (iF_a > 300or400A) ∧
  (notch_eff==0)`という条件も「回生ブレーキの警告」ではないと判明した。
- **理由**：実態は「ノッチオフ後も界磁電流iF_aが閾値を超えたまま残っている
  過渡状態を検知し、電流の自然減衰（`coasting_cond`）を待たずに直列/並列
  制御ラッチを強制的に畳んで空回しへ戻す」保護的フォールバックであり、
  回生ブレーキとは無関係。誤解を招く名前を放置すると再び同じ誤読が起きる
  ため、`CHUSO1800_Traction_Controller/main.sw-net`・`SPEC.md`（source of
  truth側、commit 571e10eと同じ方式で直接編集）とあわせて改名した。
- **意図的にスコープ外とした部分**：`brake_current_fb`／
  `brake_limit_300_b`／`brake_limit_300_const`／`brake_limit_400`／
  `brake_limit_sw`／`brake_current_above_300`／`brake_current_high`／
  `brake_current_high_phase1` は同根の誤解に基づく命名だが、ユーザーの
  判断により**今回は改名対象から除外**（変更範囲を最小化するため）。
  本モジュールの `field_current_excess_block` 内でもこれらの名前は
  `brake_limit_sw`/`brake_current_above_300` のまま残っている
  （main.sw-net側と対応を取るため意図的に不揃いのまま）。
- **影響箇所**：`CHUSO1800_Traction_Controller/main.sw-net`・`SPEC.md`
  （§3.6「命名注意」・命名誤りテーブルに追記）、
  `src/chuso1800_core.lua`（`field_current_excess_block`とその内部・
  `STATE_LATCHES_LAYOUT`/`STATUS_BITS_LAYOUT`のフィールド名）、
  `SIGNAL_MAP.md`・README.md 内の「回生警告」表記。
