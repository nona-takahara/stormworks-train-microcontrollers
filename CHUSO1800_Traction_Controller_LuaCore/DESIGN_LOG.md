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

## #14 `lib/state_sync.lua`の読み込みを`require`から`dofile`へ戻す（8192文字を一時的に再超過）

- **背景**：#12で`state_sync.lua`を`require`経由に統一し、`chuso1800_core`と
  合わせて重複を解消していた（14,126→12,037文字の削減の一部）。
- **変更のきっかけ**：ユーザー「onTickはグローバルである必要がありますので、
  syncライブラリはdofileで読み込む必要がありませんか？」という指摘。
  これに対し実機生成物（`deploy/chuso1800_deploy.lua`をロードして
  `type(onTick)`/`type(_G.onTick)`を確認）で検証した結果、`require`経由
  （`-m`モードのIIFEディスパッチャに包まれる形）でも`onTick`は正しく
  トップレベルのグローバル関数になることを確認した（Luaのグローバル
  環境は関数スコープに関係なく共有されるため、`local`なしの
  `function onTick()`はどれだけ関数にネストされていても`_G`に着地する）。
  この説明を伝えたところ、ユーザーからは「いえ、dofileにしてください。
  強制的に展開させた方が納得感がありますので」との返答。技術的な正しさ
  ではなく、生成物の構造がより直接的で読み解きやすい（＝保守時の
  信頼性が高い）という判断。
- **現在の設計**：`deploy/main.lua`で`state_sync.lua`の読み込みを
  `require("state_sync")`から`dofile("state_sync")`へ戻した。
- **判明したコスト**：#12で説明した重複バグ（storm-lua-minifyの`-m`
  モードのrequireディスパッチャは、実際にrequireで参照されたかdofileで
  参照されたかに関わらず、パースした全モジュールを含めてしまう）が
  再発する。`chuso1800_core.lua`は（#12の別の理由により）引き続き
  `require`が必要なため、`-m`モード自体は有効なままであり、
  `state_sync.lua`の内容がディスパッチャ内（未使用のまま）と`dofile`
  展開箇所の両方に重複して出力される（`function onTick`が生成物中に
  2回現れることを確認）。この結果`deploy/chuso1800_deploy.lua`は
  7,873→**8,466文字**（8192文字制限を274文字超過）に増加した。
- **判断**：ユーザーへ実測値（8,466文字、274文字超過）を提示し対応方針を
  確認したところ、「このまま8466バイトで進めてください。
  storm-lua-minify側で調整します」との回答。8192文字制限は
  storm-lua-minify側のバグ（重複）に起因する一時的な超過であり、
  ユーザーが自身のパッケージ側で対処する前提のため、本リポジトリ側では
  この状態を暫定として受け入れ、追加の縮小作業は行っていない。
- **影響箇所**：`deploy/main.lua`（`dofile`への差し戻し・コメント更新）、
  README.md「デプロイ」節（現状のバイト数超過を明記）。

## #15 `chuso1800_core.lua`のモジュールテーブルを廃止し、完全なグローバルべた書き構成へ

- **背景**：#12〜#14まで、`src/chuso1800_core.lua`は`local M = {}`
  モジュールテーブルを持ち、`deploy/main.lua`から`require("chuso1800_core")`
  で読み込む設計だった。この`require`の存在が、storm-lua-minifyの`-m`
  （module-like-lua）モードを必要とし、そのモードが持つ「パースした全
  モジュールをrequire()ディスパッチャに含める」という挙動が、
  `state_sync.lua`側を`dofile`で読む設計（#14）と組み合わさると
  `state_sync.lua`の中身が二重に出力されるバグを引き起こしていた
  （7,873→8,466文字、8192文字制限を274文字超過）。
- **変更のきっかけ**：ユーザー「モジュール化を一切せず、グローバルべた書きを
  標準化できないか」「理想的には、一切モジュール化せず、グローバル関数
  べた書き合成の方がいいのですが……テストツールも、全部がべた書きなら
  対応できそうですし」との提案。storm-lua-minifyは現時点(0.1.3)では
  グローバル識別子を短縮できない（ローカルのみ短縮対象。
  `dist/ast2lua.js`の`formatExpression`で確認）ため懸念を伝えたところ、
  「storm-lua-minifyはグローバルは"現時点では"短縮できないが、将来的に
  対応する計画なので、有効と考えてください」との回答。この前提のもとで
  全面的にグローバルべた書きへ切り替えることにした。
- **現在の設計**：`src/chuso1800_core.lua`から`local M = {}`／`return M`を
  廃止し、外部（`deploy/main.lua`・テストスイート）から呼ばれる関数
  （`to_u32`/`get_bits`/`get_bit`/`put_bits`/`put_bit`/`sr_latch`/
  `zero_state`/`decode_state`/`encode_state`/`encode_stateless_in`/
  `decode_stateless_out`/`physics_tick`、および本モジュール自身の
  tickオーケストレータ）はすべて`local`なしの素のグローバル関数として
  定義する。同一ファイル内でしか使わない定数・ヘルパー（物理定数、
  `clamp`、`debounce_step`、`calc_phi`系、9個のtickサブステップ関数等）は
  従来通り`local`のまま（storm-lua-minifyのローカル変数短縮の恩恵を
  引き続き受けられる）。`deploy/main.lua`は`require`を一切使わず、
  `dofile("state_sync")`／`dofile("chuso1800_core")`の2行のみで両方を
  読み込む（`-m`モード自体を使わなくなった）。
  `deploy/build.js`もstorm-lua-minify呼び出しから`-m`フラグを削除した。
- **名前衝突の回避**：`chuso1800_core.lua`自身のtickオーケストレータは、
  元々`M.calculateTick`という名前だったが、`deploy/main.lua`側の
  state_sync契約用グローバル`calculateTick`（`lib/state_sync.lua`が
  毎tick呼ぶ、名前はこちらの都合で変更できない）と同名になると
  グローバル空間で衝突（片方がもう片方を静かに上書きする）するため、
  `core_tick`へ改名した。`deploy/main.lua`の`calculateTick`は
  内部で`core_tick(...)`を呼ぶ薄いラッパー（i2f/f2i境界変換）のまま。
- **テストスイートへの影響**：`test/run_all.lua`が`chuso1800_core.lua`を
  `dofile`で一度だけ読み込み、以降の全シナリオはグローバル関数を直接
  呼ぶ（本物のLua`dofile`はローカルは呼び出し元へ漏らさないが、
  グローバル代入は呼び出し元と共有の`_G`へそのまま反映されるため、
  この設計は実機のstorm-lua-minifyスプライスと同じ挙動になる ─
  `onTick`が`_G`に載る仕組み（#(state_sync導入時に検証済み)）と同型）。
  全12シナリオファイルから`local core = require("chuso1800_core")`を削除し、
  `core.foo(...)`呼び出しを素の`foo(...)`へ、`core.calculateTick(...)`は
  `core_tick(...)`へ置換した。`test/harness.lua`の名前付きテーブル
  ラッパー（`encode_state`等）も`core`引数を削除し、直接グローバルを呼ぶ形に
  変更した。
- **結果**：`deploy/chuso1800_deploy.lua`は**7,656文字**まで縮小
  （8192文字制限を536文字下回る）。`-m`モードのrequire()ディスパッチャ
  コード自体が丸ごと消えたことに加え、#14の重複バグも根本原因（`-m`
  モード自体）ごと解消された。テストスイート12/12は引き続き全てpass。
- **影響箇所**：`src/chuso1800_core.lua`（モジュールテーブル廃止・
  `core_tick`への改名）、`deploy/main.lua`（`require`全廃・`dofile`
  2本化・`core_tick`呼び出し）、`deploy/build.js`（`-m`フラグ削除）、
  `test/run_all.lua`（`chuso1800_core.lua`を`dofile`で一度だけ読み込み）、
  `test/harness.lua`（ラッパーから`core`引数を削除）、全12テスト
  シナリオファイル（`core.`呼び出し除去・`require`行削除）、README.md
  「コードの構成」節・「デプロイ」節、`SIGNAL_MAP.md`。

## #16 `chuso1800_core.lua`のコメントを日本語化・シェイプアップ、`property`フォールバックをテスト側へ切り出し

- **背景**：#1〜#15の各変更を都度その場のコメントに書き足してきた結果、
  `src/chuso1800_core.lua`のコメント量が肥大化していた（特にファイル冒頭の
  モジュール設計に関する説明が76行）。この種の「なぜこの設計になったか」は
  本来`DESIGN_LOG.md`が担う役割であり、ソース中に重複して書く必要はない。
- **変更のきっかけ**：ユーザー「コメントがかなり膨大になってきたので、
  適切にDESIGN_LOGに切り出し、シェイプアップしましょう。ちなみにminifierを
  入れたので日本語でのコメントが可能になりました」。
- **現在の設計**：
  1. 決定の経緯・却下した代替案など「なぜ」の長い説明は本ファイルへの
     参照（`DESIGN_LOG.md #n`）に置き換え、ソース中では繰り返さない。
  2. ローカルな非自明情報（ビット位置・引数/戻り値の順序・物理式の由来・
     元main.sw-netでの誤命名など、その場で読む人が知る必要がある内容）は
     残すが、簡潔にした。
  3. storm-lua-minifyはコメントを完全に除去してからminifyするため、
     コメントの文字数・言語はStormworksの8192文字制限に一切影響しない
     （デプロイビルドに一度でも通せば実証済み）。したがって以後は
     日本語で書いてよい（英語で書く理由は元々なかった）。
  4. `property`グローバルが存在しない非Stormworks環境向けのフォールバック
     実装（`DEFAULT_NUMBER_PROPERTIES`テーブル＋スタブ`property.getNumber`）
     を`src/chuso1800_core.lua`から削除し、`test/run_all.lua`側で
     同等の`property`グローバルを用意する形に切り出した。本番コードパスには
     元々一度も使われない分岐だったため、ソースから追い出すことで
     見通しが良くなっただけでなく、deployビルドの対象からも外れて
     実際にサイズが縮んだ（7,656→**7,496文字**）。
- **影響箇所**：`src/chuso1800_core.lua`（コメント全面的に日本語・簡潔化、
  `property`フォールバック削除）、`test/run_all.lua`（`property`スタブを
  `dofile("chuso1800_core.lua")`の前に追加）。

## #17 `main.sw-net`の実配線（README.md「今後の実配線について」の実施）

- **背景**：#1〜#16はすべて`src/chuso1800_core.lua`（Luaコア本体）の設計
  だったが、`main.sw-net`自体は「コア部分（`core_write`/`core_logic`の
  骨組み）のみのひな形」で止まっていた。今回、README.mdの「今後の実配線に
  ついて」1〜5項に沿って実際に配線し、`CHUSO1800_Traction_Controller/
  main.sw-net`（オリジナルのゲート網）と比較したときの**すべての差分**を
  ここに記録する（PR #3レビューで「Luaコア以外の.sw-net差分の説明が
  不足している」との指摘を受け、追記）。
- **前提**：以下は`src/chuso1800_core.lua`自体の変更ではなく、それを
  ゲート網へ配線する側（`main.sw-net`）だけの変更。ノードの取捨選択の
  大枠（何をLua化し何をgate側に残すか）自体は#2/#4/#9で既に決定済みで、
  今回はその決定を実際のノード・配線として書き下した作業。

### (a) オリジナルから削除したノード（Luaコアに吸収済み）

README.md「今後の実配線について」3項の通り、以下をオリジナルの
`main.sw-net`から削除し、持ち込んでいない：

- phase1/phase2/regenの3個のSRラッチとそのset/reset論理一式
  （`traction_phase1_latch`/`traction_phase2_latch`/`regen_latch`と、
  `traction_phase1_set_cond`/`traction_phase1_cap`/`phase1_notch_active`/
  `phase1_not_high_notch`/`phase1_regen_active`/`phase1_low_bc`/
  `brake_limit_sw`/`brake_current_high_phase1`/`traction_phase1_set`/
  `traction_phase1_reset`/`traction_phase2_blinker_cond`/
  `traction_phase2_cap`/`traction_phase2_set_cond`/`traction_phase2_reset`/
  `regen_set_cond`/`regen_reset`/`regen_not_available`/`traction_all_off`/
  `regen_off_all`/`power_with_regen`/`no_power_notch`/
  `field_current_excess_cond`/`field_current_excess_blinker`/
  `field_current_excess_pulse`/`coasting_cond`/`current_near_zero`/
  `no_notch_no_regen_brake_demand`/`neutral_cond`/`phase_reset_cond`/
  `regen_pulse_regen_flag_off`）
