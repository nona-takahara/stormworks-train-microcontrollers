# CHUSO1800 Lua Core（プロトタイプ）

`CHUSO1800_Traction_Controller` の制御ロジックのうち状態機械・タイマー・
ノッチ処理・BC平滑化と、既存の電流物理演算（`scripts/n409.lua`）を、
**1つの純関数Luaモジュール**（`src/chuso1800_core.lua`）に統合した
スタンドアロンのプロトタイプです。

- **`CHUSO1800_Traction_Controller/` 配下のファイルは一切変更していません。**
- `main.sw-net` へのLUAノード配線差し替え自体はまだ行っていません
  （`script_ref`をどう向けるかはゲート網側の作業のため）。ただし
  Stormworksへそのまま貼り付けられる状態のデプロイ用スクリプトは
  `deploy/`に用意済み（「デプロイ（実機組み込み用スクリプト）」参照）。
- Stormworks実機なしで、素の `lua` インタプリタだけでテストできます（「テスト」参照）。

### ドキュメントの読み方

| ファイル | 役割 |
|---|---|
| このREADME | 概要・契約・設計判断（現在の姿） |
| [`SIGNAL_MAP.md`](./SIGNAL_MAP.md) | 全信号→スロット/ビット割付の**一次情報源** |
| [`DESIGN_LOG.md`](./DESIGN_LOG.md) | 「なぜそうなったか」の意思決定ログ（当初案と変更経緯） |
| `../CHUSO1800_Traction_Controller/SPEC.md` | 元のゲート網の仕様。本文中の `§x.y` はこれを指す |
| `../../lib/state_sync.lua` | リポジトリ共通の汎用ステート同期ドライバ（本モジュール専用ではない） |

## スコープ：Lua化したもの／ゲート側に残したもの

**Lua化した範囲**（本モジュールが実装）：

- phase1/phase2/regen の状態機械（SRラッチ、§3.6）
- カム進段・ホーミング（`position_counter`、§3.2）
- ノッチ処理（`notch_eff`/`notch_ge*`、§3.3）
- 力行カット条件（`eb_condition`、§3.5）
- BC/回生BC平滑化と回生遅延タイマー（§3.8）
- 電流物理演算（`n409.lua` のNewton法を逐語移植）

**ゲート側に残した範囲**（本モジュールは関知しない）：

- パンタグラフ4ラッチ一式（§3.9）。本モジュールはExtended IFのパンタ関連
  信号も `property.getBool("M type")` も一切参照しない
- 架線電圧セレクタ一式（`panta*_1800_active` はゲート側計算値をそのまま使う）
- SAP/ECBブレーキ圧解決と direction 合成（「入力の前提」参照）
- Momelink-A整形／Rolling Stock Status整形／`bc_target_read`

パンタグラフ以外はステートレスなデータ整形・muxが中心で、Lua化しても
得るものが少ない箇所。該当ノードの一覧は `SIGNAL_MAP.md` の
「ゲートに残すもの」節を参照。パンタグラフをゲート側に残した経緯は
`DESIGN_LOG.md` #2 を参照。

## 契約（インターフェース）

```lua
local core = require("chuso1800_core")
local stateless_out, state_out = core.calculateTick(stateless_in, state_in)
```

- `stateless_in`・`stateless_out`：Lua数値の配列 `[1..8]`。現在tickの
  センサ値相当の入力／現在tickの出力。
- `state_in`・`state_out`：Lua数値の配列 `[1..8]`。`state_out` はそのまま
  次tickの `state_in` として自己ループで戻ってくる。
- 制御状態の保持にLuaの永続グローバル変数は一切使用しない。tickをまたぐ値は
  すべて `state_in`/`state_out` に収めてあり、そのおかげでStormworksの
  `input`/`output` をモックせずに素の `lua` からテストできる。
- 各スロットは生のdoubleか、`to_u32`/`get_bits`/`put_bits`/`get_bit`/`put_bit`
  （`string.pack("I4",...)` ベース、`src/chuso1800_core.lua` 内に直接定義）
  でビット位置ごとに直接組み立て・分解する32bit整数のどちらか。後者で複数の
  bool・小整数を1スロットに同居させる。
- **ファイルは単体で完結している（`require` なし）**。Stormworksには
  モジュール読み込み機構がないため、そのままLUAノードに貼り付けられる形を
  維持すること（経緯は `DESIGN_LOG.md` #1）。

## tickモデル

