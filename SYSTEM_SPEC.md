# 中宗電鉄 2000系列 マイコンシステム 詳細仕様書

> - 対象: `CHUSO2000_*` 配下の各 `main.sw-net` および付随 Lua スクリプト
> - 参照仕様: `SignalComposite.md` (v0.4), `CabComposite.md`, `NITS.md`
> - 改訂日: 2026-06-14
> - 本書は各マイコン単体の `SPEC.md` を統合し、システム全体のデータフロー・状態機械・プロトコルをエンジニアが実装・デバッグに使える形でまとめたものである。

---

## 0. 凡例・前提知識

- sw-net の `inst` 行は `型ID 名前 (パラメータ): 入力 -> 出力` 形式。
- `COMPOSITE_READ_*` の `channel=N` が読み出すチャンネル。`channel=-1` + `channel_input` は動的チャンネル指定。
- `COMPOSITE_WRITE_*` の `inK` は出力 composite のチャンネル `K + offset - 1` に書き込む。`inc` は元 composite をパススルーし、書かれないチャンネルはそのまま流れる。
- 「B」=ブールチャンネル、「N」=数値チャンネル。チャンネル番号は 1 始まり。
- Stormworks のロジックは 1 tick (1/60 s) ごとに評価され、`MEMORY_REGISTER`・`SR_LATCH`・`CAPACITOR`・Lua はフィードバックループ上で **1 tick 遅延** を持つ。コンポジット間の信号伝搬も各マイコン 1 tick の遅延がある。

---

## 1. システム概要

CHUSO 2000系の制御は、**1両単位の運転台ユニット**と**編成内通信（Momelink / NITS）**の二層で構成される。マイコンは大きく次の 6 種に分かれる。

| マイコン | 役割 | 主な入力 | 主な出力 |
|---|---|---|---|
| **Cab Controller V** | 運転台制御の中核。マスコン・逆転器・ドア・標識灯・各種スイッチを集約し、制御コマンドと表示ステータスを生成 | Seat Input, ATS/ATC, Crew Handle L/R, Drive/Settings Loop, Physics, Drive Support | Control Commands TX, Monitor Status, ハンドル角度/音, 標識灯 |
| **Cab Display IV** | 運転台モニタ表示。Monitor Status / Rolling Stock Status を映像化 | Monitor Status, Rolling Stock Status, タッチ | Main Monitor 映像, ARC, 列車長, Loop Start |
| **Driver Assistance IV** | 運転支援。GPS+距離程から次駅・接近・停車・締切を判定 | Monitor Status, Physics, タッチ | Drive Support, 映像, Beep |
| **Traction Controller** | 牽引制御 (VVVF)。ノッチから力行/制動・BC圧・電力を計算。パンタ/DB/高加速/Momelink を管理 | Simple IF, Extended Commands RX, Physics, Voltage, BC, MR, Inertia, Momelink | Output (Watt), BC Target, Rolling Stock Status, Momelink, ブレーキ音 |
| **Onecar Control** | 単車制御。前後 2 運転台の Control Commands Type 3 (CC3) を合成し下流へ分配。NITS FIFO・Simple IF 前後反転 | CC3 from Front/Back, Simple IF RX | CC3 (統合), Simple IF RX inverted |
| **Door Min** | ドア最小制御。センサ間距離で開閉エリア判定、NITS 指令で開扉、モータ速度とチャイムを出力 | Phys. Input ×2, Other Inputs, NITS Ext. | Door is Open, Chime High/Low, モータ速度 |

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

Cab Controller の `Control Commands TX` は車両ブリッジ/ゲートウェイ（`Signal_Gateway.xml` / `Signal_Bridge`）で NITS パケット化され、編成内に分配される。Onecar Control はその NITS から復元された前後 2 系統の CC3 を受けて単車向けに統合する。

---

## 2. マイコン間インターフェース（コンポジット信号）

主要なコンポジットの定義元と内容は `SignalComposite.md` / `CabComposite.md` を正典とする。流れの要点:

