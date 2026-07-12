# CHUSO 1800系 牽引制御マイコン仕様書

> 対象: `CHUSO1800_Traction_Controller_main_renamed.sw-net`、`scripts/n409.lua`  
> 適用車種: 中宗電鉄1800形・1900形  
> 改訂日: 2026-07-12  
> 旧 `SPEC.md` は本書で置き換える。旧解析に含まれていた誤認は `LEGACY_SPEC_CORRECTIONS.md` に分離した。

## 1. 文書の位置づけ

本マイコンは、直流電動機の抵抗制御、直並列切替、界磁制御、回生制動、空気ブレーキ補完、パンタグラフ制御、Momelink-A Advanced連携、およびRolling Stock Status生成を行う。

1800形と1900形は同じマイコンを使用し、Property `M Type` で動作を切り替える。1900形を別設計の牽引制御マイコンとして扱ってはならない。ただし、1900形モードではMomelink inner unitとの分担が入り、ローカル処理とinner unit由来データの使用範囲が変わる。

本書では、現在未消費のロジックも削除せず、実装どおり記載する。

## 2. sw-net解釈上の前提

- `THRESHOLD(min,max)` は `min <= input <= max` のときtrue。
- `NUM_SWITCHBOX` は `switch=true`で入力`a`、falseで入力`b`を選ぶ。未接続入力は0またはfalse。
- `COMPOSITE_WRITE_*` の `inc` は元コンポジットを引き継ぎ、指定チャンネルだけを上書きする。
- `SR_LATCH`、`CAPACITOR`、Lua、自己帰還式は状態を持つ。すべての組合せゲートが一律に1 tick遅延するとは仮定しない。
- 元のsw-net生成処理には、`THRESHOLD`の`max=0`を`max=1`として出力する不具合があった。次の6ノードは実機設定に合わせて`max=0`へ修正済み。
  - `catenary_input_zero`
  - `cam_position_unchanged`
  - `power_notch_zero`
  - `cam_at_zero`
  - `field_control_cam_ready`
  - `direction_neutral`
- Physics Sensor N9への結線は、元sw-net上では入力指定が欠けている。実機結線では車両前後速度を読むものとして扱う。
- Luaノードは `scripts/n409.lua` を参照する。

## 3. 外部入出力

### 3.1 入力

| ポート | 型 | 用途 |
|---|---|---|
| Physics Sensor [+Z is front] | composite | N9から車両前後速度を取得 |
| Catenary Line Voltage [V] | number | 外部架線電圧 |
| SAP [atm] | number | SAP方式でのブレーキ要求圧 |
| BP [atm] | number | SAP方式でのブレーキ管圧 |
| BC [atm abs] | number | 実測ブレーキシリンダ絶対圧 |
| MR [atm abs] | number | 元空気だめ絶対圧 |
| Controller Stop | boolean | 外部からの牽引制御停止要求 |
| Simple IF | composite | 力行・制動・方向・DB自動などの指令 |
| Extended IF | composite | パンタグラフ指令 |
| Momelink inner unit | composite | 1900形で連携する内側ユニット情報 |

### 3.2 出力

| ポート | 型 | 用途 |
|---|---|---|
| DANRYU | boolean | 電機子電流が正でない状態。回生時の負電流でもtrue |
| cam | boolean | カム位置カウンタが変化したtickでtrue |
| W | number | Luaモデルまたはフォールバック後の主回路電力 |
| BC target [atm] | number | 選択されたMomelinkデータ源のN25 |
| Momelink-A | composite | 1800形基本フレームまたは1900形Advancedフレーム |
| Rolling Stock Status | composite | 車両状態、電流、架線電圧、空気圧、パンタ状態 |

## 4. 主要コンポジットチャンネル

### 4.1 Simple IF

| 種別 | ch | 意味 |
|---|---:|---|
| Number | 1 | ブレーキ指令。ECB方式では圧力相当値へ変換 |
| Number | 2 | 力行ノッチ0～7 |
| Boolean | 1 | 非常制動指令 |
| Boolean | 16 | 前進指令 |
| Boolean | 17 | 後進指令 |
| Boolean | 18 | DB自動指令。1800系では自動回生制動の許可に使用 |

### 4.2 Extended IF

| Boolean ch | 意味 |
|---:|---|
| 4 | パンタ1上昇 |
| 5 | パンタ1下降 |
| 6 | パンタ使用許可 |
| 7 | 全パンタ下降 |
| 8 | パンタ2上昇 |
| 9 | パンタ2下降 |

## 5. 架線電圧選択

外部架線電圧の使用条件は次のとおり。

```text
use_catenary_input
  = Use Supplied Catenary Voltage
    AND (Catenary Line Voltage != 0)
```