- カム進段一式（`position_counter`/`position_delta`/`position_changing`/
  `position_inc_sw`/`position_tick_pulse`/`traction_blinker`/
  `pos_inc_step`/`pos_hold_zero`/`cam_not`） ─ `cam`出力はLuaの
  status bit0（`cam_pulse`）から取り直す。
- notch処理一式（`notch_active`/`notch_eff`/`notch_enable_sw`/
  `notch_mult_one`/`notch_ge1..4`/`notch_fb`/`notch_fb_ge1`/
  `notch_fb_range_low`/`notch_fb_range_high`/`notch_fb_eq14`/
  `notch_fb_ne14`/`notch_fb_zero`/`notch_fb_nonzero`/`regen_available`）
- `eb_condition`（`BOOL_FUNC_8`）と`overspeed`（`overspeed`自体は
  gate側では未消費になったが、`overspeed_threshold`の`PROPERTY_NUMBER`
  ノード自体は(c)の通り残す）
- 旧電流源一式（`current_sim`（`LUA`, script_ref違いで実体は
  `n409.lua`）/`sim_input`/`current_src_mux`/旧`motor_current`/
  `motor_current_in_range`/`motor_current_positive`（旧版。新版は
  同名で作り直し、下記(b)参照）/`motor_current_oor`/`startup_delay`/
  `power_cut_set`/`power_cut_latch`/`power_cut_reset`）
- 電流リミット・デバウンス一式（`current_below_limit`/
  `current_below_limit_cap`/`current_limit_sw`/`current_limit_reduced`/
  `traction_any_active`）
- 界磁電流超過・ブレーキ電流一式（`brake_current_fb`/
  `brake_current_high`/`brake_current_above_300`/`brake_limit_300_b`/
  `brake_limit_300_const`/`brake_limit_400`/`brake_min_pressure`/
  `brake_below_min`）
- 回生BC一式（`regen_bc_target`/`regen_bc_smooth`/`regen_bc_sw`/
  `regen_bc_zero`/`regen_bc_below_min`/`regen_bc_min`/`regen_bc_enable`/
  `regen_delay_cap`/`bc_target_below_min`/`bc_target_min`/
  `low_bc_with_regen_flag`（旧gate版。新版はLuaのstatus bit経由）/
  `regen_current`/`regen_current_write`/`current_offset_200`）
- 旧BC平滑化・旧speed/W取得（`bc_target_raw`/`bc_target_smooth`
  （旧gate版FUNC_NUM_3自己ループ）/`speed_w_read`/`speed_raw`
  （旧current_src_mux ch7読み）/`traction_status_bool`）

### (b) 新規に追加したノード（Luaコアとの橋渡し専用。オリジナルに存在しない）

- **1tick遅延タップ×8**（`speed_delay`/`catenary_voltage_sw_out_delay`他、
  `FUNC_NUM_1(expression="x")`を1段だけ挟むだけの恒等ゲート）：
  `lib/state_sync.lua`が要求する`i1`（ch9-16、「1tick遅れた現在入力」）を
  作るためのもの。自己ループさせていない点が`position_counter`等の
  既存の自己ループ状態ノードと違う ─ SPEC.md §0.2で全ゲート出力は
  入力から1tick遅れると定義されているため、**自己ループなしの単純な
  1段通過だけで正確に1tick遅延**になる（自己ループが必要なのは「前tickの
  “自分自身の”出力」を参照する場合であり、`i1`は「前tickの“他ノードの”
  出力」を写すだけなので通過段数1つで足りる）。この1段=1tickという前提の
  信頼性は、README.md「tickモデル」に書かれている通りcomposite自己ループ
  固有の不確実性（`lib/state_sync.lua`が二重バッファ＋再同期で吸収して
  いる問題）とは別物 ─ 数値/composite単体の直列ゲート伝搬はSPEC.md §0.2の
  前提でtickカウントが確定するため、`i1`側には再同期機構を持たせていない
  （`state_sync.lua`自身も`i1`を無条件に信頼する実装になっている）。
- **`regen_flag_num`/`controller_stop_num`**（`NUM_SWITCHBOX(a=1,b=0)`）：
  `regen_flag`・`Controller Stop`はboolean信号だが、`COMPOSITE_WRITE_NUMBER`
  はnumberチャンネルしか書けないため、Luaへ渡す前に0/1のnumberへ変換する。
- **`bool_one`/`bool_zero`**（`CONST(1)`/`CONST(0)`）：オリジナルの
  `direction_flag_one`/`direction_flag_zero`と同じ値を共通化した
  リネーム。オリジナルは`forward_flag_sw`/`backward_flag_sw`の2箇所だけ
  だったが、今回`regen_flag_num`/`controller_stop_num`でも同じ
  1/0変換が必要になったため、CONSTノードを4箇所で使い回す形にまとめた
  （値は変わらない、ノード数を増やさないための整理）。
- **`core_write`（`COMPOSITE_WRITE_NUMBER`, count=16, offset=1,
  inc=core_out）**：ch1-8=i0（当tickのstateless入力そのもの）、
  ch9-16=i1（上記delayタップ）を明示的に書き込み、ch17-32は
  `inc=core_out`（`core_logic`自身の前回出力）がそのまま素通りする
  自己ループにしてある。count=16のため`in17`以降のピン自体を
  宣言していない点が重要 ─ `COMPOSITE_WRITE_NUMBER`は「count/offsetの
  範囲外のチャンネルはinc側をそのまま素通りさせる」仕様（宣言していない
  チャンネルへは一切書き込まない）なので、ch17-32はcore_out自身の値が
  無条件に折り返される。これが`lib/state_sync.lua`の要求する
  `o2_fb`（ch17-24）・`s2_fb`（ch25-32）の自己ループそのものになる。