sw-net の字面通りのモデル（SPEC.md §0.2）では全ゲート出力が1tick遅延するが、
それを再現すると中間信号ごとにステートスロットが必要になり8本に収まらない。
そこで本モジュールは：

- **真にtickをまたぐもの**（SRラッチ、デバウンス/タイマーCAPACITOR、
  周期パルス、電流物理の準ステート、BC平滑化）だけを遅延ありとして扱う。
  今tickの判断には `state_in` の古い値を読み、新しい値を `state_out` に書く。
- **それ以外**（ノッチ処理、力行カット条件、BC目標値の式など）はすべて
  純粋な組合せ論理として、1回の `calculateTick` 内で完結させる。

この「同tick内への圧縮」はSPEC.md自身が§0.2末尾で許容しているもの
（過渡のtick数は短縮されうるが、定常状態の結論は不変）。既知の帰結として、
SPEC.md のH7（カムのオーバーシュート）はゲート段の追加遅延1tickに依存する
現象であり本モデルでは再現しない。これは黙って見過ごさず
`test/scenarios/h7_cam_overshoot_homing.lua` で明示的に検証・記述している。

### コードの構成

`src/chuso1800_core.lua` は、ゲート名を同名ローカル変数へ機械置換した
1枚の巨大関数にはしていない。SPEC.md §3.x 各節にほぼ対応する小関数
（`eb_and_brake_pressure`／`notch_and_cam_feedback`／`brake_demand`／
`debounce_block`／`field_current_excess_block`／`phase_state_machine`／
`advance_cam`／`smooth_bc` 等）に分割し、`calculateTick` はそれらを
順に呼び出すオーケストレータ。観測される挙動はこの分割で変わらない
（純粋なリファクタリング）。

これら小関数（および`physics_tick`/`decode_state`/`encode_state`/
`encode_stateless_in`/`decode_stateless_out`）は、名前付きテーブルでは
なく**位置引数・多値返却**でやり取りする。storm-lua-minifyはローカル変数・
関数名は短縮できてもテーブルのキー文字列（`t.field_name`のような形）は
短縮できないため、名前付きテーブルを多用するとStormworksの8192文字制限を
圧迫する（経緯・実測値は `DESIGN_LOG.md` #13）。可読性は当然下がるので、
各関数の直前に引数・戻り値の順序を説明するコメントを付けてある。テスト側は
`test/harness.lua`の名前付きテーブル変換ラッパー（`encode_state`/
`decode_state`等）経由でこれらを呼び出しており、テストコード自体は読みやすい
名前付きテーブルのまま書ける（ラッパーはdeployビルドに含まれないため
サイズに影響しない）。

`src/chuso1800_core.lua`自体は`local M = {}`のようなモジュールテーブルを
一切持たない。`decode_state`・`physics_tick`・`core_tick`（本モジュールの
tickオーケストレータ本体。`calculateTick`という名前は
`deploy/main.lua`側のStormworks直結グローバルが使うため、衝突を避けて
こちらは別名にしてある）等はすべて`local`なしの**素のグローバル関数**として
定義されている。`test/run_all.lua`と`deploy/main.lua`はどちらもこのファイルを
`require`ではなく`dofile`で読み込む一枚岩の非モジュールファイルとして扱う。
モジュール化をやめた理由・経緯は `DESIGN_LOG.md` #15。

## 意図的な簡略化（黙って解決していない点の明示）

1. **`power_cut_latch`/`startup_delay`/`motor_current_oor` 系は削除。**
   `startup_delay` の `enable` は未配線かつ `discharge_time=0` のため出力は
   恒常 `false`、`motor_current_oor` のしきい値 `±200000A` は実際の電流レンジ
   （数百A）から到達不能。よって下流ラッチの `q` は常時 `false` と証明できる
   ─ 挙動変更ではなく**死コードの証明**。`power_cut` はゲート側RSSビットとの
   整合のため常時 `false` の定数ステータスビットとしてのみ残す。
   保証：`test/scenarios/power_cut_dead_logic_constant.lua`。

2. **CAPACITORを線形アキュムレータとしてモデル化。** デバウンス系
   （`phase1_cap` 等）は「Ntick連続enableで確定」の0-6カウンタ、
   `regen_delay`（0.5秒充電/10秒放電）は0-600のスケール済み整数
   （enable時+20/tick、disable時-1/tick。整数演算のみで浮動小数点誤差なし）。
   SPEC.md §0.1 のCAPACITOR記述に基づくが、**Stormworks実機の内部実装とは
   突き合わせていない**。境界値テスト：
   `test/scenarios/regen_delay_cap_timing.lua`。
   ビット割付の詳細は `SIGNAL_MAP.md`、生double案を却下した経緯は
   `DESIGN_LOG.md` #6。