| コンポジット | 送信元 → 受信先 | 内容 |
|---|---|---|
| **Control Commands TX** | Cab Controller → Bridge/Gateway | N1 ブレーキ[0-31], N2 力行[0-7], N6 NITS Ext, N7 NITS 0x60 ペイロード数値, B1 非常制動, B6/B7 前後選択, B16/B17 前後進, B27-B30 扉開閉, B32 運転台起動 等 |
| **Control Commands Type 3 (CC3)** | (前後運転台) → Onecar Control → 牽引/ドア | 上記を 1 両向けに正規化したもの。B6=front_cab ビット |
| **Simple Interface RX / Simple IF** | 編成バス → 各車 | N1 ブレーキ, N2 力行, N4/N5 前後両数, B1 非常制動, B16/B17 方向, B18 DB自動 等。自車=ch16, 前車=1-15, 後車=17-31, コモン=32 |
| **Extended Commands RX** | Bridge → 牽引/Cab | N9 扉モード, B1 NITS Ext 有効, B4-B9 パンタ ロック/昇降, B10 自車締切ラッチ, B14 高加速, B32 後方車両締切 等 |
| **Monitor Status** | Cab Controller → Display / Driver Assistance | B1-B16 状態ビット, N9 ブレーキ, N10 力行, N11 レバーサ, N12 編成向き, N13 速度, N27-32 Ext コピー（`SignalComposite.md` Monitor Status(IV) 参照） |
| **Drive Support** | Driver Assistance → Cab Controller | N1 NITS化メモリレジスタ, B1 出力中, B2/B3 締切(前/後), B4 駅停車ランプ |
| **Rolling Stock Status** | Traction Controller → Display | N2 BC圧, N3 モータ電流, N4 パンタ電流, N5 架線電圧, N8 MR圧, パンタ状態ビット |
| **Rolling Stock Settings** | 設定 → 牽引/Cab | B1 is_m_car, B2 編成向き(上り) |
| **Inertia Composite** | 設定 → 牽引 | N1-4 慣性係数 a/b/c/d |
| **Momelink** | 牽引↔編成内ユニット | ID=1911, N1 CV, N23 パンタ電圧 |

> 注: `Simple Interface RX` と `Control Commands TX`/`CC3` でチャンネル N1/N2 のブレーキ/力行の割当が入れ替わる箇所があるため、参照側の `channel=` を必ず確認すること（後述 §9 参照）。

---

## 3. 各マイコン詳細

### 3.1 Cab Controller V

運転台コントローラ。最大の sw-net で、座席・スイッチ群を集約する。

#### 入出力ポート（主要）
- **入力**: Seat Input, Mas-con Key, Simple Interface RX, Physics Sensor [+Z=front], Drive Loop, Settings Loop, ATS/ATC, Crew Handle Right/Left, Conductor Switch Interlock Release, Drive Support, Conductor Em brake 1/2, Extended Commands RX, Rolling Stock Settings
- **出力**: Control Commands TX, Monitor Status, Main Handle Angle/Sound, Reverser Position/Sound, Formation Lever, Front/Tail Sign, Express Light (UMI/YAMA), High beam, Crew Buzzer, ATS/C Reset Signal

#### 主要機能ブロック

**(a) メインハンドル（マスコン）ノッチカウンタ** — `notch_counter` (COUNTER, min=4, max=-7)
- Seat ch2 軸（[W]/[S]）の ±0.5 閾値でノッチ up/down。`CAPACITOR(0.3s)+BLINKER(0.1/0.1)` でホールド時リピートパルスを生成。
- Seat ch1 軸（[A]/[D]、センター戻し）はノッチを中立方向へ寄せる。`notch_up_src` は `eb_q`（EB中）と AND され、EB 中のみ加速方向操作を有効化。
- 正方向 = ブレーキ、負方向 = 力行（カウンタ値）。`min=4, max=-7` の引数順は実装上の慣習で、可動域は -7（常用最大制動）〜+4（力行最大）。