- **Core outputs抽出一式**（`motor_current_read`/`w_read`/
  `bc_target_smooth_read`/`bcT_read`/`status_bits_read`、いずれも
  `COMPOSITE_READ_NUMBER(channel=1..5, composite=core_out)`）：
  **【PR #3レビューでの訂正】** 当初ch17-21（`output.setNumber(i+16,
  o0[i])`で当tickに計算した`o0`そのもの）を読む実装にしていたが、これは
  誤り。`lib/state_sync.lua`のonTickは、`s2`（自身が2tick前に計算し
  内部に保持しているstate）と`s2_fb`（実際に外部の自己ループ経由で
  戻ってきた2tick前のstate）を毎tick突き合わせ、食い違っていれば
  そこで初めて再計算して追いつく、という再同期をしている。つまり
  ch17-24（`o0`）は**この再同期を経る前の、当tickの時点では検証されて
  いない計算値**であり、外部のゲートが安心して消費できるのは、
  再同期の対象そのものである`s2`/`o2_fb`の系列 ─ ch1-8（`o2_fb`が
  そのまま中継された「2tick遅れた出力」）の方である。したがって
  `motor_current`等はch1（motor_current）〜ch5（status bits）から読む
  のが正当（`SIGNAL_MAP.md`の`stateless_out[1..8]`とチャンネル番号が
  そのまま対応する）。ch17-24は自己ループ経由の再同期にのみ使う内部値
  として扱い、main.sw-net側の他ゲートからは読まない。
- **`status_cam_bit`/`status_power_cut_bit`**（`FUNC_NUM_1`で
  `x%2`・`floor(x/128)%2`を計算し、`THRESHOLD(min=1,max=1)`でbooleanに
  戻す）：`SIGNAL_MAP.md`の`STATUS_BITS_LAYOUT`（stateless_out[5]、
  `put_bit`で組み立てたuint32）からbit0（`cam_pulse`）とbit7
  （`power_cut`）だけを取り出す。この2bitだけを取り出しているのは、
  `SIGNAL_MAP.md`の同表で「現状ゲート側で消費されているか」が
  この2つだけ「される」（`cam`出力／Rolling Stock Statusの
  `power_cut`ビット）で、残り6bit（phase1_latch等）は「されない ─
  予備/デバッグ用」と明記されているため ─ 使われないbitの抽出ゲートを
  追加しても死コードが増えるだけなので作っていない。
  **【PR #3レビューでの訂正・`NUMBER_TO_COMPOSITE`/`COMPOSITE_TO_NUMBER`を
  使わなかった理由の補足説明】** `COMPOSITE_TO_NUMBER`は「32個のcomposite
  boolean channelをbit0(LSB)〜bit31(MSB)としてかき集めた32bit列を、
  “その並びをIEEE754 floatのビットパターンとして解釈した値”として単一の
  Number channelに出す」ゲートである（`NUMBER_TO_COMPOSITE`はその逆
  ─ 入力`number`をIEEE754 floatのビットパターンとみなし、そのビット列を
  32個のcomposite boolean channelへ展開する）。つまりどちらの向きでも、
  「32bitの並び」と「1個のNumber値」の対応関係は**その32bitをIEEE754
  floatのビットパターンとして読み書きする**という対応であり、「32bitを
  2進数の整数として読み書きする」対応ではない。`status_bits`は
  `src/chuso1800_core.lua`の`put_bit`/`put_bits`が2進数の整数として
  組み立てた0-255の値（例：bit0とbit2が立っていれば整数値5）で、
  Stormworksのcomposite numberチャンネルにも「値が5である1個のfloat」
  としてそのまま乗って渡ってくる。ここで`NUMBER_TO_COMPOSITE`にこの
  `5`を渡すと、得られる32bitは「整数5の2進数表現(...00101)」ではなく
  「floatの5.0をIEEE754単精度でエンコードしたときのビットパターン
  (0x40A00000)」になり、`put_bit`が意図したbit0/bit2とは無関係な
  ビット列に壊れる。したがって`status_bits`から個々のbitを正しく
  取り出すには、IEEE754変換を経由しない算術演算
  （`floor(x/2^n)%2`で2進数としてのn番目のbitを直接計算する）を
  使う必要があり、今回はそちらを採用した。
  **【PR #3での確認事項】** `status_bits`（stateless_out[5]）は
  `deploy/main.lua`の`calculateTick`ラッパーが`i2f`/`f2i`を通すのは
  `state_in`/`state_out`のスロット3-7（`OLD_I`等の生double）だけであり、
  `stateless_in`/`stateless_out`はいずれの方向にも一切通らない。つまり
  `status_bits`はLua内で`put_bit`により組み立てられた整数値のまま
  `core_tick`→`calculateTick`→`state_sync.lua`の`onTick`→composite
  numberチャンネルへと、**始めから終わりまで一度もIEEE754ビットパターン
  変換を経ずに一貫して「整数値としてのfloat」で運ばれる**。したがって
  main.sw-net側でも`status_bits_read`（`COMPOSITE_READ_NUMBER`）で
  その数値を直接読み出し、`floor(x/2^n)%2`で2進数のn番目のbitとして
  そのまま解釈するのが正しい（`NUMBER_TO_COMPOSITE`等でIEEE754変換を
  挟む必要も、挟んではいけない理由もここにある）。
- **`motor_current_positive`/`danryu_not`（DANRYU再計算）**：ゲート構成
  自体はオリジナルの`motor_current_positive`/`danryu_not`
  （`GREATER_THAN`+`NOT`、`DANRYU = NOT(motor_current > 0)`）と同一。
  入力元だけがオリジナルの`current_src_mux`から新しい
  `motor_current_read`（Luaコアの`motor_current`出力）に変わっている。
- **`speed_display`の入力元**：オリジナルの`speed_display`は
  `speed_raw`（`current_src_mux` ch7）を`x*3.6+1`しているが、SPEC.md §6
  の指摘通り旧`current_sim`のch7は実際には`speed`ではなく`bcT`
  （n409.luaの出力）だった ─ つまりオリジナルの時点で名前と中身が
  食い違っていた（既知の表記バグ、今回のマイグレーションが原因ではない）。
  今回はこの**入力信号としての実体（bcT）をそのまま維持**し、Luaコアの
  `bcT`出力（`SIGNAL_MAP.md`のstateless_out[4]、core_out ch20）を
  `bcT_read`で読んで`speed_display`に繋いだ。実速度に「修正」しなかった
  理由は、Momelink 1900フレーム（ch25）の実際の送信内容をオリジナルと
  ビット互換に保つため（この移行のスコープは「Lua化」であって「既存の
  誤表記の是正」ではないため、既存の表記バグはそのまま踏襲する方針 ─
  #10のような明確な誤命名修正とは異なり、外部フレーム仕様に影響する値は
  今回変更していない）。
- **`W`/`bc_target_smooth`の読み出し元**：オリジナルは`current_src_mux`
  のch4（`speed_w_read`）・自前のFUNC_NUM_3自己ループ
  （`bc_target_smooth`）だったが、どちらもLuaコア内部
  （`core_tick`/`smooth_bc`）に統合されたため、`core_out`のch18・ch19を
  読むだけになった。計算式自体（`accel*0.2+bc_target_smooth*0.8`のEMA等）
  は`src/chuso1800_core.lua`側で不変。

### (c) オリジナルのまま維持したノード

- パンタグラフ4ラッチ一式・Momelink整形一式・Rolling Stock Status整形
  一式は、ノード構成・パラメータともオリジナルと完全に同一（README.md
  「今後の実配線について」4項の通り、入力元だけを新モジュールの出力へ
  張り替え）。
- `overspeed_threshold`/`power_limit_current`の`PROPERTY_NUMBER`ノードは
  ノード自体を残す（出力は現在gate側では未消費 ─
  `src/chuso1800_core.lua`が同名プロパティを`property.getNumber`で
  直接読むため。#3参照）。`brake_limit_current`
  （「Brake Limit@320kPa [A]」）はSPEC.md §5で**オリジナルの時点で
  既に未消費と指摘済みの死コード**であり、今回のマイグレーションの
  スコープ外として無変更のまま残してある。
- SAP/ECBブレーキ圧解決一式（`sap_ecb_toggle`/`ecb_pressure_sw`/
  `ecb_sap_pressure`/`eb_signal`/`sap_raw`等）とdirection合成一式
  （`forward_signal`/`backward_signal`/`forward_flag_sw`/
  `backward_flag_sw`/`direction`）は、ノード構成・式ともオリジナルと
  同一（#4で決定済みの通り、最終値だけをLuaコアへ渡す）。

### (d) Catenary voltage control節について（今回のセッション以前からの差分）

- `main.sw-net`の「Catenary voltage control」節は、本セッション開始前
  から既にひな形として配置されていたもので、今回新規に書いたものではない。
  ただしオリジナルとの差分として説明が必要なため記録する：
  - `catenary_active_thresh`のしきい値が`(min=0, max=0)`になっている
    （オリジナルは`(min=0, max=1)`）。これはSPEC.md §4.2/§6-1（H1）で
    指摘されている「storm-mclのシリアライズ不具合で`.sw-net`の字面が
    `(0,1)`になっているが実機の真値は`(0,0)`」を踏まえた**実機値での
    修正版**であり、退行ではない。
  - `catenary_active_thresh_out`→`catenary_dead`、
    `catenary_inactive_out`→`catenary_active_out`、
    `catenary_voltage_sub_en`→`catenary_voltage_en`にリネームされている
    （論理は同一、「無電圧域を検出するのに`_active`と名付いている」
    という元の命名の分かりにくさ（SPEC.md §5「命名反転」表参照）を
    是正する趣旨のリネームと見られる）。
- **影響箇所**：`CHUSO1800_Traction_Controller_LuaCore/main.sw-net`
  全体（新規実配線）、`project.json`（"Phyics Sensor [+Z is front]"の
  タイポ修正、既存の`nodes`側リネームに`links`側が追従していなかった
  ことによる配線切れの修正）、`main.sw-mcl`（`storm-mcl layout-dsl`で
  新規生成）。

## #18 storm-lua-minify（および元ネタのluamin）の演算子優先順位バグにより
`put_bit`/`put_bits`/`get_bits`がminify後に壊れていたのを修正

- **経緯**：PR #3の実機テストで、`notch_pos=4`等の力行指令を与えても
  一切加速しない現象が報告された。`main.sw-net`の配線（#17）を何度も
  疑って切り分けを重ねたが（stateless入力の内容、composite自己ループの
  `s2`/`s2_fb`一致、`calculateTick`のi2f/f2i境界）、いずれも正常だった。
- **切り分け**：`src/chuso1800_core.lua`の`core_tick`を素の`lua`で
  実機報告どおりの入力・状態で直接呼ぶと、1tick目でphase1へ正しく
  遷移し実電流が流れることを確認した。ところが**同じ入力を
  `deploy/chuso1800_deploy.lua`（minify後の実機投入版）へ与えると、
  `position_counter=1・phase1/2/regenラッチ全部false・OLD_IF_A=20`
  というコースティング（惰行）の固定点に固まったまま遷移しなかった**。
  ソースと成果物とで挙動が違う＝**minify自体が壊している**という
  ことになる。
- **原因の特定**：`deploy/chuso1800_deploy.lua`内の`put_bit`の実体を見ると
  ```lua
  function put_bit(I,G)return I and 1 or 0<<G end
  ```
  になっていた。元のソースは `(b and 1 or 0) << shift`
  （必要な括弧つき）だが、Luaの`<<`は`and`/`or`より演算子優先順位が
  **高い**ため、括弧が落ちると`I and 1 or (0<<G)`＝`I and 1 or 0`と
  解釈され、**`shift`が完全に無視されて常に0か1を返す**バグになる。
  同根の問題で`put_bits`のマスク計算`(1 << width) - 1`も、`-`が`<<`より
  優先順位が高いため括弧が落ちると`1 << (width - 1)`になり、
  `get_bits`の同じ形のマスク計算も同様に壊れていた（`get_bits`自身の
  外側`(acc >> shift) & (...)`は、たまたま`>>`が`&`より優先順位が高い
  というLuaの既定順序と一致するため、括弧が落ちても実害がなかった
  ─ 壊れるのは「既定の優先順位を明示的に上書きするために括弧が必要な
  箇所」だけ、というのがこのバグの本質）。
- **npm本体（luamin）でも同一のバグを確認**：storm-lua-minifyは
  ユーザー自身が開発している別パッケージだが、そのコードの元ネタである
  npm公開済みの`luamin`単体（`(b and 1 or 0) << shift`等、同じ式を
  minifyしただけ）でも**バイト単位で同一の壊れた出力**になることを
  実際にインストールして確認した。ユーザーからのちに
  https://github.com/mathiasbynens/luamin/issues/76
  （`(a & b) >> c`が`a & b >> c`に壊れるという、同根の既知issue）の
  存在を教えてもらい、根本原因（再出力時に演算子優先順位表を踏まえずに
  括弧を無条件に削る）が上流luamin由来の既知の問題であることを確認した。
  このためユーザーが提案した「代替でluaminを直接使うbuild.js」という
  回避策は**同じバグを踏むため有効ではない**と判断し、採用していない。
- **対応**：`src/chuso1800_core.lua`の`get_bits`/`get_bit`/`put_bits`/
  `put_bit`を、二項演算子1個につき1行の`local`代入へ分解する書き方に
  全面的に書き直した（例：`local shifted=acc>>shift; local mask=...;
  return shifted&mask`）。これは可読性のためではなく、**「削られると
  困る括弧」を含む複合式を最初から作らない**という、このminifierバグ
  そのものへの回避策。今後この4関数（および同種のビット演算コード）を
  1行の複合式へ戻さないこと。
- **見つかった経緯の反省点とテストの追加**：`test/run_all.lua`の12
  シナリオはいずれも`src/chuso1800_core.lua`（minify前）を直接
  `dofile`するため、minifyそのものが原因のバグは原理的に検出できな
  かった。これは実際に本バグが12/12 passのまま実機まで届いてしまった
  直接の原因。再発防止として`test/verify_deploy_artifact.lua`を新設し、
  `deploy/chuso1800_deploy.lua`自体を`input`/`output`モック経由で
  動かして（1）`put_bit`/`put_bits`の往復、（2）実機報告と同じ入力を
  与えてphase1へ遷移し実電流が流れること、の両方を検証する。
- **影響箇所**：`src/chuso1800_core.lua`（`get_bits`/`get_bit`/
  `put_bits`/`put_bit`の書き直し）、`deploy/chuso1800_deploy.lua`
  （`node build.js`で再生成、7,628文字＝8192文字制限内）、新規
  `test/verify_deploy_artifact.lua`、README.md「テスト」節。

## #19 新SPEC.md（ChatGPTとの再検証版）との突き合わせで発見した
`chuso1800_core.lua`側の2件のバグを修正

- **背景**：ユーザーがChatGPTと共に`CHUSO1800_Traction_Controller/main.sw-net`を
  ゼロから再検証し、`CHUSO1800_Traction_Controller_main_renamed.sw-net`・
  新`SPEC.md`・`LEGACY_SPEC_CORRECTIONS.md`としてPRへ追加した。これにより、
  storm-mclのシリアライズ不具合で`THRESHOLD(min=0,max=1)`と誤出力されていた
  6ノードのうち、`direction_nonzero`（#17で既に対応済み）以外の5ノードの
  実値が初めて確定した。`chuso1800_core.lua`はこれらのうち2箇所を、
  誤った側（旧SPEC.mdの(0,1)解釈）を前提に実装していたことが判明したため
  修正した（`main.sw-net`側の配線ではなくLuaコア自体のバグ）。
- **バグ1：`cam`出力（カムパルス）の発火条件**。旧SPEC.mdは「カム1巡完了時
  だけ発火」としていたが、正しくは`cam_position_unchanged`
  （`THRESHOLD(0,0)`、実値`(0,0)`）を`NOT`しただけの「カム位置のDELTAが
  0でないtickすべてで発火」（通常の+1進段でも、20→0の折返しでも発火）。
  `advance_cam`の`cam_pulse`計算を`not (delta >= 0 and delta <= 1)`
  （折返し時のみtrue）から`delta ~= 0`（位置が変化した全tickでtrue）へ
  修正した。
- **バグ2：`notch_fb_ge1`（カム位置≤1判定）は実際は`cam_at_zero`
  （カム位置**厳密に0**）だった**。オリジナルsw-netには`notch_fb_ge1`
  （進段開始条件用）と`regen_available`（界磁制御ラッチ投入条件用）という
  同一式`THRESHOLD(0,1)(notch_fb)`の重複ノードが2つあり（旧SPEC.md
  §5「冗長・デッドロジック」で指摘済み）、今回のLua移植では1つの
  `notch_fb_ge1`変数へ統合していた。ところが実機の真値はどちらも
  `THRESHOLD(0,0)`（カム位置が厳密に0の場合のみ）であり、`(0,1)`
  レンジのまま統合してしまっていた。`notch_and_cam_feedback`の該当行を
  `notch_fb >= 0 and notch_fb <= 1`から`notch_fb == 0`へ修正した。
  この値は`power_with_regen`（直列ラッチ投入条件の一部）と
  `regen_latch`（界磁制御ラッチ）の投入条件・`regen_off_all`
  （カムホーミング条件）の3箇所すべてに使われている。
- **【重要な訂正】「フル力行中に`regen_latch`が誤って立つ」という
  以前の指摘の撤回**：本セッション中、フル力行を続けたまま加速する
  シミュレーションで、カムのリング（`(x+y)%21`、上限で飽和しない）が
  一巡してカム位置0へ戻るたびに`regen_latch`がtrueになる現象を発見し、
  「まだ全開力行中なのに回生へ誤って遷移するバグではないか」と報告して
  いた。しかし新SPEC.md §7.1・LEGACY_SPEC_CORRECTIONS.md #2により、
  `regen_latch`（`field_control_latch`と改称すべき）は**回生専用の
  ラッチではなく、並列抵抗制御完了後の界磁制御（弱め界磁）モードを表し、
  力行・回生の両方で使われる**ことが判明した。つまり観測した現象は
  「並列で加速中にカムが一巡して0へ戻ったら界磁制御（弱め界磁）モードへ
  入る」という、SPEC.md §7.2 手順5に明記された**意図通りの力行シーケンスの
  一部**であり、バグではない。「40km/h付近で加速度が鈍る」という当初の
  観測自体は、弱め界磁突入に伴う自然な特性である可能性が高く、誤診断
  だった点を訂正する。ただし変数名`regen_latch`・`regen_off_all`等が
  この実態と乖離した名前のままである点は、今後の可読性向上の余地として
  残っている（本コミットでは修正していない）。
- **テスト**：`test/scenarios/spec_v2_corrections.lua`を新設。
  （1）カムが通常の+1進段をした際に`cam_pulse`がtrueになること、
  （2）カムが動かないtickでは`cam_pulse`がfalseのままであること、
  （3）カム位置1では界磁制御ラッチが投入されないこと、
  （4）カム位置0（厳密）では界磁制御ラッチが投入されること、
  の4点を検証する。既存13→14本、`test/verify_deploy_artifact.lua`も
  合わせて全て通過を確認した。
- **影響箇所**：`src/chuso1800_core.lua`（`notch_and_cam_feedback`・
  `advance_cam`）、`deploy/chuso1800_deploy.lua`（再生成）、新規
  `test/scenarios/spec_v2_corrections.lua`、`test/run_all.lua`
  （シナリオ登録）。

## #20 `main.sw-net`のゲート側ノード名を、新SPEC.md（再検証版）の命名に合わせて全面リネーム

- **背景**：#19で新`SPEC.md`・`LEGACY_SPEC_CORRECTIONS.md`・
  `CHUSO1800_Traction_Controller_main_renamed.sw-net`を取り込んだ後、
  「.sw-netも適宜修正してほしい（本PRのメインタスクはsw-netの作成）」との
  指示を受けた。`main.sw-net`のゲート側（SAP/ECB・direction合成・
  カテナリ電圧・パンタグラフ・Momelink整形・RSS整形、およびLuaコアとの
  橋渡し用に今回新設したノード群）は、いずれもオリジナルの誤解を招く
  旧名（`sap_ecb_toggle`／`catenary_active_thresh`／`speed_display`／
  `bc_pressure_norm`／`momelink_1900_out`等）のまま実装していた。
  新SPEC.mdの「保守上の原則」（§16）が明記する「Phase 1/2のような抽象名を
  再導入せず直列・並列・界磁制御を明記する」等の方針を`main.sw-net`にも
  反映するため、対応する各ノードを`CHUSO1800_Traction_Controller_main_
  renamed.sw-net`と同じ名前へリネームした。
- **リネームしたもの**（対応するオリジナルsw-netのゲートが存在する範囲）：
  `sap_ecb_toggle→brake_system_is_sap`、`eb_signal→emergency_brake_command`、
  `ecb_pressure_sw→ecb_virtual_brake_pipe`、
  `brake_pressure_sw→brake_pipe_for_inhibit`、`sap_raw→brake_command`、
  `ecb_sap_pressure→ecb_brake_demand_pressure`、
  `sap_pressure_sw→brake_demand_pressure`、
  `forward_signal/backward_signal→forward_command/reverse_command`、
  `forward_flag_sw/backward_flag_sw→forward_direction_value/
  reverse_direction_value`、`direction→direction_sign`、
  `notch_pos→power_notch_command`、`regen_flag→db_auto_command`、
  `speed→vehicle_speed`、`catenary_rated_voltage→
  nominal_catenary_voltage`、`catenary_voltage_toggle→
  use_supplied_catenary_voltage`、`catenary_active_thresh→
  catenary_input_zero`、`catenary_inactive→catenary_input_nonzero`、
  `catenary_voltage_en→use_catenary_input`、`panta_up→
  panta_1800_active_any`、`catenary_voltage_mux→
  selected_catenary_voltage`、`catenary_voltage_sw→
  traction_supply_voltage`、`mtype_toggle→vehicle_type_1900`、
  `is_1800_type→vehicle_type_1800`、`bc_pressure_norm→
  bc_application_ratio`、`momelink_1800_out→momelink_1800_frame`、
  `momelink_1900_out→momelink_advanced_frame`、`unit_type_code→
  inner_unit_type_id`、`type_is_1911→inner_unit_type_is_1911`、
  `type_id_1911→momelink_type_id_1911`、`const_35→vehicle_mass_tonnes`、
  `momelink_ch26→inner_unit_acceleration`、`momelink_1900_select→
  use_1900_advanced_frame`、`momelink_version_sw→
  momelink_output_frame_mux`、`rolling_status_bool_write→
  rolling_stock_status_bool`、`momelink_src_mux→status_data_source`、
  `momelink_ch24/23→status_armature_current/status_catenary_voltage`、
  `bc_pressure_kpa→bc_gauge_pressure_kpa`、`bc_target_read→
  status_bc_target`、`rolling_status_write→rolling_stock_status`。
- **Luaコアとの橋渡し用（今回新設分、新SPEC.mdのLua入出力表§8.2/8.5に
  合わせて命名）**：`motor_current_read→armature_current_read`、
  `w_read→traction_power_read`、`bc_target_smooth_read→
  model_acceleration_smoothed_read`（stateless_out[3]、SPEC.md §8.5 N3
  「車両加速度」）、`bcT_read→pneumatic_brake_decel_demand_read`
  （stateless_out[4]、同N7「空気ブレーキ補完要求」）、
  `status_bits_read→traction_model_status_read`、
  `status_cam_bit/status_cam_pulse→cam_position_changed_bit/
  cam_position_changed_flag`、`status_power_cut_bit/status_power_cut→
  traction_fault_bit/traction_fault_flag`、`speed_display→
  bc_target_abs_pressure`（新SPEC.md §10.4の式`pneumatic_demand*3.6+1`と
  同一）。
- **変更していないもの**：`PROPERTY_*`ノードの`n=`属性（ゲーム内
  プロパティパネルの表示名・実車のセーブデータに紐づく実体で、ノード名の
  リネームとは別次元の破壊的変更になるため）。`n="Catenary Line Voltage"`／
  `n="M type"`はリネーム版参照sw-netでは`n="Use Supplied Catenary
  Voltage"`／`n="M Type"`に変わっているが、これは追随していない
  （ユーザー確認待ち）。ポート名（`"BC target [atm]"`等、実車の外部
  結線に紐づく）も無変更。
