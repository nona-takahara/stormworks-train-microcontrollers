# CHUSO2000 Onecar Control — 設計仕様

## 概要

単車制御マイコン。前方・後方の両運転台から届く `Control Commands Type 3` を合成し、
単一の `Control Commands Type 3` として下流（牽引制御・ドア制御等）へ出力する。
また `Simple IF RX` の前後両数チャンネル (N4/N5) を入れ替えて `Simple IF RX inverted` として出力する。

## 命名規則

- `cc3_front_*` / `cc3_back_*` — 前方/後方からの CC3 入力から読み出した値
- `b{N}_or` — CC3 boolean チャンネル N の前後 OR 結果（出力 B{N} に対応）
- `b{N}_packed_or` — N7 packed bool の B{N} を前後 OR した結果
- `packed_front_b{N}` / `packed_back_b{N}` — N7 packed から展開した個別ビット
- `*_sw` — COMPOSITE_SWITCHBOX 経由（アクティブ運転台側のみ通過）
- `sifrx_*` — Simple IF RX 処理関連

## 論理グループ

### 1. 運転台選択

CC3 の B6 (`channel=6` boolean) が `front_cab` ビット。

| インスタンス | 役割 |
|---|---|
| `cc3_front_is_front_cab` | 前方 CC3 の B6 読み出し |
| `cc3_back_is_front_cab` | 後方 CC3 の B6 読み出し |
| `front_cab_active` | 前方がfront_cab かつ 後方がfront_cabでない → 前方運転台起動 |
| `back_cab_active` | 後方がfront_cab かつ 前方がfront_cabでない → 後方運転台起動 |
| `any_cab_active` | 前後いずれかがfront_cab |
| `either_cab_active` | front_cab_active OR back_cab_active |
| `cc3_front_sw` / `cc3_back_sw` | アクティブ運転台側のみ通す Switchbox |

### 2. 数値チャンネル

| チャンネル | 信号名 | 合成方式 |
|---|---|---|
| N1 | ブレーキノッチ | switchbox 経由で前後 ADD |
| N2 | 力行ノッチ | switchbox 経由で前後 ADD |
| N3 | ダイナミックブレーキ | switchbox 経由で前後 ADD |
| N4 | ブレーキ力[kPa] | 前方のみ (`brake_force_front`) |
| N5 | 力行パラメータ | 前方のみ (`powering_param_front`) |
| N6 | NITS データ | 前後から FIFO キューへ (`nits_front` / `nits_back`) |
| N7 | packed bool B1-B15 | 前後展開して OR 合成後に再パック |

### 3. N7 packed bool (B1-B15)

B3/B4、B7/B9(ch位置)、B10/B11、B12/B13 は前後で入れ替えが発生する（前後方向反転のため）。
`cc3_b_packed_builder` → `cc3_b_packed_num` で数値化して N7 に出力。

### 4. 前後選択 / 締切ゲート

B7 が前後選択コマンド。前方運転台から後方への B7 送信、または後方から前方への B7 送信が
クロスした場合を `door_isolated`（締切状態）とし、B6/B7 の出力信号をゲートで無効化する。

| インスタンス | 役割 |
|---|---|
| `fwd_back_cross_front` | 前方が front_cab かつ 後方が B7 ON |
| `fwd_back_cross_back` | 後方が front_cab かつ 前方が B7 ON |
| `door_isolated` | クロス発生 = 締切状態 |
| `not_door_isolated` | 締切でないフラグ |
| `any_cab_active_gated` | `any_cab_active` AND `not_door_isolated` → CC3 B6 出力 |
| `any_fwd_back_cmd_gated` | `any_fwd_back_cmd` AND `not_door_isolated` → CC3 B7 出力 |

### 5. Boolean チャンネル (B1-B32)

基本は前後 OR。例外:
- **B4/B5**: 前後で扉A/B が入れ替わる（後方の B5→前方の B4 扱い、逆も同様）
- **B16/B17**: switchbox 経由で前後反転（前方 ch16=前進 → 後方 ch17 と対応）
- **B18**: AND（前後両方がONの場合のみ。DBブレーキ自動）
- **B27-B30**: 扉開閉操作で前後チャンネル反転（B27↔B29, B28↔B30）
- **B32**: OR後さらに `either_cab_active` でゲート (`id_tx_gated`)

### 6. Simple IF RX

N4(前側両数) と N5(後側両数) を入れ替えて `Simple IF RX inverted` として出力。
B4/B5 も同様に入れ替え。

### 7. NITS FIFO キュー

`scripts/n200.lua` が float-int 変換ベースの FIFO キューを実装。

**エンコード形式**: Stormworks の float と 32bit int の相互変換を利用。`('I4'):unpack(('f'):pack(x))` でデコード。

**動作**:

- 入力コンポジット N1/N2 を毎 tick 読む（2件/tick 受信可能）
- センチネル値 `1<<24 = 16777216` は「無効」を意味し、キューに積まない
- キューから先頭 1 件を出力（キュー空時はセンチネルを出力）

| 入力 ch | 内容 |
|---------|------|
| N1 | NITS パックデータ 1 |
| N2 | NITS パックデータ 2 |

| 出力 ch | 内容 |
|---------|------|
| N1 | NITS パックデータ（1件/tick）またはセンチネル |
