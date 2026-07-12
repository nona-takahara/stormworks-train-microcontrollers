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

## #11 `lib/state_sync.lua`（汎用ステート同期ドライバ）との統合

- **背景**：ユーザーがリポジトリ共通ライブラリとして`lib/state_sync.lua`を
  masterに追加した（本モジュール専用ではなく、`calculateTick(stateless_in,
  state_in)`という同じ形の純関数を持つ任意のマイコンモジュールから使う
  想定）。composite チャンネルの自己ループ配線が実機で何tick遅延するか
  不確実な問題に対し、「2tick前に自分が出した state と、外部からの
  フィードバック値が一致するか」を毎tick確認し、不一致なら再計算して
  追いつくという設計で対処している。
- **発見したバグ**：`lib/state_sync.lua`の`onTick()`内、無条件に毎tick
  実行される行が`caluculateTick(i0, s1)`とタイポしていた（正しくは
  `calculateTick`）。存在しないグローバル関数呼び出しのため、そのまま
  では**毎tickエラーで即クラッシュ**する状態だった。1文字の綴り間違いと
  判断し、`lib/state_sync.lua`側で直接修正した（設計判断ではなく
  バグ修正）。
- **判明した契約の不一致**：`state_sync.lua`は自身の冒頭コメントで
  「state入出力はinteger前提」と明記している。`chuso1800_core.lua`の
  `state_in`/`state_out`はスロット1-2（`STATE_LATCHES_LAYOUT`/
  `STATE_TIMERS_LAYOUT`）こそ元から32bit整数だが、スロット3-7
  （`OLD_I`/`OLD_IF_A`/`OLD_PHI`/`regen_bc_smooth`/`bc_target_smooth`）は
  生のLua doubleであり、このままでは`state_sync.lua`が想定する形と
  一致しない。
- **現在の設計**：新規ディレクトリ`deploy/`に単一ファイル`deploy/main.lua`
  を追加。`state_sync.lua`が呼ぶ生グローバル関数
  `calculateTick(stateless_in, state_in)`を実装するブリッジで、スロット
  1-2は無変換で素通し、スロット3-7は`state_sync.lua`自身が定義する
  `f2i`/`i2f`（float32のビットパターンをuint32として運ぶ、
  `pack_bits`/`unpack_bits`と同じ`string.pack`/`string.unpack`の応用）で
  このスロット境界だけ変換する。`src/chuso1800_core.lua`自体はこの変換
  を一切知らず、内部では常にフル精度のdoubleで計算する（既存テスト
  スイートは無変更・無影響）。`../../lib/state_sync.lua`・
  `../src/chuso1800_core.lua`は`dofile(...)`で読み込む（`require`が無い
  Stormworks向けの実機フラット化は、開発者側のビルドツール
  `storm-lua-minify`が`dofile(...)`のリテラル文字列パスをその場に展開する
  形で行う想定のため、こちら側で独自のビルドスクリプトや生成済み
  成果物は持たない ─ 当初は`deploy/build.sh`で連結した単一ファイル
  `deploy/chuso1800_deploy.lua`を生成・コミットしていたが、
  ユーザー指摘「スクリプト生成はstorm-lua-minifyが実施するので埋め込みは
  dofileを使ってほしい。コード規模も無駄に大きい」を受けて撤回し、この
  形に置き換えた）。
- **理由**：float32への丸めは`f2i`/`i2f`を通るスロット境界で1回だけ発生する。
  これは新たに導入した損失ではなく、Stormworksのcomposite `number`
  チャンネル自体が元々float32精度である以上、実機配線すれば避けられない
  制約を明示化したにすぎない（idempotencyは開発中に手元のscratchスクリプト
  で確認済み：float32で正確に表現できる値は`f2i(i2f(x))`が完全往復し、
  そうでない値も相対誤差2e-7程度に収まる）。`chuso1800_core.lua`自体を
  「全スロット整数」制約に合わせて作り替える案（生doubleスロットを廃止する
  等）は採らなかった ─ 標準Luaでのテスト容易性という当初からの一次要件
  （README「契約」）を損なわずに済む、境界だけの変換の方が影響範囲が
  小さいため。
- **自動テストは設けていない**：`deploy/main.lua`の`dofile`が作業ディレクトリ
  相対のため、テストにはサブプロセスで`deploy/`を作業ディレクトリとして
  実行する必要があり、値の受け渡しにも数値の完全精度シリアライズが要る
  （実装・検証したが、後にユーザーから「テストの必然性も薄いプロジェクトな
  ので、無理にテストしない方がいい」との指摘を受け撤回した）。中身は
  i2f/f2iによるスロット境界変換という薄いグルーコードにとどまり、
  `calculateTick`本体のロジックは他の12シナリオで既にカバーされている
  ため、サブプロセス経由の自動テストを常設する労力には見合わないと判断。