- **確認**：リネームは配線トポロジ・パラメータを一切変えない純粋な
  識別子変更。`typecheck-dsl`・`dsl2xml`（警告なし）・
  `lua test/run_all.lua`（13/13）・`test/verify_deploy_artifact.lua`
  で無影響を確認した。`main.sw-mcl`は`storm-mcl layout-dsl --force`で
  再生成した。
- **影響箇所**：`CHUSO1800_Traction_Controller_LuaCore/main.sw-net`
  全体、`main.sw-mcl`（再生成）、`SIGNAL_MAP.md`「ゲートに残すもの」節・
  ステートレス出力スロット表（新ノード名に追従）。

## #21 マージ前レビューとして`claude-fable-5`モデルへ独立コードレビューを依頼、
`regen_delay`のヒステリシス欠落バグを修正

- **背景**：#17-#20の一連の修正・リネームを終え、ユーザーから
  「Fable 5によるレビューを受けて、問題なければ実機で不具合が残っていても
  一旦マージする」方針の指示を受けた。レビューは`Agent`ツールに
  `model: "fable"`を指定して起動し、`main.sw-net`・
  `src/chuso1800_core.lua`・`lib/state_sync.lua`・新SPEC.md・
  `CHUSO1800_Traction_Controller_main_renamed.sw-net`を独立に
  突き合わせさせた。
- **レビュー結果概要**（優先度順）：
  - **F1（要修正・本エントリで対応）**：`regen_delay`（回生遅延の
    `CAPACITOR(0.5, 10)`相当）を「充電完了」判定として`regen_delay_level
    >= 600`という**レベルの単純比較**で実装していたが、実機の
    Stormworks CAPACITORはヒステリシス動作（満充電で一度ONになったら、
    放電が完了する＝レベル0に戻るまでONを保持し続ける）をする。旧実装では
    放電開始後1tick目（600→599）で即座に「未充電」判定へ落ち、
    本来10秒（600tick）保持されるべき回生抑制が実質1tickしか効かなかった。
  - F2：#17時点のコメントに、その後#18で撤回した「全ゲートは1tick遅延する」
    という前提を引きずった記述が残っていた（軽微・情報用途のみ、実害なし）。
  - F3：`notch_pos`の`math.floor`丸めについての些末な指摘（実害なし、
    現状のまま維持で問題ない）。
  - F4：`PROPERTY`ノードの`n=`属性を新SPEC.mdの表示名に追従させるかは
    #20で既に「ユーザー確認待ち」として明記済みの未決事項であり、
    新規の指摘ではない。
- **F1の修正**：レベル（`regen_delay_level`、0-600の整数）に加えて、
  ヒステリシス出力そのものを表す新しい状態bit `regen_delay_active`を
  STATE_TIMERS_LAYOUT（`state_in[2]`／`state_out[2]`）のbit19に追加した。
  `regen_delay_step(old_level, old_active, enable)`が
  レベルの増減と同時に`new_active`を計算する：`enable`中は
  `old_active`が真であれば真のまま維持（レベル`> 0`である限り）、
  `enable`が切れて放電に転じてもレベルが0に達するまでは真を維持し続け、
  レベルが600に達した瞬間に初めて真になる（`old_active`が偽の場合）。
  旧`regen_delay_charged(level) = level >= 600`関数は削除した。
  `encode_state`/`decode_state`（`regen_delay_active`をslot2のbit19として
  読み書き）・`smooth_bc`（`regen_bc_enable`の判定を`regen_delay_active`
  ベースへ変更）・`core_tick`の呼び出し箇所を対応する形へ更新した。
- **テスト**：`test/scenarios/regen_delay_cap_timing.lua`の
  「充電完了しきい値」節を、旧仕様（`level>=600`）を前提にした誤った
  アサーションから、新しいヒステリシス仕様を検証する5ケース
  （レベル600・active=trueで有効、レベル599でもactive=trueなら
  ヒステリシスにより有効を維持──本バグの直接の回帰ガード──、
  レベル599でactive=false（一度も満充電に達していない）なら無効、
  レベル1から放電してレベル0に達した瞬間にのみactiveがfalseへ切り替わる）
  へ書き換えた。`test/harness.lua`の`encode_state`/`decode_state`
  ラッパーにも`regen_delay_active`フィールドを追加した。
  `lua test/run_all.lua`（13/13）・`test/verify_deploy_artifact.lua`
  で無回帰を確認した。
- **影響箇所**：`src/chuso1800_core.lua`（`regen_delay_step`・
  `encode_state`・`decode_state`・`smooth_bc`・`core_tick`）、
  `deploy/chuso1800_deploy.lua`（再生成、7669文字）、
  `test/harness.lua`・`test/scenarios/regen_delay_cap_timing.lua`、
  `SIGNAL_MAP.md`（STATE_TIMERS_LAYOUT表を19bit→20bit使用へ更新、
  `regen_delay_active`の説明を追記）。

## #22 `tools/sw-net-sim`（原稿ゲート網）と`chuso1800_core.lua`の突き合わせ調査
　─ 新規の実装バグは検出されず、tickモデル差による1件のみ発見・文書化

- **経緯**：PR #5で`tools/sw-net-sim`（原稿`main.sw-net`＋`scripts/n409.lua`を
  単体でtick実行できるシミュレータ）がマージされたことを受け、これを使って
  `chuso1800_core.lua`の実機バグ調査を行った。単純なtick単位diffは
  無効（`tools/sw-net-sim/README.md`が明記する通り、シミュレータは全ゲート
  1tick遅延モデル、`chuso1800_core.lua`は組合せ論理を同tick内に圧縮する
  モデルで、前提が異なる）なため、「定常値」と「状態遷移の順序」ベースで
  突き合わせた。
- **手法**：原稿ゲート網（`sim.lua`）と`chuso1800_core.lua`の`core_tick`に
  同一の外部シナリオ（notch・speed・direction・brake等）を並行して与え、
  `position_counter`／`phase1_latch`／`phase2_latch`／`regen_latch`／
  `notch_ge1`／`field_current_excess_cond`等の遷移イベント列（tick番号と
  新値）を両モデルから抽出し、(1) 遷移の**順序**が一致するか、(2) 十分な
  tick数の後の**定常値**が一致するかを確認した（比較ハーネス自体は
  スクラッチパッドで使い捨て、リポジトリにはコミットしていない）。
- **検証したシナリオ**：フル力行での直列→並列→界磁制御（弱め界磁）の
  一巡（cam 0→20→0）、途中でnotchを落とした場合のカムホーミング
  （SPEC §7.4）、力行から回生への切替（ECBモード、db_auto+brake_cmd）、
  界磁電流超過パルスによる並列→直列への降格（SPEC §7.5）、EB/方向中立/
  過速度/ブレーキ管圧不足の各牽引禁止条件（`eb_condition`）の網羅的
  スイープ、`regen_delay`ヒステリシス（#21）の数値検証。