**(b) 非常ブレーキ (EB) ラッチ** — `eb_latch` (SR_LATCH)
- **set（= EB 解除）**: `handle_neg_rise | eb_set_src | center_ax_pos_rise`
- **reset（= EB 投入）**: `pos_at_min | eb_reset_btn_pos | moterman2_key | (!mascon_active)`
- `eb_q` = EB 投入中、`eb_not_q` = 通常。**負論理に注意**: set 側が EB 解除、reset 側が EB 投入である（§9 参照）。
- 常用最大ブレーキ(-7)で更に [W] を入れると `pos_at_min` 経由で EB へ引き継ぎ。一度離して再投入が必要なインターロック付き。
- EB 中は `mascon_eb_sw` がノッチを **-8 固定**にする。

**(c) 逆転器** — `reverser_counter` (COUNTER, min=-1, max=1)
- Seat ch4 軸の ±0.5。Mas-con Key OFF (`not_mascon_key`) でリセット（中立固定）。-1=後退/0=中立/+1=前進。

**(d) 編成前後レバー** — `formation_counter` (COUNTER, reset=-1, min=-1, max=1)
- Settings Loop B13(up)/B14(dn)。`Formation Lever = x/4`（-0.25/0/+0.25）。`form_is_fwd`(=+1) と `form_is_rear`(=-1) を多用。
- **マスコン有効条件** `mascon_active = Mas-con Key AND form_is_fwd`。前方選択かつキー挿入で初めて力行/制動が出る。

**(e) ATS ブレーキ上限** — `eff_notch = min(min(mascon_val, ats_lim_eb), min(ats_lim_full, ats_lim_half))`
- ATS/ATC B8→EB(-8), B7→全制限(-8), B9→半制限(-4)。`ats_lim_en`（故障/B側開扉なし or 戸閉連動）で各制限を有効化。最も強い制限が採用される。

**(f) 力行/制動コマンド計算**
- `power_cmd = max(eff_notch, 0)` → TX N2
- `brake_cmd = clamp((-x - min(0, x+6)) * 4, 0, 31)` → TX N1
  - x≥0→0、x=-1..-6→(-x)*4、x≤-7 で更に増加し EB(-8) で最大。

**(g) ドア制御**（§7 へ）／**(h) NITS 0x60 ペイロード**（§4 へ）／**(i) 標識灯**

- **Front Sign**: SR ラッチ。set = `headlamp_rise | (headlamp AND form_is_fwd)`、reset = `headlamp_fall | form_fwd_fall`。
- **Tail Sign**: `form_is_rear OR Drive Loop B15(尾灯強制)`。
- **High beam**: Drive Loop B4 の NOT。
- **Express (UMI/YAMA)**: Drive Loop B13/B16 のパススルー。

**(j) Control Commands TX 組み立て** — `tx_num_build`(N1-N7) + `tx_bool_build`(B1-B32)
- B1=`em_brake`（非常制動 failsafe: 通常走行で 1）, B2=ブザー, B6=`form_is_fwd`, B7=`form_is_rear`, B16/B17=逆転器, B27-B30=扉開閉, B32=`mascon_active`。
- N6=`ds_nits_mem`(Drive Support N1), N7=`nits60_num`(0x60 ペイロード)。

**(k) Monitor Status 組み立て** — `mon_bool_build`(B1-16) + `mon_num_build`(N9-13)
- B4=`eb_not_q`, B5=`mascon_active`, B6=`si_b1_eb`, B7=`ds_stop_lamp`, B16=`rss_dir`。
- N9=Simple IF N1 ブレーキ, N10=N2 力行, N11=逆転器, N12=編成, N13=速度。Extended Commands RX を `inc` でパススルー（N27-32 等）。

#### 注意点
- `em_brake` は failsafe 設計。`eb_form_fwd = eb_not_q AND form_is_fwd`（通常走行＝B1 ON）と車掌 EB / ATS EB の OR。
- `unused_sign_latch` 系は旧 Express 実装の残骸（出力未接続）。

---

### 3.2 Cab Display IV

運転台モニタ表示。Monitor Status / Rolling Stock Status を読み、複数の Lua で映像を合成する。

