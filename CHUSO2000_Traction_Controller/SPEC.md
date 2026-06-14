# CHUSO2000 Traction Controller — 命名方針と機能概要

## 命名方針

snake_case を採用。プレフィックスで信号の出所・役割を明示する。

| プレフィックス | 意味 | 例 |
|---|---|---|
| `si_` | Simple IF コンポジット読み取り | `si_n1_brake_read`, `si_b1_mascon_read` |
| `ext_` | Extended Commands RX 読み取り | `ext_b6_panta_up_read` |
| `vvvf_` | VVVF Lua 関連 | `vvvf_lua`, `vvvf_lua_in`, `vvvf_data_sw` |
| `momelink_` | Momelink 編成内通信 | `momelink_id_read`, `momelink_cv_build` |
| `bc_` | BC (Brake Cylinder) 圧力・BC Mode | `bc_press_calc`, `bc_sim_lpf` |
| `cv_` | 定速制御 (Constant Velocity) | `cv_reg`, `cv_latch`, `cv_src_sw` |
| `boost_` | 高加速検知ラッチ | `boost_latch`, `boost_accel_gt` |
| `panta_` | パンタグラフ制御 | `panta_fwd_latch`, `panta_fwd_and` |
| `db_` | ダイナミックブレーキ | `db_fwd_latch`, `db_fwd_and` |
| `inertia_` | Inertia Composite 係数 | `inertia_a_read` ～ `inertia_d_read` |
| `rss_` | Rolling Stock Status 出力 | `rss_bool_build`, `rss_num_build` |
| `const_` | 定数 | `const_1500`, `const_cv_default` |
| `velocity_` | 速度信号 | `velocity_read`, `velocity_eff`, `velocity_sw` |
| `mascon_` | マスコン有効化・ホールド | `mascon_enable_cap`, `mascon_hold_cap` |

ネット名は動詞を省略し名詞・形容詞で意味を表現する。  
例: `velocity` (速度), `brake_notch` (ブレーキノッチ値), `mascon_active` (マスコン有効), `cutout_enable` (締切有効)

---

## 機能概要

### ポート一覧

| ポート名 | 方向 | 型 | 説明 |
|---|---|---|---|
| Physics Input | in | composite | 物理センサ入力 (ch9=速度[m/s]) |
| Voltage | in | number | パンタグラフ電圧 [V] |
| Output (Watt) | out | number | 消費電力 [W] |
| Simple IF | in | composite | Simple Interface RX (ノッチ・方向等) |
| Momelink Line from inner Unit | in | composite | 編成内 Momelink データ入力 |
| To Momelink Input & Advanced | out | composite | 編成内 Momelink データ出力 |
| Rolling Stock Status | out | composite | 車両状態コンポジット出力 |
| Brake sound | out | number | ブレーキ音トリガー [0-1] |
| Extended Commands RX | in | composite | パンタ・DB・高加速コマンド |
| Inertia Composite Input | in | composite | 慣性係数 a/b/c/d |
| BC | in | number | 実ブレーキシリンダ圧 |
| BC Target | out | number | BC 目標圧 [m/s 等価] |
| MR | in | number | 元空気だめ圧 [kPa] |
| Rolling Stock Settings | in | composite | 車両設定 (ch1=is_m_car) |

### 処理フロー

```
Physics Input (速度)
      │
      ▼
Simple IF (ノッチ・方向) → VVVF Lua ← Momelink (T車時)
                                │
                         vvvf_data_sw ← mascon_enable_comb
                                │
              ┌─────────────────┼──────────────────┐
              ▼                 ▼                   ▼
        brake_notch_lua   power_notch_lua      pan_voltage
              │                 │                   │
        traction_force_calc  bc_press_calc     rss_num_build
              │                 │                   │
        (牽引力→          BC Target 出力      Rolling Stock
         Inertia係数)                          Status 出力
```

### 主要サブシステム

#### BC シミュレーション
`bc_mode_prop` プロパティで Simulated / Real を切り替え可能。  
Simulated モードでは `bc_sim_lpf` の LPF 出力を `velocity_eff` として使用し、低速時は `const_v_init (4 m/s)` で下限保護する。

#### 定速制御 (CV)
ブレーキノッチ 2 段 (`brake_notch2_thr`) で CV 記憶をトリガー。  
マスコン有効時はブレーキノッチから逆算 (`cv_from_brake_calc`)、無効時は定数 1.32 m/s (`const_cv_default`)。

#### VVVF Lua
`scripts/n485.lua` にトルク・電流計算ロジックを実装。

**定数（スクリプト内ハードコード）**