- **結果**：上記すべてで、遷移の順序と定常値が両モデルで一致した
  （EB系条件のスイープは9パターン全てブール値が完全一致、
  `regen_delay`ヒステリシスはCAPACITORノードを直接1500tick駆動し
  `regen_delay_step`と突き合わせて**遷移tickまで完全一致**─ #21修正が
  正しかったことの独立検証になった）。新規の実装ミスは見つからなかった。
- **発見した1件（バグではなくtickモデル差、H7と同カテゴリ）**：
  並列（phase2）ラッチ投入中に界磁電流超過パルスが発火すると、SPEC §7.5
  「並列→直列への切替」により直列（phase1）が一旦SETされるはずだが、
  `db_auto`（`regen_flag`）がOFFの場合、原稿ゲート網では直列が1～2tickだけ
  可視的にON（co-on状態）になってからリセットされるのに対し、
  `chuso1800_core.lua`ではこの遷移が一切見えない（直列は一度もtrueに
  ならないまま並列が直接リセットされる）ことを発見した。
  原因は`phase_state_machine`の`phase1_set`（`field_current_excess_pulse
  and phase2_latch`）と`phase1_reset`（`phase_reset_cond`経由で
  `field_current_excess_pulse and (not regen_flag)`を含む）が**同一tickの
  同一pulse値**を参照しているため（`sr_latch`はreset優先）。原稿ゲート網
  では`traction_phase1_set`がpulseから1ホップなのに対し、
  `traction_phase1_reset`側は`phase_reset_cond`経由で2ホップ
  （`field_current_excess_pulse→regen_pulse_regen_flag_off→
  phase_reset_cond→traction_phase1_reset`）のため、全ゲート1tick遅延の
  原稿ネットでは1tickだけ両者がズレて直列SETが可視化される。
  `regen_flag`がONの場合はこの`phase_reset_cond`側のpulse項が消えるため
  マスキングは起きず、両モデルとも直列が可視的にSET・保持される
  （これも突き合わせで確認済み）。
- **バグと判断しなかった理由**：H7（`h7_cam_overshoot_homing.lua`）と
  同じ「組合せ論理の同tick内圧縮により過渡のtick数が短縮されるが、
  収束後の状態は変わらない」パターン（SPEC.md §0.2が明示的に許容）。
  実際、両モデルとも数tick後には直列/並列/界磁制御すべてOFF（中立）へ
  収束することを確認済み。`regen_flag`ONケースでも、直列SET/並列RESETの
  順序自体は両モデル一致。よって`src/chuso1800_core.lua`側は修正せず、
  H7と同様に「収束後の挙動が正しいことを明示的に検証するテスト」を追加
  するにとどめた。
- **テスト**：`test/scenarios/field_current_excess_pulse_reset_masking.lua`
  を新設。`regen_flag=false`でSETが一切可視化されないまま中立へ収束する
  ことと、`regen_flag=true`でSETが可視化されたまま保持されることの両方を
  検証する（将来`phase_state_machine`の項の順序が意図せず変わった場合の
  回帰ガード）。既存14→15本、`test/verify_deploy_artifact.lua`も合わせて
  全て通過を確認した。
- **未実施（第2段階）**：Stormworksで一度再保存したXMLをsw-net変換した
  ものに対する同一手法での突き合わせは、本セッションの環境に実機resave
  済みXMLが存在しないため実施していない。原稿`main.sw-net`（storm-mclの
  シリアライズ不具合を含む生成直後のもの）との突き合わせで新規バグが
  出なかった以上、次に疑うべきは「storm-mcl生成そのものが実機仕様と
  異なる」可能性（`LEGACY_SPEC_CORRECTIONS.md` §3のTHRESHOLDパース不具合
  のような類）だが、これを検証するには実機resave済みXMLが要る。
- **影響箇所**：新規`test/scenarios/field_current_excess_pulse_reset_masking.lua`、
  `test/run_all.lua`（シナリオ登録）。`src/chuso1800_core.lua`・
  `deploy/chuso1800_deploy.lua`は無変更。

## #23 実機で確認された「並列＋界磁制御固着からの再力行で過電流／低速固着」
　バグを修正（本セッションのメインタスクだった実機バグそのもの）

- **経緯**：ユーザーからStormworks実機で「固着するような挙動」を確認済み
  との報告を受け、#22で見つけていた「フル力行でカムが一周し並列＋界磁制御
  （`phase2_latch`＋`regen_latch`）まで到達した後、notchを0に戻して放置
  すると内部状態が二度と中立へ戻らない」という現象（#22執筆時点では
  「両モデルが一致するので実装バグではない」として深掘りしていなかった）
  を再調査した。
- **再現**：`chuso1800_core.lua`単体で、フル力行→カム一周（`position_counter=0`、
  `phase1_latch=false`／`phase2_latch=true`／`regen_latch=true`）→notch=0で
  長時間放置、という手順を踏むと、`phase2_latch`／`regen_latch`が
  **恒久的にON**のまま固着することを確認した。この状態から
  (1) 低速（0.5m/s）でノッチ1を再投入すると電機子電流が**約4950～5300A**
  （`Power Limit Current`210Aの約24倍）まで瞬間的に跳ね上がる、
  (2) 中速（8m/s）でフルノッチを再投入すると電流は`200A`程度に留まるが
  それ以上上がらず、カムも二度と動かないまま**低出力で永久に固着**する、
  の2通りの症状を確認した。ユーザーからの追加報告で(2)も実機で確認済み
  であることが分かった。
- **原因**：sw-net-sim経由で`CHUSO1800_Traction_Controller/main.sw-net`
  （原稿ゲート網）＋`n409.lua`を同じ手順で駆動したところ、電流値まで
  ほぼ完全一致（4958.70A）で同じ現象を再現した。**Luaコア移植のバグでは
  なく、原稿ゲート網自体に元からある状態遷移の抜け穴**である：
  - `phase2_latch`のリセット経路は`phase_reset_cond`
    （`coasting_cond or (field_current_excess_pulse and not regen_flag)`）
    のみ。`coasting_cond`は`neutral_cond and (not regen_latch)`を要求する
    が、`regen_latch`が固着してtrueのままなので**この経路は原理的に
    絶対に成立しない**。もう一方の`field_current_excess_pulse`は
    界磁電流が300/400Aを超えないと発火せず、真にアイドル状態（notch=0・
    ブレーキ要求なし・電流ほぼ0）ではこの閾値には到達しない。
  - `phase1_set`（直列再投入）の条件は
    `(power_with_regen and not phase2_latch) or (field_current_excess_pulse
    and phase2_latch)`。`power_with_regen`項は`phase2_latch`がONだと
    ブロックされ、`field_current_excess_pulse`項も上記と同じ理由で発火
    しない。結果、**直列（抵抗投入側）へ再遷移する経路が一切ない**。
  - 固着状態でnotchを再投入すると、カム位置0（並列側抵抗表`PR[1]=0Ω`＝
    抵抗全短絡）のまま`physics_tick`の`regen`分岐（`regen_latch`が
    trueなのでこちらに入る）で電圧をほぼ無抵抗（`MOT_RES=0.07Ω`のみ）で
    接続することになり、Newton法の収束先次第で数千A規模の過電流、
    または「弱め界磁の定電流整定点(約200A)に収束するが直列の強トルク
    特性を一切経由しないため実質進段不能」のどちらかに陥る。
- **修正方針の相談・決定**：規模の大きい変更（原稿`main.sw-net`側の
  設計変更を伴う可能性）のため、`AskUserQuestion`でユーザーに確認した。
  結果：(1) 修正範囲は`chuso1800_core.lua`のみ（`CHUSO1800_Traction_
  Controller/main.sw-net`はREADME.mdの方針通り無変更のまま）、
  (2) リセットのトリガーは既存の「界磁電流過剰」フラグの経路
  （`field_current_excess_cond`→`field_current_excess_pulse`）を流用しつつ
  検知条件を見直す、という2点で合意した。
- **修正内容**：`field_current_excess_block`に新しい判定
  `stuck_at_top_idle`（`regen_latch and phase2_latch and (not phase1_latch)
  and notch_fb_ge1(カム0) and current_near_zero(motor_current) and (not
  low_bc_with_regen_flag)`）を追加し、既存の`field_current_excess_cond`
  （界磁電流300/400A超過判定）と`or`で合流させた
  （`(field_current_excess or stuck_at_top_idle) and (not notch_ge1)`）。
  これにより：
  - 界磁電流300/400A超過による既存の並列→直列降格・回生遅延の挙動は
    完全に無変更（`field_current_excess`項がそのまま残る）。
  - 新たに「カム0で並列＋界磁制御だけが立ったまま直列が一度も立たない
    状態」かつ「notch/回生要求ともになく電流もほぼ0まで収束している」
    場合も同じ`field_current_excess_pulse`が発火し、
    `phase_state_machine`側の`phase1_set`／`phase_reset_cond`の
    **既存の配線をそのまま再利用**して両ラッチを中立へ解放する
    （新しい状態スロット・新しいSRラッチ経路は一切追加していない）。
  - `phase_state_machine`内で重複していた`current_near_zero`のしきい値
    判定（`-50..50`）を、共有ローカル関数`current_near_zero(motor_current)`
    へくくり出した（DRY化、挙動は無変更）。
- **修正後の確認**：修正前に確認した2症状がいずれも解消したことを直接
  実行して確認した：(1) 低速再投入時、アイドル中に約50tick（電流減衰）
  ＋30tick（デバウンス、既存の`FIELD_CURRENT_EXCESS_PERIOD_TICKS`と同一）
  で両ラッチが中立へ解放され、以降の再力行では直列（`SR[1]=7.428Ω`）が
  正しく投入され電流は約171～174Aに収まる。(2) 中速フルノッチ再投入時も
  同様に直列から正しく再進段し、カムが0で固着せず通常通り進段する
  （確認例：tick300で`position_counter=16`まで正常進段）。
  一方、notchが実際に投入されている間や、回生ブレーキ要求
  （`low_bc_with_regen_flag`）が生きている間は、この新条件が発火しない
  （`not notch_ge1`／`not low_bc_with_regen_flag`のガード）ことも確認済み
  ─ 力行中・制動中に界磁制御ラッチが不意に解放されることはない。
  `tools/sw-net-sim`側の既存突き合わせシナリオ（#22で作成した各種）も
  再実行し、無回帰を確認した（この修正は原稿`main.sw-net`側には反映して
  いないため、固着シナリオそのものについては両モデルが意図的に乖離する
  ─ これは合意した修正範囲どおり）。
- **テスト**：`test/scenarios/stuck_at_top_of_ladder_recovery.lua`を新設。
  （1）アイドル放置で固着状態が中立へ解放されること、（2）解放後の
  再力行が直列（抵抗あり）を正しく経由し、過電流の再現条件
  （直列を経由しないまま並列で電流>1000A）が発生しないこと、
  （3）notch投入中は固着状態が解放されないこと、（4）回生ブレーキ要求
  発生中も固着状態が解放されないこと、の4点を検証する。既存15→16本、
  `test/verify_deploy_artifact.lua`も合わせて全て通過を確認した。
- **影響箇所**：`src/chuso1800_core.lua`（`field_current_excess_block`・
  `phase_state_machine`・共有`current_near_zero`関数・`core_tick`の
  呼び出し箇所）、`deploy/chuso1800_deploy.lua`（`node build.js`で
  再生成、7,802文字＝8192文字制限内）、新規
  `test/scenarios/stuck_at_top_of_ladder_recovery.lua`、`test/run_all.lua`
  （シナリオ登録）。`CHUSO1800_Traction_Controller/main.sw-net`は
  ユーザーとの合意通り無変更。

## #24 storm-lua-minifyの変数名衝突バグにより、`K`（電動機定数）が
高速域で界磁電流Newton法の解を破壊し、カムが並列以降へ一切進段しなく
なっていた不具合を修正（実機セーブで実在を確認済み）

- **経緯**：#23の固着バグ修正後、ユーザーから「初回スポーン直後、
  一度もトップギアに到達したことがない状態でも、電流は流れ加速もするが
  カム位置だけが一切進段しない」という別の実機報告を受けた。`notch<2`・
  `direction=0`・`catenary_voltage_sw=0`など複数の仮説を`src/
  chuso1800_core.lua`直接呼び出しで検証したが再現せず、さらに
  「進段しない間の電流は210Aの限界より明らかに低い値で安定していた」
  との追加情報から、デバウンス条件自体は理論上満たされているはずと
  判明した。