- **出力映像**: Main Monitor（ATS/ATC + メイン合成）, ATP Switch, Electricity Display, ARC（走行距離 km 上下位合成）, ATC Train Length（編成両数→列車長 m）。
- **Loop Start / ATS/C Settings 出力**: ハイビーム X/Y, レバーサ, 編成向き, ドア締切状態をループへ返す。
- **スムージング**: 架線電圧・モータ電流に指数平滑 `(e^-a)*(delta+(prev-raw)*(a+1))+raw`、a=0.4。
- 命名は `ms_bXX_*` / `ms_nXX_*`（Monitor Status）, `rs_nX_*`（Rolling Stock Status）。

---

### 3.3 Driver Assistance IV

運転支援。物理量と Monitor Status から次駅・接近・停車・締切を判定し、`Drive Support` と映像を生成する。詳細ロジックは §8。

- **ポート**: in = Monitor Status, Physics Input, Drive Support Monitor Touch / out = Drive Support, Output(video), Monitor Beep。
- **Lua 群**: `n61`(運転支援コア), `n130`(Monitor 解析), `n105`(タッチ UI), `n106`(表示生成), `n107/n115/n127`(描画), `n141`(Drive Support 出力)。
- **接近/停車ラッチ**: `approach_latch`, `arrival_latch`（§8.2）。
- **メモリレジスタ 1-7**: タッチ UI から運行情報を保持し Drive Support N1-N6 / N8(page) に出力。`memreg7` は距離程補正に使用（`spd_correction`）。

---

### 3.4 Traction Controller

牽引制御 (VVVF)。`scripts/n485.lua` がトルク・電流計算の本体。

#### 入出力ポート
- **入力**: Physics Input(ch9=速度), Voltage, Simple IF, Momelink Line, Extended Commands RX, Inertia Composite, BC, MR, Rolling Stock Settings
- **出力**: Output (Watt), To Momelink Input & Advanced, Rolling Stock Status, BC Target, Brake sound

#### 主要ブロック
- **方向**: Simple IF B16/B17 → `direction`(+1/-1/0)。
- **VVVF Lua 入力**: N1 速度, N2 電圧, N3 ブレーキノッチ, N4 力行ノッチ, N5 方向, N6 CV, N7 cv_default, N8/N9 牽引パラメータ。ブール: mascon, high_accel, db_auto_not, is_m_car。
- **VVVF Lua 出力（n485）**: ch1 力行ノッチ(補正後), ch2 ブレーキノッチ, ch15=1911(ID), ch17 watchdog, ch20 回生フラグ, ch23 パンタ電圧, ch24 パンタ電流, ch29 モータ電流。
- **マスコン有効化ラッチ** — `mascon_enable`: Lua ch17(watchdog) の変化エッジを `OR→XOR→NOT→CAPACITOR(0.1s)` で検出し、`mascon_hold_cap(1s)` との OR で `mascon_enable_comb` を維持。マスコン有効中は Lua 出力、無効中は Momelink の CV データへ `vvvf_data_sw` で切替。
- **BC 圧計算**: `BC Target = (power_notch_lua * 3.02) + bc_offset + 1`。`bc_offset` は力行中 or 回生中で 0.45。`bc_mode_prop`(Simulated/Real) で実測 BC とシミュレーション BC を切替。シミュレーションは `bc_sim_lpf` LPF、低速時は `const_v_init(4)` で下限保護。
- **定速制御 (CV)**: ブレーキノッチ 2 段でラッチ → 速度を `cv_reg` に記憶。`cv_src` はマスコン有効時 `brake_notch/8/3.6`、無効時 1.32 m/s 定数。
- **パンタ/DB**: Ext B4-B9 で前後パンタ SR ラッチ。`パンタ not_q AND パンタ上昇(B6)` → DB ラッチ set、B7 で reset。`is_m_car` で T 車は全状態無効。`cutout_enable = db_fwd OR db_rev`。
- **Boost (高加速)**: `BLINKER(0.5/0.5)` で速度サンプリング。前回値 > スナップ値なら加速中、3s 継続で `boost_latch` set → `boost_coef=1`。`mascon_fall` でリセット。
- **牽引力**: `((v*abs(v))*a + v*b + brake_notch_lua*c) * boost_coef`（a/b/c=Inertia）。
- **電力**: `voltage_src`（実電圧 or 1500V）→ `cutout_enable` で 0 → `Output(Watt) = motor_current * enabled_voltage`。
- **Momelink**: ID=1911 を ch15、CV を ch1、(M 車は)パンタ電圧を ch23 に乗せ転送。T 車は受信信号をそのまま中継。