| 定数 | 値 | 意味 |
|------|----|------|
| `MASS_M_CAR` | 35 t | M車1ユニットの質量 |
| `UNIT_CURRENT_MAX_P` | 720 A | 力行最大電流 |
| `UNIT_CURRENT_MAX_B` | 1200 A | ブレーキ最大電流 |
| `MOTOR_PER_UNIT` | 4 | 制御モータ数（実機） |
| `CONST_VF` | 0.0256 V/(km/h) | V/f 定数 |
| `BOOST` | 1.25 | 高加速係数 |
| `MAX_LINE_VOLTAGE` | 1.82 kV | 架線電圧上限 |
| `REFINE_VOLTAGE` | 1.70 kV | 回生制限開始電圧 |

**Lua 入力チャンネル（M車モード）**

| ch | 信号 |
|----|------|
| N1 | 速度 [m/s] |
| N2 | パンタグラフ電圧 [V] |
| N3 | 力行ノッチ (pN, 0–5) |
| N4 | ブレーキノッチ (bN, 0–31) |
| N5 | 方向 (direction) |
| N6 | 定速制御目標速度 [m/s] |
| N7 | EB時ブレーキ力パラメータ（bN≥32 or EB時に使用） |
| N30 | 連結両数 − 1（unitCar = N30 + 1） |
| N31 | 最大不足ブレーキ力（maxlackBrk） |
| B1 | EB |
| B2 | 高加速 (boost) |
| B3 | 回生無効 (disable_regen) |
| B4 | M車フラグ (is_M_car) |

**T車モード追加入力（Momelink 経由）**

| ch | 信号 |
|----|------|
| N8/N9 | M車→T車へのパススルーデータ |
| N15 | Momelink ID（1911 と一致するか判定） |
| N16 | Momelink 有効フラグ (bool, B16 扱い) |
| N23 | パンタ電圧 × 1000 [mV]（M車からの転送） |
| N24 | モータ電流 _MI（M車からの転送） |
| N25 | 不足ブレーキ力（M車からの転送） |
| N29 | パンタ電流（M車からの転送） |

**Lua 出力チャンネル（M車モード）**

| ch | 信号 |
|----|------|
| N1 | 不足ブレーキ力 lack_btrq |
| N2 | 牽引力 × 方向 [≈ m/s²] |
| N15 | 1911（Momelink ID） |
| N23 | パンタ電圧 × 1000 [mV]（Momelink へ転送） |
| N24 | モータ電流 _MI（Momelink へ転送） |
| N25 | 残車両あたり空気補完ブレーキ力 |
| N29 | パンタ電流（Momelink へ転送） |
| N30 | 0（M車） / N8 パススルー（T車） |
| N31 | 0（M車） / N9 パススルー（T車） |
| B16 | 回生ブレーキ有効（not disable_rb AND bN≠0 AND trq<0） |
| B17 | ウォッチドッグ（毎tick トグル） |
| B18 | 電動機動作中（trq ≠ 0） |
| B19 | 回生余剰電流あり（resI > 0） |
| B20 | 電気ブレーキ作動中（M車）/ B20 パススルー（T車） |

**力行ノッチ電流特性**

| notch | 動作 |
|-------|------|
| 0 | 惰行 |
| 1 | 微弱力行（vfcI = 0.5） |
| 2 | 41 km/h 以下: 1.03、以上: 定速 CV 追従（PI 制御） |
| 3 | 最大 1.543（定電流） |
| 4+ | 最大 1.543（定電流） |
| <0 | 回生ブレーキ（制動） |

架線電圧が 1.15 kV 未満で力行抑制、1.05 kV 未満で電気ブレーキも停止。

#### Mascon 有効化ラッチ
`nits_watchdog` (Lua ch17) の変化エッジを `XOR→NOT→CAPACITOR` で検出し `mascon_enable` を生成。  
`mascon_hold_cap` (1s) との OR で `mascon_enable_comb` を維持。

#### パンタグラフ / ダイナミックブレーキ
Extended Commands RX B4-B9 でパンタ前後の SR ラッチを制御。  
パンタ上昇コマンド (B6) + パンタ not_q → DB ラッチをセット。  
M 車 (`is_m_car`) フラグで T 車時は全状態を無効化。

#### Boost (高加速) 検知
500ms ブリンカーで速度をサンプリングし、前回値 > スナップショット値なら加速中と判定。  
加速継続 3s 以上で `boost_latch` がセット → `boost_coef = 1` (通常は 0=無効)。  
マスコン落下 (`mascon_fall`) でリセット。

#### Momelink
ID = 1911 を ch15 に書き込み、ch1 に CV、ch23 に電圧を埋め込んで転送。  
M 車: パンタ電圧を転送。T 車: Momelink 信号をそのまま転送。