- **切り分け**：`src/chuso1800_core.lua`のcore_tickへ、電流出力
  （`accel`）を`speed`へ毎tick積分で足し戻す「速度フィードバックを
  模した」シミュレーションを組んで実行したところ、**ソース
  （`src/chuso1800_core.lua`）は正常**にフル力行から15秒程度で直列→
  並列→界磁制御まで進段した。ところが同じシミュレーションを
  `deploy/chuso1800_deploy.lua`（minify後の実機投入版）へ与えると、
  並列進段直後（約5秒、速度1.4～2.4m/s）で速度が頭打ちになり、電流も
  ゼロへ向けて減衰し続け、二度と進段しないことを確認した──
  ユーザー報告と一致する現象。`lib/state_sync.lua`の2tick遅延
  自己ループ配線を正確に再現したハーネスでも同じ結果になり、
  `state_sync`統合の問題ではなく`core_tick`自体（正確にはそこから
  呼ばれる`physics_tick`）の問題と判明した。
- **原因の特定**：ソースと`deploy/chuso1800_deploy.lua`それぞれの
  `physics_tick`を同一入力で直接呼び出し数値を突き合わせたところ、
  1回の呼び出しだけで既に約0.047A（相対約0.03%）の差が生じており、
  これがtickを重ねるたびに拡大し最終的に致命的な乖離になっていた。
  `deploy/chuso1800_deploy.lua`内の該当関数（当時の`calc_ia`/
  `deriv_ia`に相当するminify後の独立local関数）を確認したところ：
  ```lua
  local function ab(a8,ac,a,ad,a7,a9)return a*a3(a6(a7,a8,a9))*a-ac+(c+ad)*a8 end
  ```
  引数リストの3番目が`a`という名前になっていた。ところがファイル冒頭の
  電動機定数`K`（=12.16）も同じスコープ階層でstorm-lua-minifyにより
  **同じ`a`という短縮名**を割り当てられていた（`local a=12.16`が
  ファイル内で最初に宣言されるlocalであるため）。この関数の中では
  パラメータ`a`（元は電動機回転数`n`）が外側の`K`を**シャドーイングして
  しまい**、ソースの`K * calc_phi(...) * n`（電動機定数×磁束×回転数）が
  `n * calc_phi(...) * n`（回転数の2乗×磁束）に化けていた。低速では
  `K*n`も`n²`もどちらも小さく差が目立たないが、速度が上がるにつれ
  前者は線形、後者は二次で乖離し、電機子電流のNewton法（5回の固定
  反復）が全く違う値へ収束してしまう。`K`をこの関数へ明示的な引数として
  渡す修正を試したところ、生成された引数リストに`a`が**2回出現する
  （`local function ab(a,a8,ac,a,ad,a7,a9)`）**という、より明白に不正な
  出力が確認され、単純な引数追加では回避できないstorm-lua-minify自体の
  リネームパスのバグ（複数の新規ローカルを一度に命名する際、外側スコープの
  既存の短縮名との衝突を確認していない）と判断した。npm本体の`luamin`
  についてはこの特定パターンでは未確認だが、#18の教訓（storm-lua-minifyは
  ユーザー自身が開発している別パッケージであり、根本修正はこのリポジトリの
  スコープ外）に倣い、ソース側の構造を変えて問題のパターンを避ける方針とした。
- **実機セーブによる裏付け**：ユーザーから提供された実機resave済みXML
  （`CHUSO1800 Traction Controller`マイクロプロセッサ）を確認したところ、
  実際に車両へデプロイされているLUAノードのスクリプト（object id=62）に、
  **一字一句同じ引数衝突パターン**（`local function a9(a6,aa,a,ab,a5,a7)
  return a*a1(a4(a5,a6,a7))*a-aa+(c+ab)*a6 end`、3番目の引数が`a`で
  電動機定数と衝突）が実在することを確認した。これにより、今回の
  診断が実機の症状と完全に一致することが実証された。なお、この実機
  セーブのスクリプトは`decode_state`が15値までしか返しておらず
  （`regen_delay_active`ビット19の読み出しが無い）、#21（回生遅延の
  ヒステリシス修正）より前の版がまだ実車に投入されたままであることも
  判明した──本PRの成果を含む最新の`deploy/chuso1800_deploy.lua`への
  再デプロイが必要。
- **修正**：どの独立local関数も`K`を自由変数として参照しないよう、
  電機子電流のNewton法（旧`calc_ia`/`deriv_ia`/`calc_current_phi`の
  3関数）を丸ごと`physics_tick`本体へ直接インライン化した。
  `physics_tick`はグローバル関数であり、その本体内で使われる`K`は
  実際にstorm-lua-minifyで問題なく処理されることを確認済み
  （同関数内の他の`K`使用箇所と同じ扱いになる）。独立local関数として
  括り出さないことで、このバグを誘発する「外側の短縮名と衝突する
  複数の新規ローカルを持つ独立local関数」というパターン自体を作らない。
  `calc_iF`/`deriv_iF`（それぞれ1行の式）も同様にインライン化し、
  `calc_phi`/`deriv_phi`（`K`を参照しない、`Kmu`/`Ks`/`PHIs`のみ参照）は
  そのまま独立関数として維持した（この2つは元々1引数のみで問題を
  起こしていなかった）。
- **修正後の確認**：`src/chuso1800_core.lua`と`deploy/
  chuso1800_deploy.lua`の`physics_tick`を同一入力で直接突き合わせ、
  ビット単位で完全一致することを確認した。速度フィードバックを模した
  20秒間のシミュレーションを`deploy/chuso1800_deploy.lua`へ通しても、
  ソースと完全に同じ軌跡（フル力行で約10秒後に並列進段、以降も速度上昇
  継続）を再現した。
- **テスト**：`test/verify_deploy_artifact.lua`に新しい検証を追加。
  `deploy/chuso1800_deploy.lua`自身の出力（`accel`）を自身の速度入力へ
  毎tick積分で足し戻す20秒間のシミュレーションを実行し、フル力行で
  並列（`phase2_latch`）へ到達することを確認する（このバグが再発すれば
  検出できる）。`test/run_all.lua`側の既存15シナリオは元々ソース直読みの
  ため無関係・無回帰。
- **影響箇所**：`src/chuso1800_core.lua`（`physics_tick`：`calc_ia`/
  `deriv_ia`/`calc_current_phi`/`calc_iF`/`deriv_iF`を削除しインライン化）、
  `deploy/chuso1800_deploy.lua`（`node build.js`で再生成）、
  `test/verify_deploy_artifact.lua`（新規の速度フィードバック検証を追加）。

## #25 `momelink_advanced_frame`の`count=1`により、Momelink-A出力の
大半（自車平滑加速度・電機子電流・牽引供給電圧・BC目標・車両質量・
Type ID）が一切送出されていなかった不具合を修正

- **経緯**：ユーザーから「Momelink-A用加速度をうまく出せていないのでは」
  との指摘を受けて`main.sw-net`を調査した。
- **原因**：`momelink_advanced_frame`（`COMPOSITE_WRITE_NUMBER`）が
  ```
  inst COMPOSITE_WRITE_NUMBER momelink_advanced_frame (count=1, offset=1) :
    in1=bc_application_ratio_out, in2=inner_unit_acceleration_out,
    in15=momelink_type_id_1911_value, in22=vehicle_mass_tonnes_value,
    in23=traction_supply_voltage_out, in24=armature_current_out,
    in25=bc_target_abs_pressure_out, in26=model_acceleration_smoothed_out
    -> out=momelink_advanced_frame_out
  ```
  という配線になっていた。`COMPOSITE_WRITE_NUMBER`は`count`個の入力
  （`in1`～`in count`）だけを実際に読み、それ以外の`in`キーは
  ノードの実体として存在しない（Stormworks実機のノードUIは`count`個の
  ソケットしか持たない）。`count=1`のため実際に書き込まれるのは
  `in1`（`bc_application_ratio`、BC作動比）だけで、`in2`
  （自車平滑加速度の1800形上書き元となる`inner_unit_acceleration`）・
  `in15`（Type ID）・`in22`（車両質量）・`in23`（牽引供給電圧）・
  `in24`（電機子電流）・`in25`（BC目標絶対圧）・`in26`（自車平滑加速度、
  新SPEC.md §13.2）は**すべて無視され、`momelink_advanced_frame_out`に
  一切反映されていなかった**（`tools/sw-net-sim/sim.lua`の
  `EVAL.COMPOSITE_WRITE_NUMBER`実装で`for i=1,count`のループ範囲外に
  なることを確認、`storm-microcontroller-language`の
  `parseSwNetDocument`もこの`count`属性をそのまま保持する）。
  この`momelink_advanced_frame_out`は`status_data_source`経由で
  `status_bc_target`（`"BC target [atm]"`出力ポート）・
  `status_armature_current`（Rolling Stock Status N3）・
  `status_catenary_voltage`（同N5）にも使われているため、**影響は
  Momelink-Aの加速度だけでなく、`BC target [atm]`出力・Rolling Stock
  Statusの電機子電流／牽引供給電圧フィールドにも及んでいた**（いずれも
  常時0）。`momelink_1800_frame`（1800形フレーム、`count=2`で`in1`/`in2`
  のみ上書きし残りは`inc=momelink_advanced_frame_out`から継承）経由の
  実際の`"Momelink-A"`出力も、継承元が空である以上同じ影響を受けていた。
- **他ファイルとの突き合わせ**：ユーザー指示に従い
  `CHUSO1800_Traction_Controller/SPEC.md` §13.2/13.3と
  `CHUSO1800_Traction_Controller_main_renamed.sw-net`（無印側の再検証版）
  を参照したところ、**無印側にも一字一句同じ`count=1`の不整合**
  （`momelink_advanced_frame`）があり、さらに無印の未リネーム
  オリジナル`CHUSO1800_Traction_Controller/main.sw-net`（`momelink_1900_out`）
  にも同型の不整合が存在した。加えて、ユーザーが提供した実機resave済み
  XML（`CHUSO1800_Traction_Controller_LuaCore`、#24で使用したものと同じ
  ファイル）を`storm-mcl xml2dsl`で変換して確認したところ、実際にゲーム内へ
  デプロイされているノード（変換後の`n82`）も**`count=1, offset=1`で
  `in1`しか配線されていない**（`in2`以降のワイヤ自体が実機データに
  存在しない）ことを確認した。つまりこの不具合はLuaコア移植や本セッションの
  リネーム作業で入ったものではなく、**原稿・無印・実機デプロイ済みの
  いずれにも元から存在する不具合**であり、`main.sw-net`のテキストDSL側で
  `in2`以降を後から書き足した際（新SPEC.md §13.2に合わせてChatGPTとの
  再検証で追記されたと推測される）に`count`を追従させ忘れたものと考えられる。
- **修正方針**：README.mdの既存方針
  （`CHUSO1800_Traction_Controller/`配下は一切変更しない）に従い、
  `CHUSO1800_Traction_Controller_LuaCore/main.sw-net`側のみ`count`を
  `1`から`26`（`in26`まで配線されているため）へ修正した。無印側
  （`CHUSO1800_Traction_Controller/`）に同じ不具合が存在する旨はユーザーへ
  報告済みだが、本PRのスコープ外として無変更のままにしてある。
  未配線のチャンネル（3-14, 16-21）はSPEC.md §13.2で「現状未消費」
  扱いのままであり、`count`を広げても未接続入力はSPEC.md §2の規約通り
  0がそのまま出力されるだけで実害はない。
- **確認**：`storm-mcl typecheck-dsl`で構文確認、`tools/sw-net-sim`で
  修正後の`main.sw-net`を再ビルドして実際にtick実行し、フル力行後の
  `"Momelink-A"`コンポジット出力を検査した結果、N1（BC作動比）・
  N2（1800形上書き後は自車加速度、Advanced生値では`Momelink inner unit`
  ch26のパススルー）・N15（Type ID=1911）・N22（車両質量=35）・
  N23（牽引供給電圧=1500）・N24（電機子電流≈200）・N25（BC目標絶対圧）・
  N26（自車平滑加速度、SPEC.md §13.2の主対象）が**すべて正しく出力される**
  ことを確認した。同時に`"BC target [atm]"`出力ポートおよび
  `"Rolling Stock Status"`のN3（電機子電流）・N5（牽引供給電圧）も
  連動して正しい値になることを確認した。`main.sw-mcl`は
  `storm-mcl layout-dsl --force`で再生成したが、レイアウトは`count`属性に
  依存しないため既存コミットと完全に同一（差分なし）だった。
  `src/chuso1800_core.lua`・`deploy/chuso1800_deploy.lua`は無変更のため
  `test/run_all.lua`（15/15）・`test/verify_deploy_artifact.lua`（2件とも
  pass）は無回帰。