- 条件成立時: 外部入力電圧を使用。
- 条件不成立時: 定格1500 Vを使用。
- その後、1800形用パンタ有効状態が1基以上成立している場合だけLuaモデルへ電圧を供給する。
- 1900形モードではローカルの1800形パンタ有効信号が無効となる。1900形ではMomelink inner unitとの分担があるため、この事実だけから「1900形は制御対象外」と解釈してはならない。

## 6. 力行ノッチとカム軸

### 6.1 力行ノッチ

Simple IF N2を0～7へ制限し、牽引禁止時には0倍する。

```text
effective_power_notch
  = clamp(power_notch_command, 0, 7)
    * (traction_inhibit ? 0 : 1)
```

`power_notch_zero`は生のSimple IF N2が0であることを検出する。牽引禁止後の有効ノッチではなく、入力指令そのもののゼロ判定である。

### 6.2 カム位置

カム位置は0～20の21段で循環する。

```text
cam_position_counter = (previous + increment) % 21
```

`cam`出力は、カム位置のDELTAが0でないtickでtrueになる。通常の+1進段と20→0の周回の両方を含む。

Lua出力N5はカム位置のエコーであり、次の条件へデコードされる。

| 条件 | 範囲 |
|---|---|
| cam_at_zero | 0 |
| cam_in_series_range | 0～13 |
| cam_at_transition_position | 14 |
| cam_in_parallel_range | 14～20 |

`cam_zero_epsilon`と`cam_nonzero_epsilon`は現状未消費だが保持する。

## 7. 直列・並列・界磁制御

### 7.1 モード対応

| sw-net状態 | 主回路上の意味 | Lua入力 |
|---|---|---|
| series_connection_latch | 直列接続 | B1 |
| parallel_connection_latch | 並列接続 | B2 |
| field_control_latch | 並列抵抗制御完了後の界磁制御領域。力行と回生の両方で使用 | B3 |

Phase 1/Phase 2という旧称は、それぞれ直列・並列接続を意味する。

### 7.2 通常力行シーケンス

1. ノッチ1以上、カム0、並列OFFで直列ラッチをセットする。
2. ノッチ2以上、カム0～13、直列成立後0.1秒、かつ電流が進段閾値未満で、直列域を進段する。
3. ノッチ3以上、カム14、電流が進段閾値未満で並列ラッチをセットし、直列ラッチをリセットする。
4. ノッチ3以上、カム14～20、並列成立後0.1秒、かつ電流が進段閾値未満で、並列域を進段する。
5. 並列状態でカム0へ到達すると、界磁制御ラッチをセットする。

Luaの抵抗表はこのカム配置に対応する。

- `SR[1..21]`: 直列抵抗表
- `PR[1..21]`: 並列抵抗表
- カム14は直並列転換位置
- 並列進段後にカム0へ戻ると抵抗全短絡側となる

### 7.3 限流進段

進段許可は電機子電流の閉ループ制御ではなく、カム軸を止めるための閾値判定である。

| 状態 | 既定進段閾値 |
|---|---:|
| 直列 | 210 A |
| 並列 | 190 A (`base - 20`) |

電流が閾値未満の状態が0.1秒継続すると進段可能になる。

### 7.4 カム復帰

直列・並列の両ラッチがOFFで、カムが0以外にある場合は、カム軸を回し続けて0へ戻す。

### 7.5 界磁電流による接続遷移

ノッチOFF時に界磁電流が選択閾値を超えると、0.1秒ON／0.4秒OFFの周期パルスを生成する。このパルスは並列から直列への切替、直列の解除、またはDB自動OFF時の接続解除に使用される。

選択閾値は通常300 Aで、直列状態かつ回生減速度指令が有効な場合は400 Aとなる。

## 8. Lua電動機モデル

### 8.1 定数

| 定数 | 値 | 用途 |
|---|---:|---|
| K | 12.16 | 電動機定数 |
| Kmu | 0.00029 | 磁束係数 |
| MOT_RES | 0.07 Ω | 電動機内部抵抗 |
| Ks | 0.85 | 飽和式係数 |
| PHIs | 150 | 磁束飽和式係数 |
| MOT_CTRL | 4 | 制御対象電動機数に関係する係数 |
| GEAR_RATIO | 5.31 | 歯車比 |
| WHEEL_R | 0.43 m | 車輪半径 |
| WEIGHT | 35000 kg | 車両質量 |

### 8.2 数値入力

| ch | 値 |
|---:|---|
| N1 | 車両速度 [m/s] |
| N2 | 牽引供給電圧 [V] |
| N3 | カム位置0～20 |
| N4 | 方向符号 +1/0/-1 |
| N5 | 有効力行ノッチ0～7 |
| N6 | 電機子電流初期値・基準値。既定200 A |
| N7 | 平滑化した回生減速度目標 [m/s²、負] |
| N8 | 生の回生減速度目標 [m/s²、負] |