---

### 3.5 Onecar Control

前後 2 運転台の CC3 を 1 両向けに統合する。詳細は §5/§6/§7 のフローで参照。

- **運転台選択**: CC3 B6 が front_cab。`front_cab_active = 自前 front_cab AND 相手 not`。`cc3_*_sw`(SWITCHBOX) でアクティブ側のみ通過。
- **数値合成**: N1 ブレーキ/N2 力行/N3 DB は switchbox 経由で前後 ADD。N4/N5 は前方のみ。N6 NITS は FIFO。N7 packed bool は前後展開→OR→再パック。
- **前後反転**: N7 packed の B3/B4・B7(ch7)/B9(ch9側)・B10/B11・B12/B13、boolean の B4/B5(扉A/B)・B16/B17(前後進)・B27-B30(扉開閉) は前後で読み替えチャンネルを入れ替える。
- **締切ゲート**: B7(前後選択)が前後でクロスした場合 `door_isolated` を立て、B6(`any_cab_active`)/B7 出力をゲートで無効化。
- **B18** は AND（前後両方 ON で DB 自動）、**B32** は OR 後 `either_cab_active` でゲート。
- **Simple IF RX inverted**: N4/N5・B4/B5 を入れ替えて出力。
- **NITS FIFO**: `scripts/n200.lua`。float-int 変換ベースのキュー。前後 NITS データを `table.insert`、毎 tick 1 件出力。空のとき `1<<24` をセンチネルとして送る（受信側はこれを無視）。

---

### 3.6 Door Min

ドア最小制御。

- **開閉エリア判定**: センサ A/B 間の距離二乗 `dist_sq` を `(length±width)^2` と比較。`NAND` で `in_door_zone`（扉開放域内）。
- **開扉判定**: `Other Inputs` ch10 で `NITS Ext. Input` を切替。`Door Side`(プロパティ, 既定 ch16) を読み、SR ラッチ `door_open_latch` を set。reset = `(!door_side_signal) AND nits_opp_signal`（対向側 ch+1 の信号）。
- **チャイム**: `door_change`(開閉変化) で COUNTER をリセットし 0-120 tick 計測。High 開扉=1-79 / Low 開扉=21-99 / High 閉扉=81-120 / Low 閉扉=101-120。
- **モータ速度**: 方向（開+1/閉-1）× 速度（停止後 0.4 / 動作中 0.2、`door_moving` CAPACITOR(discharge=1) で判定）。

---

## 4. NITS 通信プロトコル

NITS は編成内の機能制御を担う拡張コマンド群（コマンド ID 0x47-0x60、`NITS.md` 正典）。Cab Controller が 0x60 ペイロードを生成し、Onecar Control が前後 NITS を FIFO で順送する。

### 4.1 0x60 ペイロード生成（Cab Controller）
`nits60_build`(B1-B13) → `nits60_to_num` → TX N7。内容:

| B | 信号 | 生成条件 |
|---|---|---|
| 1 | CP 起動許可 | Settings B4 |
| 2 | SIV 起動許可 | Settings B3 |
| 3/4/5 | クロス転換 潮/須/L長 | `cross_*_en`（停車中 AND Drive Loop B19/B20/B21） |
| 6 | 高加速 | `high_accel_en`（Settings B12 AND mascon_active） |
| 7/8 | 他車/自車締切 | Settings B17/B16 |
| 10/11 | A/B 側開扉操作 | `door_a_op` / `door_b_op` |
| 12/13 | 前/後 締切コマンド | `doorcut_fwd/rev`（自動締切 OFF AND mascon AND Drive Support B2/B3） |

