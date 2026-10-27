# 中宗電鉄 2000系列 マイコンシステム 仕様書

> - 対象: `CHUSO/CHUSO2000_*` 配下の各 `main.sw-net` と付随する Lua スクリプト
> - 参照: `SignalComposite.md`（NITS のフレーム定義は「NITS フレーム仕様」の節）、公式の [NITS](https://nonasaba.net/sw-train-docs/communicate/NITS.html)
> - 本書は、マイコン間のデータの流れ、通信プロトコル、システム全体で読み違えやすい点を書く。マイコン単体の入出力と論理は、各マイコンの `SPEC.md` を読む。

---

## 0. 凡例

`storm-mcl` の構文、ゲート、チャンネル番号、tick 評価の一般仕様は `storm-mcl spec` を正典とする。本書では「B」をブールチャンネル、「N」を数値チャンネルの略記として使う。

`NUM_SWITCHBOX` と `COMPOSITE_SWITCHBOX` は、`switch` が true のとき `a`、false のとき `b` を選ぶ（verified）。

---

## 1. システム概要

CHUSO 2000系の制御は、1 両単位の運転台ユニットと、編成内通信（Momelink と NITS）の二層で構成される。

| マイコン | 役割 | 仕様書 |
|---|---|---|
| **Cab Controller V** | 運転台制御の中核。座席、スイッチ、ループ、ATS/ATC などを読み、制御コマンドと表示用の状態を作る | [`CHUSO2000_Cab_Controller_V/SPEC.md`](./CHUSO2000_Cab_Controller_V/SPEC.md) |
| **Cab Display IV** | 運転台モニタ。`Monitor Status` と `Rolling Stock Status` を映像にする | [`CHUSO2000_Cab_Display_IV/SPEC.md`](./CHUSO2000_Cab_Display_IV/SPEC.md) |
| **Driver Assistance IV** | 運転支援。GPS と距離程から次の停車駅と接近を求め、行路の入力画面を持つ | [`CHUSO2000_Driver_Assistance_IV/SPEC.md`](./CHUSO2000_Driver_Assistance_IV/SPEC.md) |
| **Traction Controller** | 牽引制御（VVVF）。力行、回生、空気ブレーキの協調、パンタグラフ、Momelink | [`CHUSO2000_Traction_Controller/SPEC.md`](./CHUSO2000_Traction_Controller/SPEC.md) |
| **Onecar Control** | 単車制御。前後 2 運転台の CC3 を 1 つに合成し、NITS を FIFO で順送する | [`CHUSO2000_Onecar_Control/SPEC.md`](./CHUSO2000_Onecar_Control/SPEC.md) |
| **Door Min** | ドア 1 枚の最小制御。ドア状態、チャイム、ドアモーターの速度指令 | [`CHUSO2000_Door_Min/SPEC.md`](./CHUSO2000_Door_Min/SPEC.md) |
| **Signal Gateway** | NITS バスと、自車内の各マイコンの出入口 | [`CHUSO2000_Signal_Gateway/README.md`](./CHUSO2000_Signal_Gateway/README.md) |

NITS Simple Bridge（NITS バスと Simple IF の変換）は、[`../NITS_Simple_Bridge/SPEC.md`](../NITS_Simple_Bridge/SPEC.md) にある。

### 1.1 全体データフロー

```
[運転台インパネ群]
   │ Seat Input / Crew Handle / Driving Loop / Settings Loop
   ▼
Cab Controller V ──Control Commands TX──▶ (Bridge/Gateway 経由) ──CC3──▶ Onecar Control
   │  └─Monitor Status──▶ Cab Display IV / Driver Assistance IV          │
   │                                                                     │ CC3 統合
   ▼                                                                     ▼
Driver Assistance IV ──Drive Support──▶ Cab Controller V        Traction Controller (Simple IF/Ext.)
                                                                Door Min (NITS Ext.)
```

Cab Controller の `Control Commands TX` は、車両ブリッジとゲートウェイ（`Signal_Gateway`、`Signal_Bridge`）で NITS パケットになり、編成内に分配される。Onecar Control は、NITS から復元された前後 2 系統の CC3 を受けて、単車向けに合成する。

---

## 2. マイコン間インターフェース（コンポジット信号）

主要なコンポジットの定義元と内容は、`SignalComposite.md` が正典である。流れの要点は次のとおり。

| コンポジット | 送信元 → 受信先 | 内容 |
|---|---|---|
| **Control Commands TX** | Cab Controller → Bridge/Gateway | N1 ブレーキ[0-31]、N2 力行、N6 `Drive Support` N1、N7 packed bool（0x60 ペイロード）、B1 非常制動、B6/B7 前後選択、B16/B17 前後進、B27-B30 扉開閉、B32 運転台有効 など |
| **Control Commands Type 3 (CC3)** | 前後運転台 → Onecar Control → 牽引・ドア | 上記を 1 両向けに合成したもの。B6 は有効側を示すフラグ |
| **Simple Interface RX / Simple IF** | 編成バス → 各車 | N1 ブレーキ、N2 力行、N4/N5 前後両数、B1 非常制動、B16/B17 方向、B18 DB 自動 など。自車は ch16、前車は 1〜15、後車は 17〜31、コモンは 32 |
| **Extended Commands RX** | Bridge → 牽引・Cab | N9 扉モード、B1 NITS Ext 有効、B4〜B9 パンタのロックと昇降、B10 自車締切ラッチ、B14 高加速、B32 後方車両締切 など |
| **Monitor Status** | Cab Controller → Display / Driver Assistance | B1〜B16 状態ビット、N9 ブレーキ、N10 力行、N11 レバーサ、N12 編成向き、N13 速度、N27〜32 Ext のコピー |
| **Drive Support** | Driver Assistance → Cab Controller | N1 行路・状態のキュー、N2 キュー残件数、B2/B3 ドアカット（A/B）、B4 接近中 |
| **Rolling Stock Status** | Traction Controller → Display | N2 BC 圧[kPa]、N3 モータ電流[A]、N4 架線電流[A]、N5 架線電圧[V]、N8 MR 絶対圧[atm abs]、パンタ状態ビット |
| **Rolling Stock Settings** | 設定 → 牽引・Cab | B1 is_m_car、B2 編成向き（上り） |
| **Inertia Composite** | 設定 → 牽引 | N1〜N4 無次元の慣性係数 a、b、c、d。現在の演算結果は未接続 |
| **Momelink** | 牽引 ↔ 編成内ユニット | ID=1911、N1 摩擦制動減速度[m/s²]、N2 電動機加速度[m/s²]、N23 架線電圧 |

`Simple Interface RX`、`Control Commands TX`、CC3 は、いずれも N1 がブレーキ、N2 が力行である。前後反転の処理と混同しない。

---

## 3. NITS 通信プロトコル

NITS は編成内の機能制御を担う拡張コマンド群（コマンド ID 0x47〜0x60）である。ビット定義の正典は、`SignalComposite.md` の「NITS フレーム仕様」の節と、公式の NITS 仕様である。Cab Controller が 0x60 ペイロードを作り、Onecar Control が前後の NITS を FIFO で順送する。

### 3.1 0x60 ペイロード（Cab Controller の `Control Commands TX` N7）

N7 は、次の bool を数値にまとめたものである（bit 0 が下表の B1）。

| B | 内容 | 作り方 |
|---|---|---|
| 1 | CP 起動許可 | `Settings B4` |
| 2 | SIV 起動許可 | `Settings B3` |
| 3、4、5 | クロス転換 | `Drive Loop` B19、B20、B21 に、ドア操作の許可条件を AND |
| 6 | 高加速 | `Settings B12` かつ 運転台が有効 |
| 7、8 | 他車、自車の締切 | `Settings B17`、`Settings B16` |
| 10、11 | A 側、B 側の開扉操作 | ドアの開操作の条件 |
| 12、13 | 前、後の締切コマンド | 自動締切装置が働き、運転台が有効で、`Drive Support` B2、B3 が true |

詳細は `CHUSO2000_Cab_Controller_V/SPEC.md` にある。

### 3.2 NITS FIFO（Onecar Control の `n200.lua`）

- 入力 N1、N2 は前後の NITS（float のビット列を整数に戻したもの）である。`1<<24` 以外をキューへ積む。
- 毎 tick、先頭 1 件を float のビット列にして出力 N1 に出す。空のときは `1<<24`（無効のセンチネル）を出す。
- 1 tick に 1 件しか出せないので、NITS コマンドが続くと、順に遅れて伝わる。

### 3.3 0x48、0x49、0x4A〜0x4C

扉モードとドアカット（0x48）、パンタ・室内灯・ヒータ（0x49）、車両諸元（0x4A）、車両状態（0x4B）、汎用 Ext（0x4C）は、Bridge と Gateway が解釈し、Extended Commands RX として各車へ届く（`SignalComposite.md` の「NITS フレーム仕様」を参照）。Door Min は、`Door Side` のチャンネルで開扉指令を受ける。

---

## 4. 制動・力行制御フロー

```
[マスコンハンドル] Seat N2
   ▼ ノッチカウンタ（範囲は Cab_Controller_V/SPEC.md を参照）
   ▼ 非常位置ラッチ（非常位置のとき -8 に固定）
   ▼ 有効ノッチ = min(ノッチ, ATS/ATC の各制限)
   ├─ 力行 = max(有効ノッチ, 0)          → TX N2
   └─ ブレーキ = clamp(…, 0, 31)         → TX N1
   ▼ (Bridge → NITS → CC3 前後)
Onecar Control: N1/N2/N3 を前後で足す
   ▼ CC3
Traction Controller: Simple IF の N1（ブレーキ）、N2（力行）として受信
   ▼ VVVF Lua (n485): 速度、方向、定速目標から、電動機加速度と電流を求める
   ▼ Lua 故障または非常制動継続のとき、フォールバックの結果に切り替える
   ├─ BC Target = 空気ブレーキ減速度 × 3.02 + プリロード + 1
   ├─ Momelink N1 = 摩擦制動減速度[m/s²]
   └─ Output(Watt) = 架線電流 × 牽引供給電圧
```

M 車はローカルで電動機を計算する。T 車は、ID=1911 の Momelink から、電圧、電流、空気ブレーキの分担を受ける。Lua の出力の選択は、マスコンの有効状態ではなく、非常制動の継続と Lua ウォッチドッグの故障で決まる。

---

## 5. ドア制御フロー

```
[車掌スイッチ / ワンマンスイッチ / Drive Loop]
   ▼ Cab Controller
   ├─ A 側の開操作 = (Settings B20 | Crew Right B1 | 乗務員用 Drive Loop B6) かつ 許可条件
   ├─ B 側の開操作 = (Settings B25 | Crew Left B1  | 乗務員用 Drive Loop B8) かつ 許可条件
   │   許可条件 = Settings B9（戸閉連動）または 速度が -1.5 以上 1.5 以下
   ├─ 閉操作（インターロックなし）
   ▼ TX B27〜B30（扉 A/B の開閉操作）、0x60 B10/B11（開扉）
   ▼ (NITS) → Onecar Control
Onecar Control: B27↔B29、B28↔B30 を前後で入れ替えて OR → CC3 B27〜B30
   ▼
Door Min: NITS Ext. の `Door Side` のチャンネルで開扉、その 1 つ上で閉扉を受ける
   ▼ ドアモーターの速度指令 + チャイム
```

ワンマン時（`Settings B5` が OFF）は、`Drive Loop` のドア指令を使う。「乗務員用 Drive Loop」は、この `Settings B5` が false のときだけ `Drive Loop` を通す。

---

## 6. 運転支援の流れ

詳細は `CHUSO2000_Driver_Assistance_IV/SPEC.md` にある。

1. タッチ画面で、種別、出発駅、行先駅などを入力する（n105）。
2. 行路コード（`MS N3`）と GPS、距離程から、次の停車駅と接近状態を求める（n61）。
3. 行路、状態、ドアカットを `Drive Support` の N1（キュー）、B2〜B4 として出す（n141）。
4. Cab Controller は、`Drive Support` の B2、B3 を、前、後の締切コマンドとして使う（0x60 の B12、B13）。

---

## 7. 読み違えやすい点

1. **ハンドルの非常位置ラッチ**: Cab Controller の `seat_latch`（`SR_LATCH`）は、`not_q` が true のときハンドルが非常位置にあり、ノッチが -8 に固定される。set は非常位置を出る条件、reset は非常位置に入る条件である。起動直後の `q` は false（verified）なので、非常位置から始まると読む `[inferred]`。キーが OFF、または編成前後選択が前でないときは、reset がかかる。
2. **`Control Commands TX` の B1**: B1 が true のとき非常制動である。非常位置にあり（`not_q`）、かつ編成前後選択が前のとき、車掌の非常ブレーキのとき、ATS/ATC の B8 のときに true になる。
3. **チャンネル番号の入れ替え（前後反転）**: Onecar Control は、扉 A/B（B4/B5）、前後進（B16/B17）、扉開閉（B27〜B30）、N7 の一部のビットを、前後で読み替える。前方車と後方車で、物理的な A 側、前、右が反転するための処置である。デバッグでは、前後どちらの座標系かを常に意識する。
4. **Simple IF と CC3 の N1/N2**: どちらも N1 がブレーキ、N2 が力行である。Traction Controller もこの割付で読み、Lua の N3 へ力行、N4 へブレーキを渡す。
5. **1 tick の遅延の伝わり方**: 各マイコンのコンポジット出力は、次の tick に下流へ届く。Cab → Onecar → Traction の 3 段では、指令の反映に数 tick かかる。Lua（`n200` FIFO、`n485` VVVF）やラッチも 1 tick の遅延を持つので、`PULSE` のエッジに依存する論理は、tick の順序を確かめる。
6. **NITS FIFO のセンチネル `1<<24`**: 空のキューが出す無効値で、受信側は「データなし」として読み飛ばす。実データに `0x1000000` が現れない前提である。
7. **Lua ウォッチドッグと非常フォールバック**: Lua B17 のトグルが 0.1 秒止まるか、非常ブレーキが 1 秒続くと、フォールバックのコンポジットを選ぶ。これはマスコンの有効判定ではない。
8. **`is_m_car` による役割分担**: ローカルのパンタグラフ状態と牽引供給電圧は、`is_m_car`（`Rolling Stock Settings` B1）が true の車両だけで有効になる。T 車は、Momelink のM車データを中継して使う。
9. **準備済みで未接続のロジック**: Traction の慣性係数の演算、非常制動時の牽引カット、`unused_and` は、外部出力に未接続である。削除済みの機能ではなく、接続の準備だけをした状態として扱う。
10. **ドア操作のインターロック**: 開扉は、許可条件（戸閉連動 OR 速度が ±1.5 m/s 以内）が必須である。閉扉はインターロックなしである。クロス転換も、同じ停車条件でゲートされる。
