# CHUSO2000_Cab_Display_IV SPEC

## 機能概要

運転台表示マイコン（Display IV）。Monitor Status コンポジットから各種信号を読み込み、以下のビデオ出力を生成する。

- **Main Monitor**: ATS/ATC画面・メイン画面を合成したメインモニタ映像
- **ATP Switch**: ATPページ切り替えビデオ（ATP モニタータッチで操作）
- **Electricity Display**: 架線電圧・電流・packed車両情報を表示するビデオ
- **ARC**: 走行距離計算値（km 上位・下位を合成した数値）
- **ATC Train Length**: 編成両数から計算した列車長（m）
- **Loop Start, ATS/C Settings**: ハイビームX/Y位置・レバーサ・編成向き・ドア締切状態をループに出力

## 命名規則

### インスタンス名

| パターン | 意味 |
|---|---|
| `ms_bXX_<name>_read` | Monitor Status Boolean チャンネル読み込み |
| `ms_nXX_<name>_read` | Monitor Status Number チャンネル読み込み |
| `rs_nX_<name>_read` | Rolling Stock Status Number チャンネル読み込み |
| `lua_<role>` | LUA インスタンス（役割名） |
| `<target>_num_write` | COMPOSITE_WRITE_NUMBER（ターゲット別） |
| `<target>_bool_write` | COMPOSITE_WRITE_BOOLEAN（ターゲット別） |
| `prop_<name>` | PROPERTY_NUMBER プロパティ入力 |
| `<signal>_sw` | NUM_SWITCHBOX スイッチ |
| `<signal>_read` | COMPOSITE_READ 各種 |
| `const_<meaning>` | CONST 定数 |

### ネット名

| パターン | 意味 |
|---|---|
| `ms_b2_high_beam` | Monitor Status B2（ハイビーム/減光） |
| `ms_b4_eb_pos` | Monitor Status B4（マスコン非常位置） |
| `ms_b5_mascon_active` | Monitor Status B5（マスコン有効） |
| `ms_b6_eb_active` | Monitor Status B6（非常ブレーキ作用） |
| `ms_n13_speed` | Monitor Status N13（速度 m/s） |
| `rs_n2_bc_press` | Rolling Stock Status N2（BC圧 kPa） |
| `rs_n5_line_voltage` | Rolling Stock Status N5（架線電圧 V） |
| `rs_n3_motor_current` | Rolling Stock Status N3（モータ電流 A） |
| `line_voltage_smoothed` | 架線電圧スムージング済み値 |
| `motor_current_smoothed` | モータ電流スムージング済み値 |
| `atp_page` | ATPページ番号（1 or 2） |
| `atp_page_toggled` | ATPページトグル状態 |
| `formation_dir_clamped` | 編成向き（max(x,0) でクランプ済み） |
| `beam_x` / `beam_pos` | ハイビームX位置 / Y位置 |
| `*_composite` | 各用途のコンポジット信号 |
| `*_video` | 各LUA段のビデオ出力 |

## 論理グループ構成（main.sw-net 並び順）

1. Monitor Status 読み込み Boolean
2. Monitor Status 読み込み Number
3. Rolling Stock Status 読み込み
4. ATP Monitor Touch 読み込みとページ切り替えロジック
5. ATP Switch ビデオ出力
6. ハイビーム/ライト位置
7. ARC (走行距離計) 計算
8. ATC 列車長計算
9. Loop Start, ATS/C Settings 出力
10. 架線電圧・電流スムージング（指数平滑）
11. Electricity Display ビデオ出力
12. ATS/C 画面用コンポジット組み立て
13. メイン画面用コンポジット組み立て
14. ビデオレンダリングパイプライン

## Lua スクリプト詳細

### lua_atp_switch (n390.lua) — ATPスイッチアイコン描画

`input.getNumber(1)` を読み取り、パンタグラフアイコンを描画する。

| 値 | 表示 |
|----|------|
| 1 | 片側パンタ上昇（青緑色） |
| 2 | 両パンタ上昇（青緑色） |
| その他 | パンタ降下 |

---

### lua_elec_disp (n576.lua) — 電気系ディスプレイ

車両の電気情報（CV・MA・ドア戸閉状況）を 32×64 px の縦型パネルとして描画。