### 4.2 NITS FIFO（Onecar Control / n200.lua）
- 入力 N1/N2 = 前後 NITS（`unpk` で float→int 復元）。`1<<24` 以外をキューへ。
- 毎 tick 先頭 1 件を `pk`(int→float) して出力 N1。空なら `pk(1<<24)`（無効センチネル）。
- 1 tick 1 件のため、複数 NITS コマンドが連続すると順次遅延して伝搬する。

### 4.3 0x48/0x49/0x4A-0x4C
扉モード・ドアカット(0x48)、パンタ/室内灯/ヒータ(0x49)、車両諸元(0x4A)、車両状態(0x4B)、汎用 Ext(0x4C) は Bridge/Gateway が解釈し、Extended Commands RX として各車へ届く（`NITS.md` ビット表参照）。Door Min は 0x48 系の戸開指令を `Door Side` チャンネルで受信する。

---

## 5. 制動・力行制御フロー

```
[マスコンハンドル] Seat ch2
   ▼ notch_counter (-7..+4)
   ▼ eb_latch (-8固定 if EB)
   ▼ eff_notch = min(mascon_val, ATS各制限)
   ├─ power_cmd = max(eff,0)        → TX N2 (力行 0-7)
   └─ brake_cmd = clamp(...,0,31)   → TX N1 (ブレーキ 0-31)
   ▼ (Bridge → NITS → CC3 前後)
Onecar Control: N1/N2/N3 を switchbox 経由で前後 ADD
   ▼ CC3 統合
Traction Controller: Simple IF N1(ブレーキ)/N2(力行) として受信
   ▼ VVVF Lua (n485): 速度・方向・CV から力行/制動トルク算出
   ▼ vvvf_data_sw (mascon_enable_comb で Lua/Momelink 切替)
   ├─ traction_force → Inertia 係数で牽引力
   ├─ BC Target = power_notch_lua*3.02 + offset + 1
   └─ Output(Watt) = motor_current * enabled_voltage
```

ポイント: マスコン無効中（`mascon_enable_comb=0`）は Lua を使わず Momelink の CV データで定速追従する（T 車・非選択運転台側の協調制御）。

---

## 6. ドア制御フロー

```
[車掌スイッチ / ワンマンスイッチ / Drive Loop]
   ▼ Cab Controller
   ├─ door_a_op = (Settings B20 | Crew R B1 | DriveLoop B6) AND door_speed_ok
   ├─ door_b_op = (Settings B25 | Crew L B1 | DriveLoop B8) AND door_speed_ok
   │   door_speed_ok = 戸閉連動(Settings B9) OR 速度≒0(|v|<1.5)
   ├─ door_a_cl / door_b_cl (インターロックなし)
   ▼ TX B27-B30 (扉A/B 開閉操作), 0x60 N7 B10/B11 (開扉)
   ▼ (NITS) → Onecar Control
Onecar Control: B27↔B29, B28↔B30 を前後で入れ替えて OR → CC3 B27-B30
   ▼
Door Min: NITS Ext. の Door Side チャンネルで開扉指令受信 → door_open_latch
   ▼ モータ速度出力 + チャイム
```

ワンマン時（Settings B5^ OFF）は `dl_oneman_sw` で Drive Loop 側のドア指令を採用する。

---

## 7. 運転支援システム（Driver Assistance IV / n61）

### 7.1 経路・停車判定（n61.lua）
- `codeA`（Memreg2 由来）から `frm`(上位6bit) / `dest`(下位6bit) / `ttype`(12-15bit) を抽出。
- `link_tbl` で駅間グラフを BFS 探索（`find_rte`、内回り inb / 外回り）し、短い方を `get_rte` で選択。
- `is_stop`: 始終点、または `stop_type_tbl[id]` に列車種別 `ttype` が含まれれば停車駅。
- `meterage` / `coord_tbl`: 各駅の距離程と GPS 座標。`find_nearest_sta` で開扉/起動時に距離程を補正（`upkp` 時 N31=0, N32=kp で sw-net 側へ補正値を返す）。