3. **BLINKER+PULSE(rise)ペアを単一の経過tickカウンタ
   （`periodic_pulse_step`）に置換。** 本モジュールのどこもブリンカの生の
   ON/OFF出力を読まず、周期パルス（カム進段・界磁電流超過検知）だけが
   意味を持つため。
   **挙動差あり**：最初のパルスが有効化から `period_ticks` 後に来る
   （元設計は最短で `off_ticks` 後）。詳細は `src/chuso1800_core.lua` の
   `periodic_pulse_step` のコメントと `DESIGN_LOG.md` #7。

## チューニング可能なプロパティ（property.getNumber）

以下の2値は**spawn時に1回だけ**読み込むライブプロパティ。プロパティ名は
main.sw-net の対応する `PROPERTY_NUMBER` ノードの `n=` 属性と完全一致させて
あり、実配線後もLua側・ゲート側が同じプロパティ定義を参照する（真実源は
二重化しない）：

- `OVERSPEED_THRESHOLD` ← `property.getNumber("Over Speed Th. [m/s]")`
- `POWER_LIMIT_CURRENT` ← `property.getNumber("Power Limit Current [A]")`

素の `lua` のテスト環境（`property` グローバルが存在しない）では、
main.sw-net の各ノードのデフォルト値（`value=` 属性）と同じ値に
フォールバックする（`src/chuso1800_core.lua` 冒頭のコメント参照）。

`property.getBool` の呼び出しは存在しない（SAP/ECB切替はゲート側で完結、
M-typeはパンタグラフごとゲート側に残したため）。

## 入力の前提（ゲート側で解決済みの値を受け取る）

以下の入力は、main.sw-net の既存ノードが計算した**最終値**をそのまま
受け取る。本モジュールは車両がSAP車かECB車かを一切知らない：

- `brake_pressure_sw`／`sap_pressure_sw`：SAPセンサ直結／ECBオフセット換算の
  いずれであっても、ゲート側で解決済みの値
- `direction`：forward/backwardの2boolからゲート側で合成済みの -1/0/+1

生センサ値（`sap_raw`・`eb_signal`・`forward_signal`/`backward_signal`）を
受け取ってモジュール内で換算する設計から変更した経緯は `DESIGN_LOG.md` #4。

## スロット予算（概要）

詳細な内訳・ビット表は `SIGNAL_MAP.md` を参照。

| 配列 | 使用状況 |
|---|---|
| ステート | 8本中7本（パック済み2本＋生double5本）、1本予備 |
| ステートレス入力 | 8本すべて生double、予備なし。ビットパック不使用 |
| ステートレス出力 | 8本中5本、3本予備 |

状態機械と物理演算を統合したことで外部消費者のいなくなったチャンネル
（逆起電力・カム段echo・界磁電流）が消え、各カテゴリとも枠内に収まっている
（当初の予算懸念の経緯は `DESIGN_LOG.md` #8）。

## テスト

Stormworks実機は不要、素のLuaだけで動く：

```sh
lua test/run_all.lua
```

21本のシナリオ（`test/scenarios/*.lua`）。カバー範囲：

- **未変更の** `../CHUSO1800_Traction_Controller/scripts/n409.lua` に対する
  数値回帰（小さな `input`/`output` シム経由で `loadfile` するため、同ファイル
  が変更されていないことの受動的な再確認にもなる）
- SPEC.md §3.6 状態遷移図の完全な走査
- SPEC.md記載のコーナーケース（H4/H5/H6/H7）の検証
- `test/realistic_driving.lua`（クローズドループ速度シミュレーション
  ハーネス）を使った、実運転を想定した加減速シナリオ（`test/scenarios/
  realistic_scenario_*.lua`。DESIGN_LOG.md #27/#28参照）

`deploy/main.lua`（後述）には自動テストを設けていない。`dofile`が作業
ディレクトリ相対のためテストにはサブプロセスでの`deploy/`実行が必要になり、
中身はi2f/f2iの境界変換という薄いグルーコードにとどまる（`calculateTick`
本体のロジックは上記12本で既にカバー済み）ため、その労力に見合わないと
判断した。開発時に手元でi2f/f2iの往復精度と`onTick()`の多tick動作は
個別に確認済み（詳細は `DESIGN_LOG.md` #11）。