- **影響箇所**：`lib/state_sync.lua`（タイポ修正のみ）、新規
  `deploy/main.lua`、README.md「デプロイ」節・「テスト」節・
  「今後の実配線について」1項。

## #12 実機フラット化をstorm-lua-minify（Node.js）へ委譲

- **当初案**：`deploy/build.sh`（bash）が`lib/state_sync.lua` +
  `src/chuso1800_core.lua`（`local core = (function() ... end)()`で
  ラップ） + `deploy/bridge.lua`を単純にテキスト連結し、
  `deploy/chuso1800_deploy.lua`を生成していた。
- **変更のきっかけ**：ユーザー「スクリプト生成は、私のプロジェクトである
  storm-lua-minifyが実施しますので、埋め込みはdofileを使ってください
  （その場に展開されます）。また、コード規模が無駄にでかいです。
  モジュール化せず、べた書きにしてください」。続けて「生成スクリプトは、
  私がWindowsで実行する都合上、Node.jsで書いていただけると助かります」
  「storm-lua-minifyはnpmで公開済みのツールです。そいつ自体のバグも
  多いのですが、いったんそのバグの多さは無視してください」。
- **現在の設計**：`deploy/build.js`（Node.js、`storm-lua-minify`パッケージ
  ─ `nona-takahara/storm-lua-minify`、npm公開済み ─ を呼び出す）が
  `deploy/main.lua`をエントリポイントとしてビルドし、
  `deploy/chuso1800_deploy.lua`（実機貼り付け用の最終成果物）を生成する。
- **実装中に発見した`storm-lua-minify`固有の制約・バグ**（ユーザーの
  「バグの多さは無視してください」指示を踏まえ、これらを回避する形で
  設計した。ライブラリ自体は変更していない）：
  1. `require`/`dofile`のモジュール名解決は、**エントリファイル自身の
     ディレクトリからの下り（descend-only）専用**で、`..`による親
     ディレクトリ参照に対応していない（`moduleName.replaceAll(".",
     path.sep)`という素朴な実装のため、`..`のドットもセパレータとして
     破壊的に置換されてしまう）。このため`deploy/main.lua`
     （`CHUSO1800_Traction_Controller_LuaCore/deploy/`配下）から
     `lib/state_sync.lua`（リポジトリルート直下、`deploy/`から見て2階層
     上）を直接参照することはできない。
     → `deploy/build.js`が`lib/state_sync.lua`と`src/chuso1800_core.lua`を
     ビルド直前に`deploy/`へ一時コピーし（`state_sync.lua`／
     `chuso1800_core.lua`という同名ファイルとして）、`main.lua`からは
     兄弟ファイルとして`require`できるようにし、ビルド後に削除する
     （ユーザー提案「libのライブラリを事前にNode.js側でコピーして、
     その後storm-lua-minifyにかけるとスマートかもしれませんね」）。
  2. `dofile(...)`をLuaの**式（expression）の位置**（例：
     `local core = dofile("chuso1800_core")`）で使うと、対象モジュールが
     複数文＋末尾`return`という構成の場合、IIFE（`(function() ... end)()`）
     で包まれずに文の並びがそのまま式の位置へ展開されてしまい、
     `local a=local a={}...`のような**構文エラーになる実バグ**を確認した
     （`-m`モードの有無に関わらず発生）。一方`require(...)`は`-m`モードでは
     常にIIFEで包まれた形で解決される（内部の`require`ディスパッチャ関数
     経由）ため、この問題が起きない。
     → `chuso1800_core.lua`（`return M`で終わる）は`require`で読み込み、
     `state_sync.lua`（returnなし、グローバル定義のみ）は当初`dofile`で
     読み込んでいたが、次項の理由で結局こちらも`require`に統一した。
  3. `-m`モードの`require`ディスパッチャは、**実際に`require`で参照された
     かdofileで参照されたかに関わらず、パースした全モジュールを
     ディスパッチャに含めてしまう**。`state_sync.lua`を`dofile`で
     読み込んでいた際、その内容がディスパッチャ内（未使用のまま）と
     直接展開箇所の**両方**に重複して出力され、無駄にサイズを消費して
     いた（実測で約600バイト）。
     → `state_sync.lua`も`require("state_sync")`に統一し、重複を解消した。
- **影響箇所**：`deploy/build.sh`・`deploy/bridge.lua`・生成物
  `deploy/chuso1800_deploy.lua`を削除し、新規`deploy/build.js`・
  `deploy/main.lua`（全面書き換え）に置換。ルート`package.json`に
  `storm-lua-minify`を追加。README.md「デプロイ」節。

## #13 Stormworksの8192文字制限に収めるためのサイズ最適化

