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
- 各スロットは生のdoubleか、`src/bitpack.lua` の `bitpack.pack`/`bitpack.unpack`
  で生成・分解される整数のどちらか。後者を使うと複数のbool・小さい整数を
  1つの32bitスロットに同居させられる。

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

2. **SAP/ECBトグルをECBに固定。** sw-netの `PROPERTY_TOGGLE` 自体のデフォルト
   （`v=` 省略＝オフ＝「ECB」ラベル）と一致させている。ただしこれは実質的な
   挙動変更で、元々はStormworksのプロパティパネルで実行中に切替可能だった
   ものが、今後はソースコードの定数（`src/chuso1800_core.lua` の
   `SAP_ECB_IS_SAP`）を書き換える形に変わる。ステートレス入力スロット5・6は
   （ECB固定中は未使用のまま）`"BP [atm]"`/`"SAP [atm]"` に配線済みなので、
   将来SAPモードを有効化する際はスロット割付の再設計なしに定数を1つ
   切り替えるだけで済む。

3. **M-type（1800/1900）を1800に固定**（`IS_1800_TYPE` 定数）。未変換の
   Momelink選択ゲート側は引き続き実際の `mtype_toggle` プロパティを読むため、
   「1800か1900か」の真実源がLua側とゲート側で二重化している。この設計を
   1900系ユニットへ転用する場合は両方を手動で同期する必要がある。

4. **CAPACITORの充放電を線形アキュムレータとしてモデル化。**（enable中は
   charge_time秒で「充電完了」に達し、disable中はdischarge_time秒で0に戻る。
   `regen_delay_cap` の0.5秒/10秒ペアは、+20/tick充電・-1/tick放電の
   0-600レベルとして表現。）これはSPEC.md §0.1自体のCAPACITORの説明に
   基づくものだが、Stormworks実機の内部実装そのものと突き合わせたわけでは
   ない。この前提が耐えるべき境界値テストは
   `test/scenarios/regen_delay_cap_timing.lua` を参照。

5. **BLINKERは（再）有効化されるたびに必ず`off_ticks`分の「オフ」フェーズから
   開始する**（即座にオンになる応答ではない）。これは、状態遷移でブリンカが
   有効化されてから最初のパルスが出るまでに最大`off_ticks`分の追加遅延
   （進段/回生警告ブリンカの短い方のフェーズで0.1秒、回生警告ブリンカのオフ
   フェーズで0.4秒）がかかることを意味するが、その代わり保持している
   位相ビットが常に「現在の出力」を正直に反映するという性質が保たれる。
   これは、追加のステートビットなしに立ち上がりエッジ（PULSE）を検出するために
   必要な性質である。詳細は `src/chuso1800_core.lua` の `blinker_step`
   のコメントを参照。

## スロット予算（詳細な内訳はSIGNAL_MAP.mdのビット表を参照）

- ステート：22bit（パック済みラッチ・タイマー）＋19bit（パック済み）＋
  生double5本 ＝ 8本中7本を使用、1本予備。
- ステートレス入力：8本中4本を使用、4本予備（うち2本は将来のSAPモード切替に
  備えて `"BP [atm]"`/`"SAP [atm]"` に先行配線済み）。
- ステートレス出力：8本中5本を使用、3本予備。

いずれも、当初懸念していた「8本の枠に収まらない場合は相談」に該当する
ケースはなかった。状態機械と物理演算を統合したことで、外部からの消費者が
実質いなくなったチャンネル（逆起電力・カム段echo・界磁電流）が消えた分、
各カテゴリで想定より余裕ができた。

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
5. SAP/ECBおよびM-typeのハードコードを今後もソース定数のまま維持するか、
   ライブプロパティをパックされた入力ビットフィールドへ戻す仕組みを
   設計するかを決める（スロット5・6は既にこのために予約済み）。
