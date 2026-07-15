# sw-net-sim

`.sw-net` ゲート網の疑似実行シミュレータ。CHUSO1800 Lua Coreマイコンの
バグ調査（アプローチ1）用に作成した、リポジトリ共通で使えるツール。

## 構成

- `build.mjs`（Node.js）：`.sw-net` を `storm-microcontroller-language` の
  `parseSwNetDocument` でパースし、`sim.lua` が `dofile` でそのまま読み込める
  Luaテーブルリテラル（`*.graph.lua`）へ変換する。実機との既知の齟齬
  （SPEC.md §2 / `LEGACY_SPEC_CORRECTIONS.md` §3-4 記載の6ノードの
  `THRESHOLD(min,max=1→0)`修正、`speed`ノードの欠落した`composite`入力の
  補完）をここで適用する。元の `.sw-net` 自体は書き換えない。
- `expr.lua`：`FUNC_NUM_1/3/8`（数値式）と`BOOL_FUNC_4/8`（論理式）の
  簡易パーサ兼評価器。
- `sim.lua`：本体のtickシミュレータ。
- `lua_node_bridge.lua`：`LUA`ノード（Stormworksの`input`/`output`API・
  `onTick()`を使う素のLuaスクリプト）を、独立したグローバル環境で
  そのまま動かすためのラッパー。`scripts/n409.lua`を無改変で使う。
- `smoke_scenario.lua`：シミュレータ単体の健全性確認スクリプト
  （`lua smoke_scenario.lua`）。

## tickモデル（重要な設計判断）

このセッションでユーザーと確認した通り、**全ゲート出力を一律1tick遅延**
させる。ただし字面通りに「遅延した配線」を実装するのではなく、
「前tickの全ノード出力をフリーズし、この凍結済みスナップショットだけを
今tickの入力として使う」という形で実装している（`sim.lua`冒頭コメント
参照）。この方式には利点がある：

- ノード間の依存関係を見てトポロジカルソートする必要が一切ない
  （フィードバックループの解決＝サイクル検出が不要）。自己ループ
  （`position_counter`の`(x+y)%21`等）も、直列に何段も挟まった
  フィードバック（SRラッチの`s`/`r`が自分の`q`に依存する等）も、
  すべて同じ1行の仕組み（`frozen`テーブル参照）で自動的に解決する。
- ノードの評価順序は完全に無関係（tickごとに`graph.nodes`を
  好きな順序で回してよい）。

**この選択の背景**：`CHUSO1800_Traction_Controller/SPEC.md` §2は
「SR_LATCH・CAPACITOR・Lua・自己帰還式だけが状態を持ち、組合せゲートは
同tick内で瞬時に伝播する」と仮定しているが、`LEGACY_SPEC_CORRECTIONS.md`
§4はこの仮定自体を「本マイコン固有資料から確認されていない」と明記して
いる。一方 `storm-microcontroller-language` パッケージ自身の知識ベース
（`node-behavior-notes.json`の`execution-order`、confidence: **verified**）
は「Video/Audio以外の全コンポーネントは前tickの出力値を今tickの入力として
使う」＝全ゲート一律1tick遅延、と明記している。今回はユーザーの指示で
後者（全ゲート一律1tick遅延）を採用した。

**注意**：`chuso1800_core.lua`（Luaコア移植）は前者（組合せは瞬時、状態要素
だけ遅延）の前提で書かれている。そのため本シミュレータと`chuso1800_core.lua`
を単純にtick単位で突き合わせると、実際のロジックバグとは無関係な
「一律1tickぶんのタイミングのずれ」が突き合わせ結果に出る可能性が高い。
突き合わせ方法（定常値比較にするか、tickモデルの差を吸収する変換を挟むか等）
は別途検討が必要。

## 対応ゲート

`AND`/`OR`/`NOR`/`XOR`/`NOT`/`CONST`/`THRESHOLD`/`GREATER_THAN`/
`LESS_THAN`/`EQUAL`/`SUBTRACT`/`ABS`/`DELTA`/`FUNC_NUM_1`/`FUNC_NUM_3`/
`BOOL_FUNC_4`/`BOOL_FUNC_8`/`NUM_SWITCHBOX`/`COMPOSITE_SWITCHBOX`/
`SR_LATCH`/`CAPACITOR`/`BLINKER`/`PULSE`/`PROPERTY_NUMBER`/
`PROPERTY_TOGGLE`/`PROPERTY_DROPDOWN`/`COMPOSITE_READ_NUMBER`/
`COMPOSITE_READ_BOOLEAN`/`COMPOSITE_WRITE_NUMBER`/`COMPOSITE_WRITE_BOOLEAN`/
`LUA`（`CHUSO1800_Traction_Controller/main.sw-net`で使われている25種）。
他のゲート型が出てきたら`sim.lua`の`PORT_KINDS`/`EVAL`に追加が必要
（未対応の型は`Sim.new`で即エラーになる）。

CAPACITORのヒステリシス（満充電で一度ONになったら完全放電までON維持）は
`CHUSO1800_Traction_Controller_LuaCore`側で実機検証済みのモデル
（DESIGN_LOG.md #21）を一般化して実装した。BLINKERは「有効化後、最初は
off_ticks待ってから点灯」という経験則（同SIGNAL_MAP.md）に従っている
─ この初期位相の厳密なtick合わせは実機未確認。

## 既知の単純化

- 車両の速度応答（電流→加速度→速度のフィードバック）はモデル化していない。
  `Phyics Sensor [+Z is front]`ポートは呼び出し側が明示的に与える値
  （`smoke_scenario.lua`ではspawn後ずっと0）のまま。よって`smoke_scenario.lua`
  のような速度0固定シナリオでは、電流が制限閾値を超えたまま下がらず
  カムが進段しなくなる（物理的に正しい振る舞い ─ 実車なら加速して
  背電力が増え電流が下がる）。
- パンタグラフ・SAP/ECB切替などのPROPERTY系ノードは、`.sw-net`本文に
  明記されている属性（`v=`等）だけを使う。属性が省略されているノード
  （例：本ファイルの`sap_ecb_toggle`は`v=`省略＝Stormworksのデフォルト
  通りfalse＝ECB側）はそのまま未設定＝falseとして扱う。

## 使い方

```sh
cd tools/sw-net-sim
node build.mjs ../../CHUSO1800_Traction_Controller/main.sw-net chuso1800_original.graph.lua
lua smoke_scenario.lua
```