- **影響箇所**：`CHUSO1800_Traction_Controller_LuaCore/main.sw-net`
  （`momelink_advanced_frame`の`count`修正1行）、`SIGNAL_MAP.md`
  （stateless_out slot3の説明を実態＝Momelink ch2/26向けへ訂正）。
  比較検証に使ったsw-net-simハーネスはスクラッチパッドの使い捨て。

## #26 #23の固着解除ロジックが`DB自動`ON時に直列を誤ってSETし、
カムが高速域のノッチオフで勝手に前進する回帰バグを修正

- **経緯**：ユーザーから「高速域でノッチオフするとカムが前進してしまい、
  直列界磁（phase1_latch＋regen_latch同時ON）まで進段してしまう。再力行は
  並列初段からやり直しになる。固着解除ロジックが誤って発動していないか」
  との報告を受けた。
- **再現と切り分け**：フル力行から速度フィードバックを模したシミュレーション
  でカム位置0・並列＋界磁制御まで到達させ、notchを0に落として`regen_flag`
  （Simple IF B18＝DB自動）をONにしたまま放置したところ、約50tick後に
  `phase1_latch`が誤ってtrueになり、以降`phase1_regen_active`
  （`phase1_latch and notch_fb_ne14 and regen_latch`）が`traction_any_active`
  を持ち上げ続け、notch=0のままカムが0→1→2→…と際限なく進段することを
  確認した。ユーザー報告と完全に一致する現象。
  - **切り分け時の失敗**：当初`sap_pressure_sw=5`を「ゲート側解決済みの
    最終値」として直接与えて再現を試みたが、これは実際には強い回生
    ブレーキ要求（`low_bc_with_regen_flag=true`、ECBモードでの1atm≈無制動
    という前提を誤って無視した値）を注入してしまっており、`stuck_at_top_idle`
    ではなく既存の`field_current_excess`（界磁電流300A超過、SPEC.md
    §7.5）の方が実際の引き金になっていた（この経路は#23より前の
    セッション開始前ベースラインでも同様に発生し、本セッションの変更とは
    無関係）。`sap_pressure_sw=1.0`（無制動の解決済み値）に修正して
    再テストしたところ、`regen_flag=false`では正しく中立へ解放される一方、
    `regen_flag=true`のときだけ`phase1_latch`が誤ってSETされることを確認し、
    これが#23で追加した`stuck_at_top_idle`固有のバグであると確定させた。
- **原因**：#23の実装は`stuck_at_top_idle`を既存の
  `field_current_excess_cond`→`field_current_excess_pulse`チェーンへ
  合流させていた。この`pulse`は`phase1_set`
  （`field_current_excess_pulse and phase2_latch`、並列→直列降格用、
  SPEC.md §7.5）へも**無条件に**配線されており、「なぜpulseが発火したか」
  を区別しない。一方`phase_reset_cond`（`coasting_cond or
  (field_current_excess_pulse and (not regen_flag))`）は、`regen_flag`
  （DB自動）がONの間はpulse由来の項が`not regen_flag`で無効化される
  設計になっている。このため`regen_flag=true`の間に`stuck_at_top_idle`が
  pulseを発火させると、同tickで`phase1_set`はマスクされずに素通りする
  一方、`phase_reset_cond`（延いては`phase1_reset`）は
  `coasting_cond`（`not regen_latch`を要求、まだ固着中でtrue化できない）も
  他の項も不成立のためfalseのまま──`phase1_set=true`かつ
  `phase1_reset=false`という非対称な組み合わせになり、直列が
  **マスクされずに実際にSETしてしまっていた**。
- **修正**：`stuck_at_top_idle`を`field_current_excess_cond`/`pulse`
  チェーンから完全に切り離し、`phase_state_machine`内で直接計算した上で
  `phase2_reset`へのみ`or`で合流させた（`phase1_set`には一切経路を
  持たせない）。判定式自体は`current_near_zero(motor_current) and
  not(notch_ge1 or low_bc_with_regen_flag)`という既存の`neutral_cond`
  （`coasting_cond`と共用）をそのまま再利用しており、`regen_flag`の値に
  一切依存しない（これにより`regen_flag`がON/OFFいずれでも同じ経路で
  中立へ解放される）。`regen_latch`自身のリセットは既存の
  `traction_all_off`経由で1tick遅れて追従する（`coasting_cond`駆動の
  通常解放と同じタイミング挙動）。`field_current_excess_block`は
  #23以前の元の6引数シグネチャへ戻し、`stuck_at_top_idle`関連の引数
  （`phase2_latch`／`regen_latch`／`notch_fb_ge1`／`motor_current`／
  `low_bc_with_regen_flag`）は不要になったため削除した。
- **確認**：上記の`sap_pressure_sw=1.0`・`regen_flag=true`シナリオを
  修正後コードで再実行し、`phase1_latch`が一切trueにならないまま
  `phase2_latch`／`regen_latch`が正しく中立へ解放され、カム位置も0の
  ままであることを確認した。`test/run_all.lua`（15/15）・
  `test/verify_deploy_artifact.lua`（2件とも pass）で無回帰を確認した。
- **教訓**：`field_current_excess_pulse`のような「複数の意味を持つ
  共有パルス」に新しい発火条件を安易に合流させると、その pulse を
  消費する**すべての**下流ロジック（このケースでは`phase1_set`）に
  意図しない影響が及ぶ。#22で発見した「co-onマスキング」もこの
  同じ共有pulseの副作用の一種であり、今回のバグもその類縁。今後
  同様の共有パルスへ新条件を追加する場合は、まず「そのpulseを
  消費する全ての下流項」を洗い出し、新条件がそれぞれに対して
  意図通りかを個別に確認すること。
- **テスト**：`test/scenarios/stuck_at_top_of_ladder_recovery.lua`に
  新しいケース（`regen_flag=true`・無制動での固着解除が直列を
  誤ってSETしないこと、正しく中立へ解放されカム位置も不変であること）
  を追加し、ヘッダコメントに本エントリへの改訂履歴を追記した。
- **影響箇所**：`src/chuso1800_core.lua`（`field_current_excess_block`を
  元のシグネチャへ復元、`phase_state_machine`に`stuck_at_top_idle`を
  移設）、`deploy/chuso1800_deploy.lua`（`node build.js`で再生成、
  7,488文字＝8192文字制限内）、
  `test/scenarios/stuck_at_top_of_ladder_recovery.lua`（新規ケース・
  ヘッダコメント更新）。

## #27 `stuck_at_top_idle`（#26）が高速巡航中の通常の惰性走行でも
即座に発火し、並列＋界磁制御の状態を毎回破壊する回帰バグを修正

- **経緯**：#26マージ後、ユーザー指定の実運転想定シナリオ（フルノッチ
  加速→ノッチオフ→惰性→再加速…という一連の流れをクローズドループ
  シミュレーション──`physics_tick`自身の出力`accel`/`bcT`を毎tick
  速度へ積分で足し戻す──で検証）のうち、「60km/hまでフルノッチ加速、
  ノッチオフ→10秒惰性→85km/hまで再加速（カム回転なしを期待）→20秒
  惰性→SAP 4atmで制動（回生→回生終了を期待）」というシナリオで、
  再加速時にカムが並列初段からフルで登り直す（`expect_cam_static`
  違反21件）現象と、最終制動フェーズで回生が一切発生しない
  （`regen_latch`が終始false、電流0A、空気ブレーキのみの`bcT`一定値）
  現象の両方を確認した。ユーザーからも「約40km/h以上で惰性中は、
  界磁制御モードによって電機子電流が0Aになるよう制御されるモードです」
  という仕様確認があり、この状態（並列＋界磁制御・電流0A）こそが
  高速惰性走行での**正しい定常状態**であり、それを毎回失うことがバグだと
  確定した。
- **原因**：#26の`stuck_at_top_idle`は`neutral_cond`
  （`current_near_zero(motor_current) and not(notch_ge1 or
  low_bc_with_regen_flag)`）だけを条件にしていた。しかし
  `neutral_cond`は速度を一切見ておらず、界磁制御自体がノッチオフ後
  数秒で電機子電流を0A近辺へ収束させる（＝ユーザー確認済みの正常
  動作）ため、60km/hのような通常の巡航速度で数秒惰性走行しただけで
  `neutral_cond`が真になり、`stuck_at_top_idle`が発火して
  `phase2_latch`/`regen_latch`を中立へ解放してしまっていた。#23の
  バグ報告が本来指していたのは「ほぼ完全に停止した状態で、並列の
  全短絡ステップ（`PR[1]=0Ω`）に固着したまま動けなくなる」ケースだけ
  だったが、#26の条件はそれより遥かに広い「巡航中の一時的な電流ゼロ」
  も等しく拾ってしまっていた。
- **検討した代替案**：ユーザーから「速度条件ではなく界磁電流条件と
  すべきでは」「正確には予想される界磁電流条件では」という提案が
  あったが、条件の詳細（どの閾値を使うか、実際に再接続した場合の
  予測電流をどう計算するか等）を詰める前にユーザー自身が撤回し、
  「Claudeさんの計画通り進めてください」と当初案（速度条件）の続行を
  指示された。
- **修正**：`STUCK_RELEASE_SPEED_THRESHOLD = 3`（m/s）という定数を
  新設し、`phase_state_machine`に`speed`を追加の引数として渡した上で
  `stuck_at_top_idle`の条件に`math.abs(speed) < STUCK_RELEASE_SPEED_
  THRESHOLD`を`and`で追加した。閾値は、並列の全短絡ステップへ
  再接続した場合の電流を診断的に速度掃引した結果（8m/s以上では
  定常電流が自己制御域（約200A、`POWER_LIMIT_CURRENT`未満）へ収束する
  ことを確認）に基づき、それより十分低い値として選んだ──「巡航中の
  短い惰性走行では絶対に解放しない」ことを優先した保守的なマージン。
- **確認**：`test/run_all.lua`・`test/verify_deploy_artifact.lua`を
  再実行して無回帰を確認した上で、上記の実運転シナリオを修正後コードで
  再実行し、再加速時のカム回転が解消されたことを確認した（回生の
  完全な確認は#28修正後、後述）。
- **教訓**：「電流がほぼゼロ」は「停止している」の十分条件ではない
  ──界磁制御を持つ車両では、走行中でも意図的に電流をゼロへ制御する
  モードが存在しうる。状態解放の条件に電流ゼロだけを使うと、その
  正常モードを異常（固着）と誤認する。速度（または「本当に再接続の
  危険がある状況か」を直接表す別の物理量）を必ず組み合わせること。
- **影響箇所**：`src/chuso1800_core.lua`（`STUCK_RELEASE_SPEED_
  THRESHOLD`定数を新設、`phase_state_machine`に`speed`引数を追加、
  `stuck_at_top_idle`に速度条件を追加）、`test/scenarios/stuck_at_top_
  of_ladder_recovery.lua`（idle解放系サブテストの前提を「本当に
  ほぼ停止」寄りに調整、高速巡航中は解放されないことを検証する
  新規ネガティブケースを追加）。

## #28 `field_current_excess_pulse`経由の`phase_reset_cond`も同じ理由で
高速巡航中に並列＋界磁制御を破壊していたことが判明、`near_stop`
条件を共有して修正

- **経緯**：#27の速度条件を検証する過程で、`stuck_at_top_idle`とは
  別に、`phase_reset_cond`が持つ`field_current_excess_pulse and
  (not regen_flag)`という**#23より前から存在する**既存の項も、通常の
  高速巡航中に発火して並列＋界磁制御を中立へ全解放してしまうことを
  発見した。速度15m/s→0m/sへ30秒かけて緩やかに減速させる診断
  シミュレーションで、`stuck_at_top_idle`が速度条件でブロックされている
  （`near_stop`=false）にもかかわらず、速度9.275m/s・電流8A程度という
  「明らかに巡航中で全く危険でない」状態で並列(phase2)・界磁制御(regen)
  が両方とも中立へ落ちることを確認し、`DEBUG_TRACE`一時計装で
  `field_current_excess_pulse=true`かつ`phase_reset_cond=true`が
  同tickで発火していることを特定した。
