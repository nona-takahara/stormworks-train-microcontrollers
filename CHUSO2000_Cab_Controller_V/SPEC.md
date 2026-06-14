# Cab Controller V — 予想仕様書

> ソース: `CHUSO2000_Cab_Controller_IV.xml` より変換された `main.sw-net`  
> バージョン: v0.3.0 (project.json より)  
> 解析日: 2026-06-14

---

## 概要

CHUSO Series 2000 向けの運転台コントローラー。座席からの操作入力を受け取り、制御コマンドとして他のマイコンへ送信する。ATS/ATC、乗務員ハンドル、車掌操作、ドア制御、前後表示灯など幅広い機能を統合する。

---

## ポート一覧

### 入力

| ポート名 | 型 | 説明 |
|---|---|---|
| `Seat Input` | composite | 座席の軸・ボタン入力 |
| `Mas-con Key` | boolean | マスコンキースイッチ（ON=キー挿入済み） |
| `Drive Loop` | composite | 走行系ループバック（他マイコンからの状態） |
| `Settings Loop` | composite | 設定系ループバック |
| `Simple Interface RX` | composite | シンプルインターフェース受信 |
| `Extended Commands RX` | composite | 拡張コマンド受信 |
| `ATS/ATC` | composite | ATS/ATC システムからの入力 |
| `Crew Handle Right` | composite | 乗務員ハンドル（右） |
| `Crew Handle Left` | composite | 乗務員ハンドル（左） |
| `Drive Support` | composite | 運転支援システム |
| `Physics Sensor [+Z = front]` | composite | 物理センサー（+Z方向=前方） |
| `Rolling Stock Settings` | composite | 車両設定 |
| `Conductor Em brake 1` | boolean | 車掌非常ブレーキ 1 |
| `Conductor Em brake 2` | boolean | 車掌非常ブレーキ 2 |
| `Conductor Switch Interlock Release` | boolean | 車掌スイッチインターロック解除 |

### 出力

| ポート名 | 型 | 説明 |
|---|---|---|
| `Control Commands TX` | composite | 制御コマンド送信（主出力） |
| `Monitor Status` | composite | モニター表示用ステータス |
| `Main Handle Angle` | number | メインハンドル角度 |
| `Main Handle Sound` | boolean | メインハンドル操作音トリガー |
| `Reverser Position` | number | 逆転器位置（-1=後退, 0=中立, +1=前進） |
| `Reverser Sound` | boolean | 逆転器操作音トリガー |
| `Formation Lever` | number | 列車増解結レバー位置（-0.25/0/+0.25） |
| `Front Sign` | boolean | 前部標識灯 |
| `Tail Sign` | boolean | 後部標識灯 |
| `Express Light (UMI)` | boolean | 急行灯 UMI |
| `Express Light (YAMA)` | boolean | 急行灯 YAMA |
| `High beam` | boolean | ハイビーム（NOT Drive Loop ch3） |
| `Crew Buzzer` | boolean | 乗務員ブザー |
| `ATS/C Reset Signal` | boolean | ATS-C リセット信号（パルス） |

---

## 機能別仕様

### 1. メインハンドル（マスコン）

**入力:** `Seat Input` ch1（軸値 -1.0〜+1.0）  
**ノード:** n6, n7, n8, n9, n11, n12, n20, n21, n35 等

#### ノッチカウンター (n9)
- 軸が +0.5 以上 → 上昇パルス（n11）
- 軸が -0.5 以下 → 下降パルス（n12）
- COUNTER (min=4, max=-7, increment=1) にてノッチを管理
  - 正方向 = 力行ノッチ（最大 +4 と推定）
  - 負方向 = ブレーキノッチ（最大 -7 相当）
- n29: ノッチ == -7 を検出（最大制動位置）

#### SRラッチ n20（EB ゾーン管理）
- **Set 条件（EB状態へ移行）:**
  - 軸が負方向に動いたとき（n12）
  - Seat Input ch30 が ON のとき（n168）
  - Seat Input ch1 の第2読み取り軸（n22）が負方向のとき（n23）
- **Reset 条件（EB解除）:**
  - Seat Input ch2 が ON（n10）
  - 正方向 AND 軸が正側（n31）
  - 軸が正方向パルス AND 最大ブレーキ位置（n62）
  - n479 が OFF（後述の Mas-con Key 条件が成立していない場合）
- `q (n20_q)` = EB ゾーン内、`not_q (n20_not_q)` = EB ゾーン外

#### NUM_SWITCHBOX n48
- EB ゾーン外 (n20_not_q=ON) → n9_out（ノッチ値）を出力
- EB ゾーン内 → 定数 -8 を出力（非常制動位置）

#### ハンドル角度出力 (Main Handle Angle)
プロパティトグル `n619` で 2 モードを切り替え：
- **Angle モード（デフォルト）:** `(-x-2)/25`（x=ノッチ値）→ 角度へ変換
- **TETSUDAN MOD:** ノッチ値をそのまま出力

#### 操作音 (Main Handle Sound)
- ノッチ値の DELTA がプラス（変化あり）→ TOGGLE でパルス出力

---

### 2. 逆転器