```sh
lua test/verify_deploy_artifact.lua
```

上記12本はいずれも`src/chuso1800_core.lua`（minify前のソース）を直接
`dofile`するため、**minify後の`deploy/chuso1800_deploy.lua`自体に
入り込むバグは検出できない**。実際に、storm-lua-minify（および元ネタの
luamin）が演算子優先順位を無視して括弧を落とすバグにより、minify後の
`put_bit`/`put_bits`/`get_bits`が壊れる事象が発生した（詳細は
`DESIGN_LOG.md` #18）。このスクリプトは`deploy/chuso1800_deploy.lua`
そのものを`input`/`output`のモック経由で動かし、ビットヘルパーの往復と
実際の状態遷移（notchを与えてphase1へ遷移し実電流が流れること）を
検証する、minifyそのものに対する回帰テスト。

## デプロイ（実機組み込み用スクリプト）

`../../lib/state_sync.lua` は、リポジトリ共通の汎用ステート同期ドライバ
（本モジュール専用ではなく、`calculateTick(stateless_in, state_in)` という
同じ形の純関数を持つ任意のマイコンモジュールから使える想定）。composite
チャンネル経由の自己ループ配線が実機でどれだけ遅延するか不確実な問題を、
「2tick前に自分が出した state と、外部からフィードバックされてきた値が
一致するか」を毎tick確認し、不一致なら再計算して追いつく、という設計で
吸収している。

`state_sync.lua` は次の契約を要求する（自身の冒頭コメントより）：
「一般入出力はfloat前提、state入出力はinteger前提」。本モジュールの
`state_in`/`state_out` はスロット1-2（旧STATE_LATCHES_LAYOUT/
STATE_TIMERS_LAYOUT、詳細は`SIGNAL_MAP.md`参照）こそ元から32bit整数だが、
スロット3-7（`OLD_I`/`OLD_IF_A`/`OLD_PHI`/`regen_bc_smooth`/
`bc_target_smooth`）は生のLua doubleであり、このままでは`state_sync.lua`の
想定と噛み合わない。`deploy/main.lua`がこの差を吸収する：スロット3-7を
`state_sync.lua`自身の`f2i`/`i2f`（float32のビットパターンをuint32として
運ぶ、`src/chuso1800_core.lua`の`to_u32`と同じ`string.pack`/
`string.unpack`の応用）でスロット境界だけ変換する。
`src/chuso1800_core.lua`自体はこの変換を一切知らず、内部では常にフル
精度のdoubleで計算する（既存テストスイートの挙動・許容誤差は無変更）。
float32への丸めはこの境界を1回通るときだけ発生し、これはStormworksの
composite `number` チャンネル自体が元々float32精度である以上、実機配線
すれば避けられない制約を明示化したものにすぎない。

`deploy/main.lua`は`dofile("state_sync")`／`dofile("chuso1800_core")`で
この2ファイルを読み込む。どちらも`require`は一切使わない ─
`lib/state_sync.lua`・`src/chuso1800_core.lua`ともにモジュールテーブルを
持たない素のグローバル関数の集まりであり、それぞれの冒頭コメントの通り
`dofile`が読み込み方法として最も直接的（storm-lua-minifyはstatement位置の
`dofile`を常に生の文として展開する）かつ、`require`＋`-m`モードが必要と
していたディスパッチャ機構ごと不要にできる（`-m`モードは使っていない ─
経緯は `DESIGN_LOG.md` #15）。実機投入用の最終フラット化・minifyは
`deploy/build.js`（Node.js、Windowsでも同じ手順で動く）が
`storm-lua-minify`パッケージを呼び出して行い、`deploy/chuso1800_deploy.lua`
を生成する。これがStormworksの単一LUAノードにそのまま貼り付けられる完成品で、
生成物自体もリポジトリにコミットしてある（3つのソースいずれかを変更したら
`node build.js`で再生成すること）。