- **背景**：#12の作業中に判明した実測値として、`src/chuso1800_core.lua`
  単体をstorm-lua-minifyで圧縮しただけで12,386文字あり、Stormworksの
  LUAノード1個あたり8192文字という制限を単体ですでに51%超過していた。
  `state_sync.lua`＋ブリッジを含めた完成品`deploy/chuso1800_deploy.lua`は
  当初14,126文字（65%超過）。
- **原因**：storm-lua-minifyはローカル変数・関数名などの識別子は短縮
  できるが、テーブルのキー文字列（`t.field_name`という形での参照）は
  短縮できない。`chuso1800_core.lua`は`calculateTick`内の9個のヘルパー
  関数（`decode_inputs`／`notch_and_cam_feedback`／`phase_state_machine`
  等）＋`M.physics_tick`／`M.decode_state`／`M.encode_state`等の状態
  (de)シリアライズ関数が、いずれも名前付きテーブルで値を受け渡す設計
  だったため、フィールド名の文字列（`position_counter`や
  `field_current_excess_counter`等、数十種）が圧縮後もそのまま残っていた。
  さらにビットレイアウトの汎用機構（`STATE_LATCHES_LAYOUT`等の
  `*_LAYOUT`テーブル＋`pack_bits`/`unpack_bits`）も、各フィールド名を
  レイアウトテーブル側に重複して保持していた。
- **現在の設計**（ユーザーの段階的な指摘・承認を経て実施。実測値の推移）：
  1. **ビットレイアウトの直書き化**（ユーザー「ビットレイアウターをカット
     して直書きに変えることで1000～2000文字程度は確実に削減できると
     考えます」→「単にビットレイアウターをカットするだけだと大変だと
     思うので、f2i, i2fを活用し、かつ特定ビットのみ読み書きする補助関数を
     追加するとよいです」→「get_bitsもいいのですが、get_bit（booleanを
     返す）を加えるともう少し圧縮特性が良くなると思います」）：
     `*_LAYOUT`テーブルと`pack_bits`/`unpack_bits`を廃止し、ビット位置
     （shift/width）を直接指定する`to_u32`/`get_bits`/`put_bits`/
     `get_bit`/`put_bit`に置き換えた（`get_bit`/`put_bit`は1bitフィールド
     専用の省略形）。14,126→12,037文字。
  2. **calculateTick内ヘルパー関数の全面位置引数化**（ユーザー「連想配列
     的なtableを使うと圧縮が効きにくいです...table渡しをやめると圧縮率が
     向上します」→スコープ確認の結果「全面的に位置引数化（推奨）」を
     選択）：9個のヘルパー関数すべてを名前付きテーブルではなく位置引数・
     多値返却に書き換えた。12,037→9,627文字。
  3. **`M.physics_tick`／`M.decode_state`／`M.encode_state`／
     `M.encode_stateless_in`／`M.decode_stateless_out`の位置引数化**
     （ユーザー「すべて位置引数化してください」）：これらの状態(de)
     シリアライズ関数・物理演算関数も同様に位置引数・多値返却化した。
     9,627→**7,873文字**（8192文字制限内に収まった）。
- **テスト側への影響**：上記3関数群は全12テストシナリオが直接呼んでいた
  公開APIだったため、`test/harness.lua`に名前付きテーブル⇔位置引数の
  変換ラッパー（`harness.encode_state`/`decode_state`/
  `encode_stateless_in`/`decode_stateless_out`/`physics_tick`）を新設し、
  全テストファイルの呼び出し箇所を`core.encode_state({...})`から
  `h.encode_state(core, {...})`のような形へ書き換えた。ラッパーは
  deployビルドに一切含まれないため、テストの可読性を保ったままコア
  モジュールのサイズには影響しない。
- **可読性とのトレードオフ**：位置引数化した各関数には、直前のコメントで
  引数・戻り値の順序を明示している（ユーザー「位置引数化にともなって
  returnの意味が分かりづらくなるので、returnの直上などに返却順序を
  わかりやすくするコメントを加えてください」）。`M.decode_state`/
  `M.encode_state`/`M.encode_stateless_in`/`M.decode_stateless_out`の
  シグネチャ自体は「公開API」としてこの文書・SIGNAL_MAP.md・
  test/harness.luaに記録されているので、実装を読まなくても呼び出し方が
  わかるようにしてある。
- **影響箇所**：`src/chuso1800_core.lua`全体（`*_LAYOUT`テーブル・
  `pack_bits`/`unpack_bits`の削除、9個のヘルパー関数＋5個の状態(de)
  シリアライズ・物理演算関数の位置引数化、`M.calculateTick`本体の書き換え）、
  `test/harness.lua`（名前付きテーブル変換ラッパーを新設）、全12
  テストシナリオファイル（呼び出し箇所の書き換え）、`SIGNAL_MAP.md`
  （`*_LAYOUT`が説明用ラベルであり実在のLua識別子ではない旨を明記）、
  README.md「コードの構成」節・「デプロイ」節。