**入力:** `Seat Input` ch3（軸値）  
**ノード:** n102〜n119

- 軸 +0.5 以上 → 前進パルス（n105）
- 軸 -0.5 以下 → 後退パルス（n106）
- COUNTER (reset=-1, min=-1, max=1)
  - -1 = 後退 (R), 0 = 中立 (N), +1 = 前進 (F)
- Mas-con Key が OFF (n258=NOT) → カウンターリセット（中立固定）
- **Reverser Sound:** 逆転器の変化（DELTA > 0）でパルス出力

---

### 3. 列車増解結レバー（Formation Lever）

**入力:** `Settings Loop` ch12（アップ）, ch13（ダウン）  
**ノード:** n254〜n264

- COUNTER (reset=-1, min=-1, max=1)
- 出力: `x/4` → -0.25 / 0 / +0.25 として `Formation Lever` へ
- n257: 値 == +1 を検出（最前端）
- n473: 値 == -1 を検出（最後端）→ Control Commands TX へ

---

### 4. 非常制動（Emergency Brake）

**ノード:** n525

以下いずれかが成立した場合に EB 信号を発する（Control Commands TX ch1）：

| 条件 | 信号源 |
|---|---|
| 車掌非常ブレーキ 1 | `Conductor Em brake 1` |
| 車掌非常ブレーキ 2 | `Conductor Em brake 2` |
| ATS/ATC ch7 が ON | `ATS/ATC` channel 7 |
| Mas-con Key ON かつ Formation +1 かつ handle EB 外 | n479 AND n20_not_q |

---

### 5. ATS/ATC 連携

**入力:** `ATS/ATC` composite  
**関連チャンネル:**

| ch | 用途 |
|---|---|
| 7 | EB トリガー（n326） → 非常制動、ブレーキ上限変更 |
| 6 | ブレーキ上限変更（n327） → ATS 速度制限ブレーキ（-8 に制限） |
| 8 | ブレーキ上限変更（n328） → 部分制限ブレーキ（-4 に制限） |

NUM_SWITCHBOX n319/n321/n322 と FUNC_NUM_8 n320 で、ATS 状態に応じてブレーキノッチ上限を制限する：
- 通常時: n9_out（最大 -7 まで）
- ATS ch7 ON: 定数 -8 に固定
- ATS ch6 ON: 上限 -8 に変更
- ATS ch8 ON: 上限 -4 に変更
- 最終的に `min(min(x,y),min(z,w))` → 最も制限の強いブレーキを選択

#### ATS-C リセット信号
- n20 の not_q が OFF→ON（EB解除直後）にパルス出力（n633, mode=0）

---

### 6. 制御コマンド送信（Control Commands TX）

**ノード:** n448（数値合成）→ n456（ブール合成）→ `Control Commands TX`

#### 数値チャンネル（n448, offset=0, count=7）

| ch | 内容 | 計算式 |
|---|---|---|
| 1 | ブレーキ力 | `clamp((-x - min(0, x+6)) * 4, 0, 31)` (x=有効ノッチ値) |
| 2 | 力行力 | `max(x, 0)` (x=有効ノッチ値) |
| 6 | 運転支援 数値 | Drive Support ch1 |
| 7 | モニター状態数値 | 後述 Monitor Status 数値部 |

**ブレーキ計算の意味:**  
- x ≥ 0 → ブレーキ = 0（力行または中立）  
- x = -1〜-6 → ブレーキ = `(-x) * 4`（0〜24）  
- x ≤ -7 → ブレーキ = `(-x - min(0, x+6)) * 4` → 段階的に増加  
- x = -8 (EB) → ブレーキ = 最大値

#### ブールチャンネル（n456, offset=0）

| ch | 内容 |
|---|---|
| 1 | 非常制動フラグ |
| 2 | クルーブザー（または何らかのアラーム） |
| 6 | Formation Lever = +1 |
| 7 | Formation Lever = -1 |
| 9 | Settings Loop ch14 |
| 10 | Settings Loop ch1 |
| 11 | Drive Loop ch1 |
| 16 | 逆転器 前進 (Reverser = +1) |
| 17 | 逆転器 後退 (Reverser = -1) |
| 18 | NOT Drive Loop ch13 |
| 19 | Settings Loop ch6 立ち上がりパルス |
| 20 | Settings Loop ch6 立ち下がりパルス |
| 21 | n277 立ち上がりパルス（後述ドア系） |
| 22 | n277 立ち下がりパルス |
| 23 | Settings Loop ch7 立ち上がりパルス |
| 24 | Settings Loop ch7 立ち下がりパルス |
| 27 | ドア右 開信号 A（インターロック付き） |
| 28 | ドア右 開信号 B（インターロックなし） |
| 29 | ドア左 開信号 A（インターロック付き） |
| 30 | ドア左 開信号 B（インターロックなし） |
| 31 | NOT（逆転器が正方向に変化） |
| 32 | Mas-con Key AND Formation +1 |

---

### 7. ドア制御

**入力:** `Crew Handle Right`, `Crew Handle Left`, `Drive Loop`, `Settings Loop`

#### 右側ドア

