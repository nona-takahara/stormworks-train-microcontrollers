# 汎用プローブ（バイトコード仮想機械）

HTTP で注入したプログラムを tick ごとに走らせる小さな仮想機械の置き場である。
仕様は [BYTECODE_SPEC.md](BYTECODE_SPEC.md)。空気圧の測定仕様は `../AirBrake/SPEC.md`（まだコミットしていない）。

## 構成

| パス | 内容 |
|---|---|
| `src/gp.lua` | Stormworks の入口（composite と HTTP の問い合わせ）。minify の入力で、そのまま貼らない |
| `src/gp_core.lua` | 仮想機械とホスト層（Stormworks の API に依存しない純ロジック）。グローバル関数 `gp_*` |
| `src/ops.txt` | 命令番号の表（追記専用）。仕様の表との一致は Node のテストが見る |
| `tools/gpasm.mjs` | アセンブラ（Node）。`node tools/gpasm.mjs file.asm [--reset] [--out f] [--symbols-lua f]` |
| `programs/air_brake_basic.asm` | 空気圧の目標追従（試験用の最小例） |
| `programs/chuso1800/` | （まだコミットしていない）1800系 Lua Core の移植。`core_body.asm`（元の関数ごとに分けた節）、`core_only.asm`（`core_tick` の境界）、`state_sync.asm` + `main.asm`（`state_sync` もバイトコードで書いた、デプロイ形） |
| `test/run_all.lua` | 仮想機械の確認テスト（`lua test/run_all.lua`） |
| `test/gpasm.test.mjs` | アセンブラと結合の試験（`node --test test/gpasm.test.mjs`） |
| `test/chuso1800_port.lua` | （まだコミットしていない）`core_tick` の境界で、移植を元の Lua Core と比べる（乱択と境界狙いの差分 18000 件と、元のシナリオ 24 本） |
| `test/chuso1800_sync.lua` | （まだコミットしていない）デプロイ形の境界（`lib/state_sync.lua` の `onTick`、composite の 32 入力 32 出力）で、`state_sync` をバイトコードで書いた版を元と比べる。同期イベントで再計算の経路も通す |
| `test/chuso1800_timing.lua` | （まだコミットしていない）1 tick の命令数と時間（PC 上の目安） |

## 現在地

- 仮想機械、アセンブラ、空気圧の最小例、1800系 Lua Core 全体の移植まで動く。ゲーム内での実行は未検証である。
- `state_sync`（同期ステート）は仮想機械に組み込まず、バイトコードのプログラム（`state_sync.asm`）として書いてある。状態の 32 ビット整数への詰め込みと展開、float32 のビットパターンへの変換（`F2I`/`I2F`）、フィードバックとの照合、不一致のときの再計算の経路を含む。NITS など `state_sync` を使う他のマイコンも、同じ形で移せる。
- 比較は 2 つの境界で行う。`core_tick` の境界（`chuso1800_port.lua`）と、デプロイされた `onTick` の境界（`chuso1800_sync.lua`。毎 tick の状態の float32 への丸めを含む）。
- 入口（`src/gp.lua`）は最小限で、問い合わせと応答の受け取りだけを持つ。記録バッファ、開始・停止、ガードなどの設定メッセージは未実装である。
- 8192 文字: 入口 + 仮想機械は minify 後 5641 文字（2026-10-19 実測）。内訳と収める指針は BYTECODE_SPEC.md の「実装の大きさ」。
- 実機で測る項目は BYTECODE_SPEC.md の「未決」に並べてある。