| 入力 | 内容 |
|------|------|
| N1 | info0（packed: ドア存在ビット等） |
| N2 | info2（packed: ドアカット・開扉状態等） |
| N3 | CV（定速目標速度、スケール 1/20×3 = km/h換算） |
| N4 | MA（モータ電流） |
| B1 | bound（上下線方向） |

ドア戸閉判定: cc両のうち (cc-1) 両が戸閉（DC ビット on）なら `Closed=true` → 中央インジケータを緑表示。

---

### lua_top_screen (n81.lua) — メータ画面

スピードメータ（0–300 km/h）・ブレーキ計・BC圧計・MR圧計を 48×64 px で描画。

| 入力 | 内容 |
|------|------|
| N1 | ブレーキノッチ [0–31] |
| N4 | 速度 [m/s] → 3.6倍で km/h 換算 |
| N5 | BC圧（スケール 1/98） |
| N6 | MR圧 − 1 |
| B1 | 非常ブレーキ作用 |
| composite | ats_screen_composite |

---

### lua_ats_screen (n334.lua) — ATS/ATC画面

ATS/ATC のシグナル・速度パターン位置・各灯を描画。

| 入力 | 内容 |
|------|------|
| N1 (idc) | パターン目標速度 [km/h] → 速度ドット位置 |
| B1 | ATC有効 |
| B2 | 赤信号 |
| B3 | 青信号 |
| B4 | バツ灯 |
| B5 | 高精度パターン内（点滅） |
| B6 | 前方予告（点滅） |
| B10 | ATS起動 |
| composite | "ATS/ATC" |

速度パターン: idc を 5 km/h 刻みの座標テーブルにマッピングしてドット表示（0–110 km/h）。

---

### lua_ats_overlay (n349.lua) — ATS オーバーレイ

非常ブレーキ・NITS・TASC・ドア戸閉・乗客ブザー等のアイコンをオーバーレイ描画。

| 入力 | 内容 |
|------|------|
| N1 (B) | ブレーキ値 (>0 でブレーキアイコン表示) |
| N2 (PP) | 力行パラメータ（0以外で力行アイコン表示） |
| B1 | 非常ブレーキ (EB) |
| B2 | NITS有効 |
| B3 | Ctrl（戸閉かつ出発条件） |
| B4/B5 | ドアA/B状態（どちらも false で DCls=true → 戸閉アイコン緑） |
| B6 | 乗客ブザー押下 (PBPres) |
| B7 | 次停車 (NextStop) |
| B8 | TASC有効 |

---

### lua_main_monitor (n415.lua) — 車両状態パネル

Extended Commands RX の packed 車両情報 (N27/N28/N29) を 6 両分デコードして表示。

| 入力 | 内容 |
|------|------|
| N27 (info0) | 車両存在・モータ状態等のパックビット |
| N28 (info1) | モータ電流・制動状態等のパックビット |
| N29 (info2) | ドア状態・締切状態等のパックビット |
| N31/N32 | 前側・後側両数 → carcnt = N31 + N32 + 1 |
| B1 | bound（上下線方向、表示順序） |

各両の表示ドット（4行 × 6両）:
- 行1 (y=15): 車両存在 (CE、黄緑) / 締切フォース (DClose、赤)
- 行2 (y=19): モータ故障 (Me、赤) / ブレーキ状態 (Mc、橙)
- 行3 (y=23): ドアカット (DC、赤)
- 行4 (y=27): パンタ故障 (PNr、赤) / パンタ正常 (PNg、橙)

---

### lua_main_screen (n419.lua) — 保安装置種別表示

保安装置選択番号から車両形式アイコンを描画する。

| 入力 | 内容 |
|------|------|
| N1 (J) | 補助数値（2桁表示） |
| N2 | 保安装置コード。`(N2//100)%100` の下2桁で装置種別、`(N2//10000)%10` で上下線方向表示 |

保安装置種別 (`i` 値):

| i | 表示 |
|---|------|
| 1 | ATC (赤系) |
| 2 | ATC 変形 (赤) |
| 3 | ATS-P 等 (赤) |
| 4 | ATC-S / 基本 (緑) |
| 6 | モード6 (緑) |
| 7 | モード7 (赤) |

---

## スムージング方式

架線電圧と電流には指数平滑フィルタを適用。式:

```
(e^(-a)) * (delta + (prev - raw) * (a+1)) + raw
```

係数 `a = 0.4`（`const_smooth_factor`）、底は自然対数の底 `e ≈ 2.71828`（`const_euler`）。