**8192文字制限との戦い**：Stormworksの1つのLUAノードには最大8192文字までしか
書けない。`src/chuso1800_core.lua`は元々このminify後だけで12,386文字あり、
単体でも制限を超えていた。storm-lua-minifyは識別子のうち**ローカル変数・
ローカル関数名だけ**短縮できる（テーブルのキー文字列、およびグローバル
識別子はどちらも短縮できない ─ 後者は執筆時点(storm-lua-minify 0.1.3)の
制約で、将来のバージョンで対応予定とのこと）。そこで以下を行い、
`deploy/chuso1800_deploy.lua`を最終的に**7,656文字**（8192未満）まで
縮小した（経緯・実測値の推移は `DESIGN_LOG.md` #13〜#15）：
1. ビットレイアウトの汎用テーブル機構（`pack_bits`/`unpack_bits`＋
   `*_LAYOUT`テーブル）を廃止し、ビット位置を直接指定する
   `to_u32`/`get_bits`/`put_bits`/`get_bit`/`put_bit`に置き換えた。
2. `core_tick`内の全ヘルパー関数・`physics_tick`・
   `decode_state`/`encode_state`/`encode_stateless_in`/
   `decode_stateless_out`を、名前付きテーブルではなく位置引数・多値返却で
   やり取りする形に書き換えた（「コードの構成」節参照）。
3. `src/chuso1800_core.lua`自体のモジュールテーブル（`local M = {}`／
   `return M`）を廃止し、素のグローバル関数の集まりに変えた上で、
   `require`ではなく`dofile`で読み込む形に統一した。これにより
   storm-lua-minifyの`-m`モード（require()ディスパッチャ）自体が丸ごと
   不要になり、`state_sync.lua`と`chuso1800_core.lua`のどちらかが
   ディスパッチャ内で重複するバグ（当初は`state_sync.lua`側を
   `dofile`のまま残した結果、8,466文字まで再増加していた ─
   `DESIGN_LOG.md` #14）が根本から解消した。

## 今後の実配線について（実施済み）

以下の1〜5項は `main.sw-net` に実配線済み（`DESIGN_LOG.md` #17に、
オリジナルの `CHUSO1800_Traction_Controller/main.sw-net` との差分
─ 削除したノード・新規に追加したノード・維持したノード ─ を網羅した
一覧がある。この節は実配線前の計画としてそのまま残してある）：

1. `LUA current_sim` ノードの `script_ref` を、`deploy/main.lua`を
   `storm-lua-minify`でフラット化した最終スクリプトへ差し替える。
   8＋8本のスロットは、上記「デプロイ」節の通り`state_sync.lua`が2組の
   Composite Read/Write（ステート用は自己ループ、ステートレス入出力用は
   実際のゲートと接続）でパック／アンパックする（32チャンネル全体の
   配線規約は`lib/state_sync.lua`冒頭コメント、`deploy/main.lua`のコメント
   参照）。
2. `catenary_voltage_sw`／`brake_pressure_sw`／`sap_pressure_sw`／
   `direction` を新Luaノードへの正式な入力として配線する（いずれも既存
   ノードの出力をそのまま使える）。これらの解決に使う `sap_ecb_toggle`／
   `ecb_pressure_sw`／`ecb_sap_pressure`／`forward_flag_sw`／
   `backward_flag_sw` は、入力を作るゲートとして**残す**。
3. 置き換え済みとなるゲート網を削除する（2で残すもの以外）：
   phase1/phase2/regenのSRラッチとset/resetロジック、`position_counter`／
   ブリンカ／パルス／デバウンスCAPACITOR、`notch_eff`/`notch_ge*`、
   `eb_condition`、`current_src_mux`/`regen_current_write`、
   `regen_bc_smooth`/`bc_target_smooth`。
   **パンタグラフラッチ4個は削除対象ではない**（ゲート側に残す設計のため）。
4. 残すゲート（パンタグラフラッチ・架線電圧セレクタ・Momelink整形・
   Rolling Stock Status）を、新モジュールのステータスビットフィールド出力を
   読むよう配線し直す（パンタグラフ自体は今回無変更のため配線は元のまま）。
5. `overspeed_threshold`／`power_limit_current` の各 `PROPERTY_NUMBER`
   ノードは**削除せず残す**（本モジュールの `property.getNumber` が同名
   プロパティを読むため、ノードを消すとプロパティ定義自体が消える）。

## 設計変更の経緯

当初案からの変更点（bitpack分離の廃止、パンタグラフのゲート側復帰、
入力レイアウトの見直し、regen_delayの表現変更など）とその理由は、
すべて [`DESIGN_LOG.md`](./DESIGN_LOG.md) に時系列でまとめてある。
「なぜこの設計なのか」を疑問に思ったら先にそちらを参照のこと。