### 7.2 接近・停車ラッチ（sw-net + n61）
- `stops()` で次停車駅までの距離 `lts` を算出:
  - 400 ≤ lts < 520 → `set_ap`（接近セット）、mode=3
  - lts > 520 → `reset_ap`（接近解除）
  - 開扉中 AND lts<520 → mode=1（停車中）
- sw-net 側:
  - `approach_latch` (SR): set=`door_open_any | door_a_rise`、reset=`stop_cond`(戸閉 AND 速度非ゼロ)。
  - `arrival_latch` (SR): set=`ds_reset_ap`(Lua ch4)、reset=`ds_approach_rst | depart_pulse`。
  - `arrival_flash` = `approach_latch_q` を CAPACITOR(0.5/0.5) で点滅 → 駅停車ランプ。
- 出力: ds_doorcut(Lua ch3, `doorcut_tbl` に該当駅) → Drive Support B2/B3 締切、Cab Controller の `doorcut_fwd/rev` へ。

---

## 8. 既知の設計上の特徴・注意点

1. **eb_latch の負論理**: Cab Controller の `eb_latch` は **set=EB 解除 / reset=EB 投入**。`eb_q`=EB 中、`eb_not_q`=通常。`mascon_active` が落ちる(`!mascon_active`)と reset 経由で EB 投入される failsafe。読解時に set/reset の意味を取り違えないこと。

2. **TX B1 (em_brake) も failsafe 正論理**: 通常走行（前方選択 AND EB 解除）で B1=1。非常時に 0 ではなく、`eb_form_fwd | 車掌EB | ATS EB` の OR で表現されている点に注意（実体は「ブレーキ不要＝走行可」を含む信号設計）。

3. **チャンネル番号の入れ替え（前後反転）**: Onecar Control では扉A/B(B4/B5)、前後進(B16/B17)、扉開閉(B27-B30)、N7 packed の一部を前後で読み替える。前方車と後方車で物理的な「A 側/前/右」が反転するための処置。デバッグ時は front/back どちらの座標系かを常に意識する。

4. **Simple IF と CC3 の N1/N2 入れ替え**: Traction Controller は `si_n1_brake_read (channel=2)` / `si_n2_power_read (channel=1)` と、名前と channel が交差している。Simple Interface の定義（N1=ブレーキ, N2=力行）と読み出し実装の対応に注意。

5. **1 tick 遅延の伝搬**: 各マイコンのコンポジット出力は次 tick に下流へ届く。Cab→Onecar→Traction の 3 段では指令反映に数 tick かかる。Lua（n200 FIFO, n485 VVVF）やラッチ系も 1 tick 遅延を持つため、エッジ検出（PULSE）の前後関係に依存するロジックは tick 順序を確認する。

6. **NITS FIFO のセンチネル `1<<24`**: 空キュー時に送られる無効値。受信側はこれを「データなし」として読み飛ばす。実データに 0x1000000 が現れない前提。

7. **マスコン協調（mascon_enable_comb）**: Traction は watchdog エッジで「自車運転台が生きている」ことを検出し、生きていれば Lua、死んでいれば Momelink の CV を採用する。運転台未起動の中間車・反対側先頭車はこの経路で追従する。

8. **is_m_car による T 車無効化**: パンタ・DB・牽引・電力は `is_m_car`(Rolling Stock Settings B1) で AND ゲートされ、T 車では発生しない。

9. **旧実装残骸**: Cab Controller の `unused_sign_latch`、Traction の `unused_and` / `lack_brake_calc` は出力未接続または未使用。改修時に誤って配線しないこと。

10. **ドア操作インターロック**: 開扉(`door_a_op`/`door_b_op`)は `door_speed_ok`（戸閉連動 OR |速度|<1.5 m/s）が必須。閉扉系はインターロックなし。クロスシート転換も同じ停車条件 `cross_en_base` でゲートされる。
