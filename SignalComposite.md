# コンポジットインターフェース仕様 (v0.5)

CHUSO Series 2000 で使用されるすべてのコンポジット信号の定義。

**凡例**
- `*B*` / `*N*` はアスタリスクで囲まれたものが「内部専用・将来予約・暫定実装」を示す（元仕様の記法を継承）
- `（要記入）` は未確定のフィールド
- `^` は負論理（スイッチON＝信号OFF）

---

## 目次

1. [制御コマンド系](#制御コマンド系)
   - [Control Commands TX](#control-commands-tx)
   - [Simple Interface RX](#simple-interface-rx)
   - [Extended Commands RX](#extended-commands-rx--nits-ext-input)
   - [Control Commands Type 3 (CC3)](#control-commands-type-3-cc3)
2. [運転台インターフェース](#運転台インターフェース)
   - [Driving Loop](#driving-loop)
   - [Settings Loop](#settings-loop)
   - [Seat Input](#seat-input)
   - [Crew Handle Right / Left](#crew-handle-right--left)
   - [ATS/ATC](#atsatc)
   - [Loop Start](#loop-start)
3. [車両ステータス](#車両ステータス)
   - [Rolling Stock Settings](#rolling-stock-settings--inertia-composite-input)
   - [Rolling Stock Status](#rolling-stock-status)
   - [Monitor Status(IV)](#monitor-statusiv)
   - [Drive Support](#drive-support)
   - [Drive Support Monitor Touch](#drive-support-monitor-touch)
   - [ATP Monitor Touch Composite](#atp-monitor-touch-composite)
4. [牽引・補機](#牽引補機)
   - [Momelink Line from inner Unit](#momelink-line-from-inner-unit)
   - [To Momelink Input & Advanced](#to-momelink-input--advanced)
5. [ドアマイコン](#ドアマイコン)
   - [Phys. Input (Door_Min)](#phys-input-door_min)
   - [Other Inputs (Door_Min)](#other-inputs-door_min)
6. [NITS フレーム仕様](#nits-フレーム仕様)

---

## 制御コマンド系

### Control Commands TX

各先頭車マイコンから編成内へ送出する制御コマンドコンポジット。

優先度順: `0x47 > 0x41-0x43共通部分 > 0x41-0x42共通部分 > 0x41単独部 > 0x42単独部 > 0x48 > 0x60 > 0x49 > 0x4C > 0x43単独部 = 0x4B > 0x4A`

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | 非常ブレーキ | |
| B2 | bool | 連絡ブザ | |
| B3 | bool | 故障 | |
| B4 | bool | 扉A状態（開扉） | |
| B5 | bool | 扉B状態（開扉） | |
| *B6* | bool | （前後選択 前） | |
| *B7* | bool | （前後選択 後） | |
| *B8* | bool | （単行 前後選択正常） | |
| *B9* | bool | （前後選択 短絡） | |
| *B10* | bool | パン上げ | |
| *B11* | bool | パン下げ | |
| *B12* | bool | エンジン始動 | |
| *B13* | bool | エンジン停止 | |
| *B14* | bool | バッテリ起動 | |
| *B15* | bool | バッテリ停止 | |
| B16 | bool | 前進 | |
| B17 | bool | 後退 | |
| B18 | bool | ダイナミックブレーキ自動 | |
| B19 | bool | 案内表示 起動 | |
| B20 | bool | 案内表示 停止 | |
| B21 | bool | チャイム 開始 | |
| B22 | bool | チャイム 停止 | |
| B23 | bool | 室内灯 点灯 | |
| B24 | bool | 室内灯 消灯 | |
| B25 | bool | ヒータ 起動 | |
| B26 | bool | ヒータ 停止 | |
| B27 | bool | 扉A開扉操作 | |
| B28 | bool | 扉A閉扉操作 | |
| B29 | bool | 扉B開扉操作 | |
| B30 | bool | 扉B閉扉操作 | |
| B31 | bool | ID送信（0x47） | |
| B32 | bool | 前後選択 前 かつ 運転台起動 | |
| N1 | number | ブレーキ [0–31] | |
| N2 | number | 力行 [0–7] | |
| N3 | number | ダイナミックブレーキ [0–3] | |
| N4 | number | ブレーキ力 [kPa, 0–1022] | 実際は Rolling Stock Status で上書き |
| N5 | number | 力行パラメータ [0–1023] | 実際は Rolling Stock Status で上書き |
| N6 | number | 0x4C情報 | Ext. Lua の N2 に流し込む |
| N7 | number | packed bool (Ext. B1–B15情報) | 下表参照 |
| *N6* | number | Int. NITS Ext. | |
| *N7* | number | Int. NITS Ext. | |
| *N8* | number | Int. NITS Ext. 有効か？ | |
| *N9* | number | Int. 連結両数 | |

**N7 packed bool (bit0=B1)**

| bit | 信号名 |
|-----|--------|
| B1 | CP起動許可 |
| B2 | SIV起動許可 |
| B3 | クロス転換 |
| B4 | クロス転換 |
| B5 | クロス転換 |
| B6 | 高加速 |
| B7 | 後方1両に対して締切コマンド |
| B8 | 自車締切 |
| B9 | 前方1両に対して締切コマンド |
| B10 | A側開扉操作 |
| B11 | B側開扉操作 |
| B12 | 前方1両を除き締切 |
| B13 | 後方1両を除き締切 |
| B14 | 増圧使用中 |
| B15 | チャイム選択 |

---

### Simple Interface RX

`Simple IF` / `Simple IF RX` は本コンポジットの別名。0x41は排他。0x42と0x43は和で制御。0x47は阻止優先（ID:0が来たときは阻止しない）。

自分より前の車両の情報が小さい番号のチャンネル (1–15) に並ぶ。自分より後の車両の情報が大きい番号のチャンネル (31–17) に並ぶ。自車情報は ch16。コモンライン情報は ch32。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | 非常ブレーキ | |
| B2 | bool | 連絡ブザ | |
| B3 | bool | 故障 | |
| B4 | bool | A側開扉ならON（1両でも開扉ならON） | |
| B5 | bool | B側開扉ならON（1両でも開扉ならON） | |
| B6 | bool | パン上げ | |
| B7 | bool | パン下げ | |
| B8 | bool | エンジン始動 | |
| B9 | bool | エンジン停止 | |
| B10 | bool | バッテリ起動 | |
| B11 | bool | バッテリ停止 | |
| B12 | bool | 0x41の情報更新 | |
| B13 | bool | ID移行阻止を送信（0x47） | |
| B14 | bool | ID移行阻止を受信（0x47） | |
| B15 | bool | ウォッチドッグ | |
| B16 | bool | 前進 | |
| B17 | bool | 後退 | |
| B18 | bool | ダイナミックブレーキ自動 | |
| B19 | bool | 案内表示 起動 | |
| B20 | bool | 案内表示 停止 | |
| B21 | bool | チャイム 開始 | |
| B22 | bool | チャイム 停止 | |
| B23 | bool | 室内灯 点灯 | |
| B24 | bool | 室内灯 消灯 | |
| B25 | bool | ヒータ 起動 | |
| B26 | bool | ヒータ 停止 | |
| B27 | bool | 扉A開扉操作 | Type 3 では不使用 |
| B28 | bool | 扉A閉扉操作 | Type 3 では不使用 |
| B29 | bool | 扉B開扉操作 | Type 3 では不使用 |
| B30 | bool | 扉B閉扉操作 | Type 3 では不使用 |
| B31 | bool | ID移行（0x47） | |
| B32 | bool | 0x41–43共通情報 B1–B4 の更新 | |
| N1 | number | ブレーキ [0–31] | |
| N2 | number | 力行 [0–7] | |
| N3 | number | ダイナミックブレーキ [0–3] | |
| N4 | number | 前側両数 | |
| N5 | number | 前側両数 | |
| N6 | number | 合計両数 | |

---

### Extended Commands RX / NITS Ext. Input

`NITS Ext. Input`（Door_Min）は本コンポジットの別名。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | NITS Extended Command が有効 | |
| B2 | bool | 室内灯（内部ラッチ） | |
| B3 | bool | 案内表示（内部ラッチ） | |
| B4 | bool | パンタ前 ロック | |
| B5 | bool | パンタ前 ロック解除 | |
| B6 | bool | パンタ上昇信号 | |
| B7 | bool | パンタ下降信号 | |
| B8 | bool | パンタ後 ロック | |
| B9 | bool | パンタ後 ロック解除 | |
| B10 | bool | 自車締切ラッチ（内部ラッチ） | Bridge内部で 3000 の Extension Commands N12, N13 参照 |
| B11 | bool | ヒータ（内部ラッチ） | |
| B12 | bool | 増圧ブレーキ（内部ラッチ） | |
| B13 | bool | CP動作中 | |
| B14 | bool | 高加速 | |
| B15 | bool | CP起動許可 | |
| B16 | bool | SIV起動許可 | |
| B17 | bool | L/C・転クロ 潮方転換 | |
| B18 | bool | L/C・転クロ 須方転換 | |
| B19 | bool | L/C ロングシート | |
| B20 | bool | チャイム動作（交通部チャイム） | |
| B21 | bool | チャイム動作（中宗チャイム） | |
| B22 | bool | チャイム停止 | |
| B27 | bool | 扉A開扉操作 | |
| B28 | bool | 扉A閉扉操作 | |
| B29 | bool | 扉B開扉操作 | |
| B30 | bool | 扉B閉扉操作 | |
| B31 | bool | 前方車両締切 | |
| B32 | bool | 後方車両締切 | |
| N1–8 | number | Memory Register Data | memory_registers.txt 参照 |
| N9 | number | Door Mode | |
| N10 | number | Doorcut Front | |
| N11 | number | Doorcut Back | |
| N12 | number | Local Doorcut Front | |
| N13 | number | Local Doorcut Back | |
| N27 | number | Packed 車両情報（上位8bitsから）：力行、制動、未使用、車両存在 | |
| N28 | number | Packed 車両情報（上位8bitsから）：モータ故障、ブレーキ故障、低電圧、SOSボタン | |
| N29 | number | Packed 車両情報（上位8bitsから）：開扉状態、締切状態、警報（理由を問わない）、増圧許可 | |
| N30 | number | 号車番号 | |
| N31 | number | Front Cars | |
| N32 | number | Back Cars | |

---

### Control Commands Type 3 (CC3)

Onecar_Control マイコンが編成前後の先頭車間で送受信するコンポジット。
Control Commands TX のチャンネル定義に基づくが、**後方からの受信時に B27↔B29 および B28↔B30 が入れ替わる**（A側/B側の前後反転）。また B4↔B5 も後方受信時に入れ替わる。

Onecar_Control の信号名との対応を下表に示す。

| ch | 型 | 信号名（Control Commands TX より） | Onecar_Control での net 名 |
|----|-----|--------------------------------------|---------------------------|
| B1 | bool | 非常ブレーキ | b1_or |
| B2 | bool | 連絡ブザ | b2_or |
| B3 | bool | 故障 | b3_or |
| B4 | bool | 扉A状態（後方受信時は B5 と入れ替わり） | b4_or |
| B5 | bool | 扉B状態（後方受信時は B4 と入れ替わり） | b5_or |
| B6 | bool | （要確認：B32相当?） | cc3_front/back_is_front_cab |
| B7 | bool | （要確認） | packed bool の一部 |
| B8 | bool | 自車締切 | door_isolated |
| B9–B15 | bool | 各種コマンド（上表参照） | （要記入） |
| B16 | bool | 前進 | b16_or |
| B17 | bool | 後退 | b17_or |
| B18 | bool | ダイナミックブレーキ自動 | b18_and（AND合成） |
| B19–B26 | bool | 各種コマンド（上表参照） | （要記入） |
| B27 | bool | 扉A開扉操作（後方受信時は B29 と入れ替わり） | （要記入） |
| B28 | bool | 扉A閉扉操作（後方受信時は B30 と入れ替わり） | （要記入） |
| B29 | bool | 扉B開扉操作（後方受信時は B27 と入れ替わり） | （要記入） |
| B30 | bool | 扉B閉扉操作（後方受信時は B28 と入れ替わり） | （要記入） |
| B31 | bool | （要確認） | （要記入） |
| B32 | bool | ID送信（0x47） | id_tx_gated |
| N4 | number | ブレーキ力 [kPa] | brake_force_front/back |
| N5 | number | 力行パラメータ | powering_param_front/back |
| N6 | number | NITS情報 | nits_front/back |
| N7 | number | packed bool（N7 内 B1–B15） | cc3_front/back_b_packed_num |

---

## 運転台インターフェース

### Driving Loop

運転台の操作入力を受け取るループコンポジット。Outputs からスタートし、必要なインパネをぐるぐる回ってからマスコンマイコンに投げ込む。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | 保安装置選択 | |
| B2 | bool | パンタグラフ降下 | |
| B3 | bool | 前灯 | |
| B4 | bool | ハイビーム/減光 | |
| B5 | bool | 乗務員室灯 | |
| B6 | bool | ワンマン右開扉（A側に変更するかも） | |
| B7 | bool | ワンマン右閉扉 | |
| B8 | bool | ワンマン左開扉（B側に変更するかも） | |
| B9 | bool | ワンマン左閉扉 | |
| B10 | bool | ワンマン発車予告 | |
| B11 | bool | （TASC机上スイッチ） | |
| B12 | bool | 乗務員ブザー | |
| B13 | bool | 急行灯（同時制御 or 個別制御-運転台側） | |
| B14 | bool | 電制オフ | |
| B15 | bool | 尾灯強制点灯 | |
| B16 | bool | 急行灯（個別制御-車掌台側） | |
| B17 | bool | ATS-S確認（2300系のみ対応） | |
| B19 | bool | クロスシート転換前方 | |
| B20 | bool | クロスシート転換後方 | |
| B21 | bool | L/Cシートロング転換 | |
| N3 | number | レバーサ（ゲージで設置） | disp |

---

### Settings Loop

起動設定スイッチ類のループコンポジット。`^` は負論理（スイッチON＝信号OFF、起動定位）。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1^ | bool | バッテリ | 負論理 |
| B2 | bool | パン上昇 | |
| B3^ | bool | SIV | 負論理 |
| B4^ | bool | CP | 負論理 |
| B5^ | bool | ワンマン | 負論理 |
| B6^ | bool | ATS/C元 | 負論理 |
| B7 | bool | 旅客案内装置 | |
| B8 | bool | 室内灯 | |
| B9^ | bool | 戸閉連動 | 負論理 |
| B10^ | bool | 自動締切装置 | 負論理 |
| B11 | bool | 救援 | |
| B12 | bool | 高加速 | |
| B13 | bool | 編成前後選択-前 | |
| B14 | bool | 編成前後選択-後 | |
| B15 | bool | 編成前後選択-非常運転 | |
| B16 | bool | 自車締切 | |
| B17 | bool | 他車締切 | |
| B18 | bool | 自車締切 | disp |
| B19 | bool | 他車締切 | disp |
| B20 | bool | A側開扉 | |
| B21 | bool | A側閉扉 | |
| B22 | bool | A側ドア状態 | disp |
| B23 | bool | 発車予告（A側） | |
| B24 | bool | 乗務員ブザー（A側） | |
| B25 | bool | B側開扉 | |
| B26 | bool | B側閉扉 | |
| B27 | bool | B側ドア状態 | disp |
| B28 | bool | 発車予告（B側） | |
| B29 | bool | 乗務員ブザー（B側） | |
| B30 | bool | TASC元 | |
| B31 | bool | 半自動（A側） | |
| B32 | bool | 半自動（B側） | |
| N4 | number | ドラム位置 | disp |
| N5 | number | 保安装置選択 | |

---

### Seat Input

運転台シートの操作入力。すべてモーメンタリ（押している間だけON）。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | 1キー 非常ブレーキ | [W]と同時に操作したとき立ち上がりエッジでEB投入 |
| B3 | bool | 3キー 非常ブレーキ | 立ち上がりエッジでEB投入 |
| B4 | bool | 4キー 乗務員連絡ブザー | 押している間だけブザー送信 |
| B31 | bool | トリガキー マスコン位置ニュートラル操作 | 立ち上がりエッジでマスコン位置をニュートラルに |
| N1 | number | Axis 1 [A][D] | [A](-)で一発ニュートラル操作、[D](+)で1ステップニュートラル側に移動。入力位置保持機能なし |
| N2 | number | Axis 2 [W][S] | [W](+)でブレーキ側、[S](-)で加速側にステップ移動。入力位置保持機能なし |
| N4 | number | Axis 4 [↑][↓] | [↑](+)で逆転器を前、[↓](-)で逆転器を後。入力位置保持機能なし |

---

### Crew Handle Right / Left

右側（A側）・左側（B側）乗務員ハンドルからのコンポジット。Right と Left で同一チャンネル構成。すべてモーメンタリ。

| ch | 型 | 信号名（Right） | 信号名（Left） | 備考 |
|----|-----|---------------|--------------|------|
| B1 | bool | A側開扉 | B側開扉 | |
| B2 | bool | A側閉扉 | B側閉扉 | |
| B3 | bool | 発車予告チャイム | 発車予告チャイム | |
| B4 | bool | 乗務員連絡ブザー | 乗務員連絡ブザー | |

---

### ATS/ATC

ATS/ATC 保安装置からのコンポジット。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | ATC有効 | |
| B2 | bool | ATC 赤灯 | |
| B3 | bool | ATC 緑灯 | |
| B4 | bool | ATC バツ灯 | |
| B5 | bool | ATC 高精度パターン内 | |
| B6 | bool | 予約（前方予告） | |
| B7 | bool | ATS/C 常用最大ブレーキ | |
| B8 | bool | ATS/C 非常ブレーキ | |
| B9 | bool | 予約（緩和ブレーキ） | |
| B10 | bool | ATS起動 | |
| B11 | bool | 確認運転 | |
| B12 | bool | 非常運転 | |
| N1 | number | パターン目標速度 | |
| N2 | number | 照査速度 | |
| N3–9 | number | ATO向け | |

---

### Loop Start

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B18 | bool | 自車締切 | disp |
| B19 | bool | 他車締切 | disp |
| B22 | bool | A側ドア状態 | disp |
| B27 | bool | B側ドア状態 | disp |
| N1 | number | ハイビーム用 | disp |
| N2 | number | ハイビーム用 | disp |
| N3 | number | レバーサ（ゲージで設置） | disp |
| N4 | number | 編成向き | disp |
| N5 | number | 保安装置選択 | |
| N6 | number | マスコン非常位置なら 1 | |

---

## 車両ステータス

### Rolling Stock Settings / Inertia Composite Input

`Inertia Composite Input`（Traction_Controller）は本コンポジットの別名。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B2 | bool | 上下線方向 | 前が上り方向なら ON（Cab_Controller が受信） |
| N1–N4 | number | （要記入） | Traction_Controller が inertia_n1〜n4 として使用 |

---

### Rolling Stock Status

VVVFマイコンは「N3が0以外」でVVVF音声を再生するとよい。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | モータLua故障 | |
| B2 | bool | 故障情報4（内容未定） | |
| B5 | bool | パンタ1 ロック状態 | |
| B6 | bool | パンタ1 上昇状態 | |
| B7 | bool | パンタ2 ロック状態 | |
| B8 | bool | パンタ2 上昇状態 | |
| N1 | number | ~~0x49~~ | |
| N2 | number | BC圧 [kPa] | |
| N3 | number | モータ電流 [A] | |
| N4 | number | パンタ電流 [A] | |
| N5 | number | 架線電圧 [V] | |
| N6 | number | パンタ1の高さ | Main Circuit の内部で設定 |
| N7 | number | パンタ2の高さ | Main Circuit の内部で設定 |
| N8 | number | MR圧 [kPa] | |

---

### Monitor Status(IV)

| ch | 型 | 信号名 | 参照元 |
|----|-----|--------|--------|
| B1 | bool | 保安装置選択シグナル | Drive B1 |
| B2 | bool | ON ハイビーム / OFF 減光 | Drive B4 |
| B3 | bool | ATS/C無効化 | Settings Loop |
| B4 | bool | マスコン非常位置 | |
| B5 | bool | マスコン有効 | |
| B6 | bool | 非常ブレーキ作用 | Simple B1 |
| B7 | bool | 停車ランプ | |
| B8 | bool | 増圧有効 | Ext. B12 |
| B9 | bool | TASC無効化（元） | |
| B10 | bool | TASC有効（仮） | |
| B11 | bool | NITS Extended Command が有効 | Ext. B1 |
| B12 | bool | A側開扉 | |
| B13 | bool | B側開扉 | |
| B14 | bool | 自車締切 | Ext. B10 |
| B15 | bool | 他車締切 | Ext. B32 |
| B16 | bool | 上下線方向 | Inertia Composite B2（前が上り方向なら ON） |
| N1–8 | number | メモリレジスタ | |
| N9 | number | ブレーキ [0–31] | Simple N1 |
| N10 | number | 力行 [0–7] | Simple N2 |
| N11 | number | レバーサ | |
| N12 | number | 編成向き | |
| N13 | number | 速度 [m/s] | |
| N27–32 | number | Ext. のコピー | |

---

### Drive Support

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1 | bool | NITS化メモリレジスタ情報出力中 | |
| B2 | bool | 締切 | |
| B3 | bool | 締切 | |
| B4 | bool | 駅停車ランプ | |
| N1 | number | NITS化メモリレジスタ情報 | |

---

### Drive Support Monitor Touch

Driver_Assistance_IV が出力するタッチUI向けコンポジット。`ui_display_pack` として ch7〜ch32 の 26ch 分が書き込まれる（COMPOSITE_WRITE offset=7）。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B1–B6 | bool | （要記入） | inc で引き継がれる元コンポジットの ch1–6 |
| N7 | number | 運転操作番号 | mon_operation_num |
| N8 | number | ARC値 | mon_arc |
| N9 | number | 操作種別 | mon_op_type |
| N10 | number | 出発駅 | mon_op_dep |
| N11 | number | 到着駅 | mon_op_dest |
| N12 | number | 表示種別 | mon_disp_type |
| N13 | number | 表示目的地 | mon_disp_dest |
| N14 | number | 境界位置 | mon_pos_bound |
| N15 | number | 位置種別 | mon_pos_type |
| N16 | number | 駅位置 | mon_pos_station |
| N17 | number | UIページ番号 | ui_page |
| N18 | number | 速度 百の位 | speed_hundreds |
| N19 | number | 速度 十の位 | speed_tens |
| N32 | number | 操作ID | ui_opid |

---

### ATP Monitor Touch Composite

Cab_Display_IV から Driver_Assistance_IV へ送るタッチUI操作入力コンポジット。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| N1 | number | （要記入） | タッチUI 操作ページ等 |

---

## 牽引・補機

### Momelink Line from inner Unit

中間車（VVVF ユニット）から先頭車マイコンへ受信する Momelink プロトコルコンポジット。

**N1/N2はCHUSO1800 Traction Controller（Momelink-A）が送出する側の仕様であり、
他車から受信する値がこの規約に従うとは限らない**（送信側ごとに定義が異なりうる、
本項目は「To Momelink-A」の送出仕様のみを記す）。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| N1 | number | BC作動比（摩擦系減速度の代理値） | `max(BC[atm abs]-1.45,0)/3.02`。無次元比（0〜1程度）で、実際のm/s²値ではない。BC圧と摩擦制動による減速度がほぼ線形関係にあることを前提に、比率をそのまま「摩擦系減速度」の代理として送出している。**符号は常に正**（方向を持たない） |
| N2 | number | 力行系加速度 [m/s²] | 牽引力（力行・回生等、能動的に力を加える系）による加速度。**符号は車両の物理的前後方向に従う**（前進+・後退-） |
| N15 | number | Momelink ID | 1911 と一致するか判定 |
| その他 | | （要記入） | VVVF制御データの定義 |

---

### To Momelink Input & Advanced

先頭車マイコンから中間車（VVVF ユニット）へ送出する Momelink プロトコルコンポジット。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| N1 | number | normalized_speed | 正規化速度 |
| その他 | | （要記入） | inc で vvvf_data が引き継がれる |

---

## ドアマイコン

### Phys. Input (Door_Min)

ドア開閉センサの位置入力。センサ A・B それぞれ別ポートの `Phys. Input` コンポジットから受信（各 ch1–3）。

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| N1 | number | センサ X座標 | |
| N2 | number | センサ Y座標 | |
| N3 | number | センサ Z座標 | |

---

### Other Inputs (Door_Min)

| ch | 型 | 信号名 | 備考 |
|----|-----|--------|------|
| B10 | bool | （要記入） | door_open_or の入力として使用 |
| その他 | | （要記入） | |

---

## NITS フレーム仕様

CHUSO Series 2000/3000 が使用する編成内情報伝送システム (NITS) のフレームビット定義。
2000系専用フィールドはオレンジ色注記で区別。

送信優先度: `0x47 > 0x41–0x43共通 > 0x41–0x42共通 > 0x41単独 > 0x42単独 > 0x48 > 0x60 > 0x49 > 0x4C > 0x43単独 = 0x4B > 0x4A`

Onecar_Control に FIFO バッファ（`nits_fifo` Lua）が存在し、センチネル値として `1<<24 = 16777216` が使われる。

### 0x47 — 選別ID

**固定値**: `0x4709C7D0` (中宗電鉄 2000系列・3000系列 共通)

ビット列 (bit31–0): `0100 0111 0000 1001 1100 0111 1101 0000`

---

### 0x48 — ドアカット制御

Ext command。1両6ドア以下で制御可能。

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x48` コマンドID |
| 23 | — |
| 22–19 | 扉モード値 [N9] |
| 18 | 扉モードフラグ |
| 17–11 | ドアカット制御値（前）[N10][N12] |
| 10 | フラグ |
| 9–3 | ドアカット制御値（後）[N11][N13] |
| 2 | フラグ |
| 1 | 戸開指令B |
| 0 | 戸開指令A |

---

### 0x49 — パンタ指令 / 車内案内

Ext command。下位ビット ON 時に全体上昇指令で下降。

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x49` コマンドID |
| 23 | 1: 後方 |
| 22–19 | 相対車両位置 |
| 18–12 | — |
| 11 | 他車締切起動 *(2000系)* |
| 10 | 他車締切終了 *(2000系)* |
| 9 | 旅客案内オン |
| 8 | 旅客案内オフ |
| 7 | 室内灯オン |
| 6 | 室内灯オフ |
| 5 | ヒータオン |
| 4 | ヒータオフ |
| 3 | 前方パンタ ロック |
| 2 | 前方パンタ（上昇/下降） |
| 1 | 後方パンタ ロック |
| 0 | 後方パンタ（上昇/下降） |

---

### 0x4A — Car Data Table

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x4A` コマンドID |
| 23 | 増圧許可 |
| 22 | ダブルデッカ |
| 21–18 | 号車番号 |
| 17–16 | 0（予約） |
| 15–14 | 0（予約） |
| 13–12 | パンタ種類（前）※ |
| 11–10 | パンタ種類（後）※ |
| 9–7 | 扉枚数（A側） |
| 6–4 | 扉枚数（B側） |
| 3 | 力行軸（前） |
| 2 | 力行軸（後） |
| 1 | 運転台（左） |
| 0 | 運転台（右） |

※ パンタ種類: 1ビットのみON＝シングルアーム、2ビットON＝菱形・下枠交差

---

### 0x4B — Car Status

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x4B` コマンドID |
| 23 | 力行 |
| 22 | 回生 |
| 21 | 通報装置動作 |
| 20 | 締切中 |
| 19 | 旅客案内 |
| 18 | 室内灯 |
| 17 | ヒータ |
| 16–15 | パンタ昇降状況（前） |
| 14–13 | パンタ昇降状況（後） |
| 12–7 | 扉1枚毎の開扉状況（A側） |
| 6–1 | 扉1枚毎の開扉状況（B側） |
| 0 | door_inv（前後で反転） |

---

### 0x4C — アドレス指定 Ext Command

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x4C` コマンドID |
| 23 | is_swap |
| 22–20 | addr1 |
| 19–0 | ペイロード / addr2 |

---

### 0x60 — 2000系専用 Ext Command

*(2000系のみ。3000系では無視される)*

| bit | フィールド |
|-----|-----------|
| 31–24 | `0x60` コマンドID |
| 23 | — |
| 22 | — |
| 21 | CP起動（協調） |
| 20 | CP停止（協調） |
| 19 | 増圧開始 |
| 18 | 増圧終了 |
| 17 | 高加速（通常）起動 |
| 16 | 高加速終了 |
| 15 | 転換クロスシート 潮方 |
| 14 | 転換クロスシート 須方 |
| 13 | L/C シートロング指定 |
| 12 | — |
| 11 | — |
| 10 | — |
| 9 | — |
| 8 | — |
| 7 | — |
| 6 | — |
| 5–4 | チャイム選択 |
| 3 | SIV/MG起動中 |
| 2 | SIV/MG停止中 |
| 1 | CP起動許可 |
| 0 | CP起動禁止 |