### 8.3 Boolean入力

| ch | 値 |
|---:|---|
| B1 | 直列接続 |
| B2 | 並列接続 |
| B3 | 界磁制御モード |
| B4 | 力行ノッチ1以上 |
| B5 | DB自動かつ回生制動要求あり。減速度追従制御を選択 |
| B6 | sw-netから書き込まれるが、現Luaでは未使用 |

### 8.4 電気モデル

車両速度から電動機回転数を求める。

```text
rpm = vehicle_speed * 9.55 * GEAR_RATIO / WHEEL_R
```

界磁電流と磁束は次の飽和式で表現される。

```text
iF  = armature_current * pF + auxiliary_field_current
phi = iF * Kmu * Ks * PHIs / (Ks * abs(iF) + PHIs)
```

電機子電流は次の方程式をニュートン法で5回反復して求める。

```text
K * phi * rpm - terminal_voltage
  + (motor_resistance + external_resistance) * armature_current = 0
```

直列時は1電動機相当電圧を架線電圧の1/8、並列時は1/4として扱う。抵抗値も同じ係数で分割する。

### 8.5 Lua出力

| ch | 値 |
|---:|---|
| N1 | 電機子電流 [A] |
| N2 | 逆起電力相当値 `K*phi*rpm` |
| N3 | 車両加速度 [m/s²] |
| N4 | 主回路電力 [W] |
| N5 | カム位置エコー |
| N6 | 補助界磁電流・界磁制御量 `iF_a` [A] |
| N7 | 電気制動で不足する減速度。空気ブレーキ補完要求 |

N3はBC目標ではなく車両加速度であり、N7は速度ではなく空気ブレーキ補完要求である。

## 9. ブレーキインターフェース

### 9.1 SAP方式

- 牽引禁止判定には外部`BP [atm]`を使用。
- 制動要求には外部`SAP [atm]`を使用。

### 9.2 ECB方式

非常制動指令から仮想BPを生成する。

| 非常制動 | 仮想BP |
|---|---:|
| OFF | 5 atm |
| ON | 0 atm |

ECBのブレーキ要求圧は次式。

```text
ecb_brake_demand_pressure
  = clamp(brake_command + (5 - virtual_BP) * 7, 0, 36) / 8 + 1
```

通常時は概ね`brake_command/8 + 1`、非常制動時は最大側へ強制される。

### 9.3 牽引禁止用ブレーキ管判定

SAP方式では実BP、ECB方式では仮想BPを4 atmと比較する。4 atm未満で牽引禁止条件が成立する。

## 10. 回生制動と空気ブレーキ補完

### 10.1 減速度目標

ブレーキ要求圧を負の減速度指令へ変換する。

```text
regen_deceleration_target
  = -floor((brake_demand_pressure - 1) * 2) / 7.2
```

平滑化は1 tickあたり、制動を強める方向へ最大0.1 m/s²、解除方向へ最大0.02 m/s²で追従する。

### 10.2 DB自動

Simple IF B18がONで、生の減速度目標が-0.05 m/s²未満のとき、自動回生制動要求を成立させる。この信号はLua B5へ入り、界磁制御を減速度追従モードへ切り替える。

### 10.3 架線過電圧保護

設計意図は、回生時に架線電圧が上昇した場合に回生を切り、再投入を抑制することである。実装上は架線電圧を直接比較せず、Luaの界磁電流が保護条件へ達したことを代理量として使用する。

- 直列接続成立後、界磁電流が300 Aを超えた状態が0.5秒継続すると、回生減速度目標を0へ切り替える。
- CAPACITORのdischarge time 10秒により、保護解除後も再投入を遅らせる。
- 回生が使えない間の要求は空気ブレーキへ引き継ぐ。

### 10.4 空気ブレーキ補完

Lua N7は、要求減速度に対して電気制動が不足した量を正値で出力する。牽引禁止時にはLua出力を使わず、次の全量フォールバック値をN7へ書く。

```text
pneumatic_brake_fallback_demand
  = max(-regen_deceleration_target, 0)
```

N7は最終的に次式でBC絶対圧目標へ変換される。

```text
BC target [atm abs] = pneumatic_demand * 3.6 + 1
```

## 11. 牽引禁止と故障ラッチ

`traction_inhibit`は次のOR条件で成立する。

- `Controller Stop`
- 牽引故障ラッチ
- 方向中立（前進・後進ともOFF、または両方ON）
- 絶対速度がProperty `Over Speed Th.`を超過
- ブレーキ管相当圧が4 atm未満

