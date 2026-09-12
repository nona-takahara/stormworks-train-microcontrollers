# CHUSO2000 Signal Gateway

NITS bus（編成内総括制御）と自車内の各マイコン（Cab Controller V・Traction
Controller・Door Min 等）との出入口を担うマイコン。`from NITS`/`to NITS`で
編成内の他車と接続し、自車側とは Control Commands Type 3 (CC3)・Simple IF
RX・Extended Commands RX・Rolling Stock Settings/Status の各コンポジットで
接続する。

上位の全体像は [`../SYSTEM_SPEC.md`](../SYSTEM_SPEC.md)・
[`../SignalComposite.md`](../SignalComposite.md) を正典とする。本書はこの
マイコン単体の入出力とブロック構成の見取り図であり、チャンネル番号・
ビット割付の正本ではない。

## ポート

| ポート | 方向 | 型 | 役割 |
|---|---|---|---|
| `from NITS` / `to NITS` | in / out | composite | NITS bus の生フレーム（受信・送信） |
| `Control Commands Type 3 front` | in | composite | 前位運転台側からの CC3（Onecar Control が合成） |
| `Simple IF RX` | out | composite | NITS から解読した編成全体の状態を自車機器へ中継 |
| `Extended Commands RX` | out | composite | 0x48–0x60 拡張コマンドのデコード結果・メモリレジスタ・各種内部ラッチ |
| `Rolling Stock Status w/ Inertia Composite` | in | composite | 自車のモータ・パンタグラフ・ブレーキ圧の状態 |
| `Rolling Stock Settings` | out | composite | `Inertia Composite`に軸動力有無フラグを付加して中継 |
| `CP Request` / `Door Open (A)` / `Door Open (B)` / `SOS Button 1` / `SOS Button 2` / `Battery` | in | boolean / number | 自車個別の入力信号 |
| `SOS Button` | out | boolean | `SOS Button 1`と`SOS Button 2`のOR |

チャンネル単位の定義は [`../SignalComposite.md`](../SignalComposite.md) の
「Simple Interface RX」「Extended Commands RX」「Control Commands Type 3
(CC3)」「Rolling Stock Settings」「Rolling Stock Status」の各節を参照する。

## main.sw-net のブロック構成

`main.sw-net`は信号の流れに沿って以下の順に並んでいる（見出しコメントと
一致）。

1. **Configuration properties** — NITS Ext. ID、Cab/Powered Axle/Side
   doors/Pantograph/Double Decker の各プロパティ
2. **NITS RX** — `scripts/n466.lua`によるバスフレーム解読
3. **Simple IF RX** — 解読結果を自車機器へ返送
4. **Address-match latch / local-mode gating** — 0x47 IDと自車IDの一致を
   ラッチし、一致後3秒間「ローカルモード」として拡張コマンド処理を有効化
5. **Car position & consist size** — 自車の連結順位・編成両数の算出
6. **NITS TX watchdog / strobe** — `n440.lua`のクラッシュ検知に使う
   ウォッチドッグ回路（詳細は下記参照）
7. **CC3 (front) direct reads**
8. **Car fault aggregation** — モータ故障・低電圧・SOSボタンを「故障」1本へ集約
9. **Rolling Stock Settings / motor current gating**
10. **Extended Commands: door status decode & memory register bus** —
    `scripts/n688.lua`（ドア関連 0x42/0x48/0x49 デコード）と
    `scripts/n691.lua`（8本のメモリレジスタ・アドレス指定 0x4C 書換）
11. **Extended Commands: per-car info packer** — `scripts/n523.lua`
    （編成各車の力行/制動/故障/開扉/締切状態を3ワードへパック）
12. **Extended Commands: internal latches** — 室内灯・案内表示・パンタ
    ロック・ヒータ・増圧ブレーキ・CP動作・高加速・SIV許可・チャイム種別・
    自車締切の各内部ラッチ。ローカル側（`n688.lua`出力）とリモート側
    （NITSから解読した`n466.lua`/`n523.lua`出力）をORで合成する構造が
    共通する
13. **Extended Commands: final composite assembly**
14. **Car Status (0x4B) composite** — `Simple IF TX`向けの自車ステータス
    ワード生成
15. **Simple IF TX** — `scripts/n458.lua`による CC3→0x48–0x60 エンコード
16. **NITS TX: assemble command composite & write to bus**

`nits_tx_encoder_lua`（`n440.lua`）・`nits_rx_decoder_lua`（`n466.lua`）は
[`../../NITS_Simple_Bridge/`](../../NITS_Simple_Bridge/)と同名のスクリプトを
使うが、チャンネル割付は独立している（`NITS_Simple_Bridge/SPEC.md`をそのまま
本機に適用できない）。ウォッチドッグ回路（8.）の仕組み自体は
[`../../NITS_Simple_Bridge/SPEC.md`](../../NITS_Simple_Bridge/SPEC.md)
「2. NITS TXフレーム生成」に解析済みの説明がある。

## 未確認点

- `cross_seat_shiokata_remote_read`/`cross_seat_suhou_remote_read`の
  ローマ字表記（潮方/須方）はフリガナの出典がなく推定である。
- `siv_permission_latch`の許可/禁止判定は、0x60フレームに専用の許可/禁止
  ビットがなく「SIV/MG起動中・停止中」ステータスビットを流用している。
  この代用が設計意図どおりかは未確認。
- `to_nits_reserved_bit_fixed_value`（`to NITS`のB5相当）は固定値になって
  おり、対応するライブ信号源が配線されていない。意図的な未実装か廃止済み
  かは未確認。
- `cc3_front_id_tx_flag_read`（CC3 B32）は`simpleif_tx_encoder_lua`
  （`n458.lua`）内で参照箇所が見当たらず、現状デッド配線の可能性がある。