- **原因**：`field_current_excess_block`が算出する`iF_a`
  （界磁電流相当値）の更新式は、`notch_ge1=false`（ノッチオフ）の
  coasting分岐で`target_i`を`math.max(math.min(0, OLD_I + 20),
  OLD_I - 20)`とクランプしており、`OLD_I`（電機子電流）が正である限り
  常に`target_i=0`になる。このため`iF_a = OLD_IF_A + (OLD_I -
  target_i) * 0.1 = OLD_IF_A + OLD_I * 0.1`となり、**電機子電流が
  どれほど小さくても正である限りiF_aは際限なく増加し続ける**。並列の
  全短絡ステップ（`PR[1]=0Ω`）に接続されたまま速度が下がっていく
  巡航シナリオでは、逆起電力の低下に伴い電機子電流がわずかずつ
  増え続けるため（速度9.275m/sの時点でもまだ8A程度）、`OLD_I`が
  完全に0へ収束しない限りこの上昇は止まらず、走行開始から数秒〜
  十数秒後には必ず`BRAKE_LIMIT_300`（300A）を超えて
  `field_current_excess_pulse`が発火する。この`pulse`が
  `phase_reset_cond`の`(not regen_flag)`項を素通りすると
  （`regen_flag`＝DB自動がOFFの間）、`coasting_cond`を経由せず
  直接、並列＋界磁制御を中立へ全解放してしまう──#27で修正した
  `stuck_at_top_idle`とは別経路で、同じ「巡航中の正常な0A制御状態を
  誤って破壊する」症状を引き起こしていた。ユーザーからの
  「惰性走行中は、すべてつなげた状態で、界磁制御によって電機子電流を
  0Aに保つのがこの車両の制御上の特徴です」という確認により、この
  巡航中の全解放が仕様違反であることが確定した。
- **修正**：`stuck_at_top_idle`と`phase_reset_cond`の両方で使う
  `near_stop = math.abs(speed) < STUCK_RELEASE_SPEED_THRESHOLD`という
  共有ローカル変数を導入し、`phase_reset_cond`の
  `field_current_excess_pulse and (not regen_flag)`項に`and
  near_stop`を追加した。これにより、`regen_flag=false`での
  「界磁電流超過→中立へ全解放」という既存の降格ショートカットは
  「本当にほぼ停止していて再接続の危険がある」場合（#23の元々の
  バグ報告が指していた状況）だけに限定される。巡航中に
  `field_current_excess_pulse`が発火した場合は、`phase1_set`の
  `field_current_excess_pulse and phase2_latch`項だけが素通りし、
  `phase1_reset`側はこの項からは発生しなくなるため、SPEC.md §7.5が
  本来意図する「並列→直列への正しい降格」（`phase2`は次tickに
  `phase1_latch and not(...)`項経由で自然にリセットされる）が
  `regen_flag`の値に関わらず一貫して起こるようになった──ユーザーの
  指示「速度条件での界磁制御モード解放が優先されるようにしてください」
  と、実運転シナリオ3・4が想定する「外部抵抗による緩やかな減速で
  直列界磁制御へ切り替わる」という仕様の双方に合致する。
- **確認**：同じ速度掃引診断で、9m/s付近において以前の「中立への
  全解放」ではなく「並列→直列（Series）への正しい降格」（カムが
  直列の抵抗表を登りながら進段）に変わったことを確認した。
  `test/run_all.lua`（15/15）を再実行し、本修正で前提が崩れた
  `field_current_excess_pulse_reset_masking.lua`（#22由来、
  `regen_flag=false`時のマスキングは`near_stop`時のみ有効という
  前提へ更新）・`stuck_at_top_of_ladder_recovery.lua`（DB自動系
  サブテストを、巡航速度で`stuck_at_top_idle`自体が`phase1_set`へ
  漏れていないことだけを検証する形へ整理）を更新して無回帰を確認した。
  ユーザー指定の実運転シナリオ2（60km/h加速→10秒惰性→85km/h再加速
  →20秒惰性→SAP4制動）を再実行し、`expect_cam_static`違反が0件、
  かつ最終制動フェーズで速度31km/h付近から回生ブレーキが正しく作動し
  （電流が負に転じ`accel`がマイナス、カムが直列抵抗表を登りながら
  減速）、13km/h付近で回生が正しく終了する（空気ブレーキのみへ
  切り替わる）ことを確認した。
- **教訓**：#27と同型のバグが、`stuck_at_top_idle`という単一の新設
  ロジックだけでなく、**既存の**`field_current_excess_pulse`消費経路
  にも独立に存在していた。「電流に基づく判定は、電流を押し上げる
  側の式（ここでは`iF_a`の更新式）が本当に有界か」を確認しないと、
  一見無関係な既存ロジックが同じ落とし穴（巡航中の正常状態を異常と
  誤認）にはまる。速度条件（`near_stop`）を`phase_state_machine`内の
  共有ローカルへ切り出したことで、今後同種の「本当にほぼ停止している
  ときだけ許可すべき」ロジックを追加する際の再利用点にもなる。
- **影響箇所**：`src/chuso1800_core.lua`（`near_stop`共有ローカルを
  導入、`phase_reset_cond`の`field_current_excess_pulse`項に
  `near_stop`を追加）、`test/scenarios/field_current_excess_pulse_
  reset_masking.lua`（`regen_flag=false`時の期待値を`near_stop`の
  有無で分岐、巡航速度でのSeries正常降格を検証する新規ケースを追加）、
  `test/scenarios/stuck_at_top_of_ladder_recovery.lua`（DB自動系
  サブテストを巡航速度基準へ再構成）。

## #29 PR #7レビューコメントによる2件の安全要件を追加：非常制動時の
無条件全解放、DB自動OFF中の直列界磁制御の禁止（#28の前提を一部修正）

- **経緯**：PR #7に対するリポジトリオーナー（実機のドメイン専門家）から
  のレビューコメントで、以下2件の安全要件が明示的に追加された。
  1. 「非常制動条件を受けたら無条件で界磁制御フラグを倒してください。
     ノッチオフ時の急加速防止が目的です」
  2. 「『ダイナミックブレーキ自動』フラグが倒れている/倒れたとき、直列
     界磁制御への移行中/開始、直列界磁制御中のいずれかであれば、界磁
     制御フラグを倒し、架線-モータ間を開放してください。これも運転士が
     意図しない加速を防止するためです」
- **要件1の実装範囲の検討**：要件1を文字通り「界磁制御ラッチ
  (`regen_latch`)だけを倒す」と実装すると、`phase2_latch`（並列）は
  ラッチされたままになる。この状態でEB解除後にnotchを再投入すると、
  `phase1_set`の`power_with_regen and (not phase2_latch)`項が
  `phase2_latch`でブロックされ、直列（抵抗あり）を経由せず並列の現在の
  カム位置（低抵抗〜全短絡）へ直結してしまう──#23が元々問題にした
  「低速で抵抗ゼロへ再接続し電流が跳ね上がる」危険パターンと同型になる。
  ユーザーに確認したところ「phase1/phase2/regenを全解放（架線-モータ間
  を完全開放）」が意図どおりであることが確認された。
- **要件2の実装方針の確認**：要件2は#28で「`field_current_excess_pulse`
  経由のParallel→Series降格は`regen_flag`に関わらず正しく発生すべき」と
  した変更の前提を覆す。ユーザーへ改めて説明を試みたところ、こちらが
  使った用語（"gate"・"phase"等、sw-net由来の語彙）が伝わらなかったため、
  無印`CHUSO1800_Traction_Controller/SPEC.md`（ユーザー自身の語彙に近い、
  GPTが起こした仕様書）を読み直して裏付けを取った。§7.5に次の記述がある：
  「ノッチOFF時に界磁電流が選択閾値を超えると、0.1秒ON／0.4秒OFFの周期
  パルスを生成する。このパルスは並列から直列への切替、直列の解除、または
  DB自動OFF時の接続解除に使用される。」──すなわちこのパルスの働きは
  DB自動の状態で分岐する（ON: 直列へ切替／OFF: 接続解除）ことが原典の
  時点で明記されており、#28の「`regen_flag`に関わらずSeriesへ降格」は
  誤りだったと確定した。
- **原因**：#28は、`near_stop`（ほぼ停止状態）の速度条件を`phase_reset_
  cond`の`field_current_excess_pulse and (not regen_flag)`項に追加して
  「巡航中はDB自動OFFでも中立へ全解放されない」ようにしていた。しかし
  正しくは、DB自動OFF中に直列界磁制御へ入る／留まること自体が「運転士が
  意図しない加速」のリスクであり、速度に関わらず接続解除すべきだった。
- **修正**：
  1. `phase_reset_cond`から`near_stop`条件を削除し、`field_current_
     excess_pulse and (not regen_flag)`を無条件（#28以前の挙動）へ戻した。
  2. `phase1_set`の`field_current_excess_pulse and phase2_latch`項に
     `regen_flag`を追加し、パルスによるParallel→Series降格そのものを
     DB自動ON時限定にした（これにより上記1のリセット項と競合しなくなり、
     DB自動OFF時はSR優先順位に頼らず構造的にSeriesへ入れない）。
  3. `phase_state_machine`に`eb_condition`を新規引数として渡し、
     `phase1_reset`/`phase2_reset`/`regen_latch`のリセット条件すべてに
     `eb_condition`をOR項として追加（要件1：非常制動時の無条件全解放）。
  4. `db_auto_off_in_series_field_control = (not regen_flag) and
     phase1_latch and regen_latch`という毎tick監視する条件を新設し、同様に
     3つのリセット条件へOR項として追加（要件2：DB自動が運転中にOFFへ
     切り替わった場合も含めて継続的に監視・解放する）。
- **確認**：新規テスト`test/scenarios/eb_and_db_auto_off_force_disconnect.
  lua`で、(a) 並列＋界磁制御の「固着」状態から巡航速度でEBを受けたら
  即座に全ラッチが解放されEB継続中は解放され続けること、(b) 直列界磁
  制御中にDB自動がOFFへ切り替わったら次のtickで即座に全ラッチが解放
  されること、(c) DB自動ONの直列界磁制御はこの修正で意図せず解除されない
  こと、をそれぞれ確認した。既存の`field_current_excess_pulse_reset_
  masking.lua`は、`regen_flag=false`が速度に関わらず常に中立へマスクされる
  よう更新した（#28の`near_stop`限定を撤回）。ユーザー提案の実運転
  シナリオ2〜4・6（回生が発生する想定のもの）は、いずれも`db_auto=true`
  を明示しないと本来SPEC.md §7.5の意味で回生が発生しえないことが判明した
  ため、全て`db_auto=true`を設定するよう修正した（シナリオ1・5は回生を
  伴わないため変更不要）。`test/run_all.lua`（22/22）・`test/verify_
  deploy_artifact.lua`（2件ともpass）で無回帰を確認した。
- **教訓**：#28は「ユーザーの実運転シナリオでの検証」という強い裏付けが
  あったが、それでも実装の勢いで`regen_flag`という既存の安全条件を
  安易に無効化してしまった。ドメイン固有の安全要件（本件では「DB自動が
  運転士の明示的な同意を表す」という設計思想）は、動作ログや物理
  シミュレーションだけでは検出できず、原典の仕様書やドメイン専門家の
  レビューでしか裏付けが取れない場合がある。またコミュニケーション面
  でも、自分（Claude）が採用した独自の説明語彙（"gate"・"phase"等）が
  ユーザー本来の語彙とズレていたため、原典SPEC.mdの言葉遣いに立ち返る
  ことで初めて正確な意思疎通ができた。今後、状態機械の安全条件について
  ユーザーと認識を合わせる際は、まず既存の一次資料（SPEC.md等）の語彙を
  優先して使うこと。
- **影響箇所**：`src/chuso1800_core.lua`（`phase_state_machine`に
  `eb_condition`引数を追加、`phase_reset_cond`の`near_stop`を削除、
  `phase1_set`に`regen_flag`を追加、`db_auto_off_in_series_field_control`
  を新設し3つのリセット条件へ合流）、`deploy/chuso1800_deploy.lua`
  （再生成、7,617文字＝8192文字制限内）、`test/scenarios/eb_and_db_auto_
  off_force_disconnect.lua`（新規）、`test/scenarios/field_current_
  excess_pulse_reset_masking.lua`（`regen_flag=false`の期待値を無条件
  マスクへ更新）、`test/scenarios/realistic_scenario_{2,3,4,6}_*.lua`
  （`db_auto=true`を明示するよう更新）、`test/run_all.lua`（新規テスト
  登録）。