成立時は有効力行ノッチを0にし、Lua結果コンポジットの代わりに空気ブレーキ全量フォールバックコンポジットを選ぶ。その結果、電流・加速度・電力・カムフィードバック・界磁電流は0となり、N7だけに空気ブレーキ要求が入る。

電機子電流が±200000 Aの範囲外へ出た場合は、計算異常として牽引故障ラッチをセットする。リセット条件は、生の力行ノッチが0かつDB自動がOFFであること。

`unused_startup_delay`はenable未接続のため現状未消費である。1800系マイコンにはLuaウォッチドッグは存在しない。XOR/NOTループによるLua生存監視は2000系列の参考実装と混同しないこと。

## 12. パンタグラフ制御と車種切替

個別パンタごとに、上昇／下降指令ラッチと使用許可ラッチを持つ。

- `panta1_latch`、`panta2_latch`: 個別昇降指令状態。
- `panta1_en_latch`、`panta2_en_latch`: パンタ使用許可状態。
- `panta_all_down_signal`: 両使用許可ラッチをリセット。
- `vehicle_type_1900`: ONで1900形、OFFで1800形。
- `panta*_1800_active`: 使用許可ラッチと1800形判定のAND。

1800形でパンタが有効なとき、Property `Panta Height (Type)`を高さとして出力する。それ以外は0.02を出力する。

## 13. Momelink-A Advanced

### 13.1 共通値

実測BC絶対圧からBC作動比を生成する。

```text
bc_application_ratio = max(BC_abs - 1.45, 0) / 3.02
```

### 13.2 Advancedフレーム

| Number ch | 値 |
|---:|---|
| 1 | 自車BC作動比 |
| 2 | inner unit N26 |
| 15 | Type ID 1911 |
| 22 | 35。Luaの車両質量と一致するため車両質量[t]と推定 |
| 23 | 自車牽引供給電圧 |
| 24 | 自車電機子電流 |
| 25 | 自車BC目標絶対圧 |
| 26 | 自車平滑加速度 |

### 13.3 1800形フレーム

Advancedフレームを引き継ぎ、N1を自車BC作動比、N2を自車平滑加速度で上書きする。

### 13.4 出力選択

```text
use_1900_advanced_frame
  = vehicle_type_1900
    AND (Momelink inner unit N15 == 1911)
```

- 条件成立: Advancedフレームを`Momelink-A`へ出力。
- 条件不成立: 1800形フレームを出力。

この切替は同一マイコン内の1800形・1900形対応であり、1900形を別マイコン方式とみなしてはならない。

## 14. Rolling Stock Status

1900形かつinner unit Type ID 1911の場合、N23～N25の情報源として`Momelink inner unit`を選ぶ。それ以外はローカルのAdvancedフレームを選ぶ。

### 14.1 Numberチャンネル

| ch | 値 |
|---:|---|
| N1 | 未設定 |
| N2 | 実測BCゲージ圧 [kPa] |
| N3 | 選択されたデータ源の電機子電流 |
| N4 | 未設定 |
| N5 | 選択されたデータ源の架線・供給電圧 |
| N6 | パンタ1高さ |
| N7 | パンタ2高さ |
| N8 | MR絶対圧 [atm] |

BCゲージ圧は次式。

```text
max((BC_abs - 1) * 101.315, 0)
```

### 14.2 Booleanチャンネル

| ch | 値 |
|---:|---|
| B1 | 牽引故障ラッチ |
| B2～B4 | 未設定 |
| B5 | 1800形パンタ1個別ラッチ状態 |
| B6 | 1800形パンタ1使用状態 |
| B7 | 1800形パンタ2個別ラッチ状態 |
| B8 | 1800形パンタ2使用状態 |

`BC target [atm]`出力は、同じデータ源のN25を使用する。

## 15. 現状未消費・保留事項

| 項目 | 状態 |
|---|---|
| `power_notch_ge4` | 未消費。保持 |
| `cam_nonzero_epsilon` | 未消費。保持 |
| `brake_current_limit_scale` | ブレーキ時限流値のスケーリング用Propertyとして用意されているが、現状未消費 |
| `unused_startup_delay` | enable未接続。保持 |
| Lua Boolean B6 | 入力コンポジットには存在するが、現Luaでは未使用 |
| Momelink N22 = 35 | 車両質量[t]と強く推定されるが、プロトコル正典による確認が望ましい |

## 16. 保守上の原則

- ノード名ではなく、結線、式、Lua入出力、外部プロトコルを優先して意味を判断する。
- Phase 1/2のような抽象名を再導入せず、直列・並列・界磁制御を明記する。
- `regen`という語は、自動回生制動要求、界磁制御モード、架線過電圧保護、空気ブレーキ補完を区別して使う。
- 2000系列の仕様はインターフェースや設計慣習の参考に限定し、1800系固有ロジックへ直接転用しない。