- **n288（インターロック付き）:** `(Settings Loop ch19 OR Crew Handle Right ch1 OR Drive Loop ch5) AND n397`
- **n292（インターロックなし）:** `Settings Loop ch20 OR Crew Handle Right ch1 OR Drive Loop ch6`

#### 左側ドア

- **n296（インターロック付き）:** `(Settings Loop ch24 OR Crew Handle Left ch1 OR Drive Loop ch7) AND n397`
- **n300（インターロックなし）:** `Settings Loop ch25 OR Crew Handle Left ch1 OR Drive Loop ch8`

#### n397（ドア操作許可条件）
`n396 (Settings Loop ch8) OR n398 (速度ほぼ0: Physics ch8 範囲 -1.5〜1.5)`

#### Crew Buzzer トリガー (n144, n316)
以下いずれかが ON のときブザー発報（BOOL_FUNC_8 OR 結合）：
- Simple Interface RX ch1
- Seat Input ch3
- Settings Loop ch23, ch28
- Drive Loop ch11
- Crew Handle Right ch3
- Crew Handle Left ch3

---

### 8. 前部・後部標識灯

#### Front Sign (n356, SR ラッチ)
- **Set 条件（点灯）:**
  - Drive Loop ch2 が ON（前方走行方向一致）かつ Formation = +1（n360）
  - Drive Loop ch2 の立ち上がりパルス（n363）
- **Reset 条件（消灯）:**
  - Formation +1 の立ち下がりパルス（n361）
  - Drive Loop ch2 の立ち下がりパルス（n362）

#### Tail Sign (n373, OR)
- 逆転器 = -1（後退位置）
- Drive Loop ch14 が ON

---

### 9. 急行灯・ハイビーム

| 出力 | ソース |
|---|---|
| `Express Light (UMI)` | Drive Loop ch12 |
| `Express Light (YAMA)` | Drive Loop ch15 |
| `High beam` | NOT Drive Loop ch3 |

---

### 10. Monitor Status 出力

**ノード:** n566（ブール）→ n567（数値）→ `Monitor Status`

#### ブールチャンネル（n566, offset=0, count=16）

| ch | 内容 |
|---|---|
| 1 | Drive Loop ch1 |
| 2 | Drive Loop ch3 |
| 3 | Settings Loop ch5 |
| 4 | n20_not_q（ハンドルが EB ゾーン外） |
| 5 | Mas-con Key AND Formation +1 |
| 6 | Simple Interface RX ch1 |
| 7 | Drive Support ch3 |
| 8〜10 | 常時 true（CONST_BOOL false の NOT） |
| 11 | Extended Commands RX ch1 |
| 12 | Simple Interface RX ch3 または ch4 |
| 13 | Simple Interface RX ch4 |
| 14 | Extended Commands RX ch9 |
| 15 | Extended Commands RX ch31 |
| 16 | Rolling Stock Settings ch1 |

さらに `Extended Commands RX` の内容を inc として連結している（パススルー）。

#### 数値チャンネル（n567, offset=8, count=5）

| ch | 内容 |
|---|---|
| 9 | Simple Interface RX ch1 (number, n622) |
| 10 | Simple Interface RX ch1 (number, n623) ※重複の可能性 |
| 11 | 逆転器位置（-1/0/+1） |
| 12 | Formation Lever カウンター値（-1/0/+1） |
| 13 | Physics Sensor ch8（前後速度） |

---

### 11. 速度判定

**ノード:** n590, n394, n395, n396, n397, n398, n503, n504, n505

- `Physics Sensor [+Z = front]` ch8 = 前後方向速度
- THRESHOLD(-1.5, 1.5) → 停車中（ほぼ速度ゼロ）を検出 → ドア操作許可
- n503: 逆転器位置の DELTA → 変化検出
- n504: THRESHOLD(0,1) → 正方向変化
- n505: NOT → Control Commands TX ch31 へ（逆転器が後退方向に変化したとき ON）

---

## 未解明・要確認事項

1. **n9 カウンターの min/max 解釈:** `min=4, max=-7` の引数順序が通常と逆に見える。実際のノッチ範囲（力行最大/制動最大）の確認が必要。

2. **Seat Input のチャンネルマッピング:** ch1=メインハンドル軸、ch2=ブール（EB解除スイッチ?）、ch3=逆転器軸、ch30=ブール の用途詳細。

3. **n622 と n623 の重複:** 両方とも Simple Interface RX ch1 を読んでいる。意図的か？

4. **n277 の詳細（ドア系パルス源）:**  
   `Settings Loop ch22, ch27 OR Crew Handle Right ch2 OR Crew Handle Left ch2 OR Drive Loop ch9`  
   → ドア閉信号？ それとも別の用途？

5. **Control Commands TX ch9〜ch11, ch18〜ch20 の受け手マイコン側の解釈。**

6. **Drive Support の ch1〜ch3 の意味**（数値1つ、boolean2つを使用）。

7. **`Conductor Switch Interlock Release` は n575/n617 経由で Drive Loop ch12/ch15 に接続されているが、本マイコン内での使用箇所が不明確**（Drive Loop を経由して別マイコンで処理される可能性）。
