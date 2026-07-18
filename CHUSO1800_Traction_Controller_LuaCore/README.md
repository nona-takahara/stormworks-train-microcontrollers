# CHUSO1800 Lua Core

CHUSO1800牽引制御の状態機械、カム進段、電流モデル、回生・空気ブレーキ補完を
1つのLuaノードへ統合した実装です。`main.sw-net`への配線と実機投入用成果物まで
含みます。

## ドキュメント

| ファイル | 役割 |
|---|---|
| [`SPEC.md`](./SPEC.md) | 現在のLua Coreの挙動と安全条件 |
| [`SIGNAL_MAP.md`](./SIGNAL_MAP.md) | 4配列×8スロットとビット割付の正典 |
| [`DESIGN_LOG.md`](./DESIGN_LOG.md) | コードから読み取れない設計判断と障害原因 |
| [`../CHUSO1800_Traction_Controller/SPEC.md`](../CHUSO1800_Traction_Controller/SPEC.md) | 原型ゲート網の仕様 |
| [`../LUA_CODING_GUIDE.md`](../LUA_CODING_GUIDE.md) | リポジトリ共通のLua構成規約 |

通常の修正では`SPEC.md`と`SIGNAL_MAP.md`だけを先に読み、理由が必要な場合に
`DESIGN_LOG.md`の該当番号を参照してください。

## 構成

- `src/chuso1800_core.lua`: 純関数`core_tick(stateless_in, state_in)`と補助関数
- `deploy/main.lua`: `state_sync.lua`とのfloat/integer境界
- `deploy/build.js`: storm-lua-minifyによる単一ファイル生成
- `deploy/chuso1800_deploy.lua`: Stormworksへ貼り付ける生成物
- `main.sw-net`: Lua Coreと、ゲート側に残した処理の結線
- `test/`: ソースと生成物の回帰テスト

ゲート側には、パンタグラフ、架線電圧選択、SAP/ECB変換、方向合成、
Momelink-AおよびRolling Stock Statusのフレーム整形を残しています。

## 実行契約

```lua
stateless_out, state_out = core_tick(stateless_in, state_in)
```

各配列は要素数8です。`state_out`を次tickの`state_in`へ戻します。
永続グローバルには制御状態を持ちません。正確な割付は`SIGNAL_MAP.md`を参照してください。

`src/chuso1800_core.lua`はモジュールテーブルを持たず、外部APIをグローバル関数で
定義します。Stormworksの8192文字制限とビルド方式に合わせた意図的な構成です。

## 原型との差分

- 組合せゲート連鎖を同一`core_tick`内へ圧縮し、真に状態を持つ要素だけを
  `state_in/state_out`へ保存します。過渡のtick数は原型と異なりうる一方、
  定常状態と安全条件を維持します。
- BLINKER+PULSEを周期カウンタへ置換しています。定常周期は同じですが初回位相は
  逐語互換ではありません。
- 到達不能な`power_cut`経路を削除し、互換用status bitだけ常時falseで残します。
- 原型ゲート網に存在した低速再力行時の固着・過電流経路を修正しています。
- 非常制動とDB自動OFF時の異常状態では、解放を決めたtickから電流、電力、
  Momelink-A用加速度を0にします。
- 弱め界磁力行のノッチ4以上では、電流目標に`Power Limit Current [A]`を使います。

## プロパティ

次の値をspawn時に1回読みます。

- `Over Speed Th. [m/s]`
- `Power Limit Current [A]`

テスト環境では`test/run_all.lua`が同名プロパティのスタブを用意します。

## テスト

Lua Coreのソースを検証します。

```sh
lua test/run_all.lua
```

minify済み成果物を直接実行し、演算子優先順位と変数名衝突を含むビルド回帰を
検証します。

```sh
lua test/verify_deploy_artifact.lua
```

## ビルド

`CHUSO1800_Traction_Controller_LuaCore/deploy`で実行します。

```sh
node build.js
```

`build.js`は`lib/state_sync.lua`と`src/chuso1800_core.lua`を一時的に同じ
ディレクトリへ置き、`deploy/main.lua`を入口にフラット化・minifyします。
生成後は次を確認してください。

1. `deploy/chuso1800_deploy.lua`が8192文字以内である。
2. `lua test/run_all.lua`が通る。
3. `lua test/verify_deploy_artifact.lua`が通る。

生成物はビルドごとに識別子名が変わる場合があります。テキスト差分の小ささではなく、
文字数と生成物テストの結果を判定基準にします。

## 変更時の注意

- スロットやビットを変える場合は`SIGNAL_MAP.md`とencode/decodeを同時に更新する。
- ビット演算で異なる優先順位の演算子を1行へ混在させない。
- Newton反復を独立local関数へ戻さない。
- `stuck_at_top_idle`を界磁電流超過の共有パルスへ合流しない。
- 直列・並列がともにOFFなら、電機子電流、電力、平滑加速度が0であることを保つ。
