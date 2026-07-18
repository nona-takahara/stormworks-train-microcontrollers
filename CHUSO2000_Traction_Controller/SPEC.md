# CHUSO2000系 牽引制御マイコン仕様書

> 対象: `main.sw-net`、`scripts/n485.lua`
>
> 元データ: `CHUSO_2000_Traction_Controller.xml`
> 改訂日: 2026-07-18

## 1. 文書の位置づけ

本マイコンは、CHUSO2000系のVVVF電動機モデル、回生・空気ブレーキ協調、パンタグラフ制御、Momelink編成内連携、およびRolling Stock Status生成を行う。

M車とT車は同じマイコンを使用し、`Rolling Stock Settings` B1のM車フラグで動作を切り替える。M車はローカルで電動機計算を行い、T車はMomelinkで受信したM車側の電圧・電流・空気ブレーキ分担値を使用する。

準備済みだが現在は外部出力へ接続されていない慣性演算・非常制動時牽引カット回路も、削除せず実装どおり記載する。

## 2. sw-net解釈上の前提

- `THRESHOLD(min,max)`は`min <= input <= max`のときtrue。
- `NUM_SWITCHBOX`と`COMPOSITE_SWITCHBOX`は`switch=true`で入力`a`、falseで入力`b`を選ぶ。未接続入力は0またはfalse。
- `COMPOSITE_WRITE_*`の`inc`は元コンポジットを引き継ぎ、指定チャンネルだけを上書きする。
- Lua、ラッチ、キャパシタ、メモリレジスタ、およびウォッチドッグの遅延用ORは状態またはtick間の値を持つ。
- Luaノードは`scripts/n485.lua`を参照する。

## 3. 外部入出力

### 3.1 入力

| ポート | 型 | 用途 |
|---|---|---|
| `Physics Input` | composite | N9から車両前後速度[m/s]を取得。+Zが前方 |
| `Voltage` | number | 外部架線電圧[V]。0のとき1500 Vを代用 |
| `Simple IF` | composite | ブレーキ・力行・非常制動・方向・DB自動指令 |
| `Momelink Line from inner Unit` | composite | 内側ユニットから受信するMomelinkデータ |
| `Extended Commands RX` | composite | パンタグラフ・高加速指令 |
| `Inertia Composite Input` | composite | N1～N4の無次元係数a～d |
| `BC` | number | 実測ブレーキシリンダ絶対圧[atm abs] |
| `MR` | number | 元空気だめ絶対圧[atm abs] |
| `Rolling Stock Settings` | composite | B1がM車フラグ |

### 3.2 出力

| ポート | 型 | 用途 |
|---|---|---|
| `Output (Watt)` | number | 架線電力[W]。力行時正、回生時負 |
| `To Momelink Input & Advanced` | composite | 外側ユニットへ送るMomelinkデータ |
| `Rolling Stock Status` | composite | 電流・電圧・空気圧・パンタグラフ・故障状態 |
| `Brake sound` | number | BC低下速度から生成するブレーキ緩解音量0～1 |
| `BC Target` | number | ブレーキシリンダ目標絶対圧[atm abs] |

## 4. 入力コンポジット

### 4.1 Simple IF

| ch | 意味 |
|---:|---|
| N1 | ブレーキ指令0～31 |
| N2 | 力行ノッチ0～7 |
| B1 | 非常ブレーキ |
| B16 | 前進 |
| B17 | 後退 |
| B18 | DB自動。OFF時はLuaの回生無効入力をONにする |

方向値は前進を+1、後退を-1として加算する。同時入力では0になる。

### 4.2 Extended Commands RX

| ch | 意味 |
|---:|---|
| B4 | 前パンタグラフをロック |
| B5 | 前パンタグラフのロックを解除 |
| B6 | パンタグラフ上昇 |
| B7 | 全パンタグラフ下降 |
| B8 | 後パンタグラフをロック |
| B9 | 後パンタグラフのロックを解除 |
| B14 | 高加速 |

ロック中のパンタグラフはB6を受けても上昇しない。上昇状態はB7でリセットされる。M車フラグがOFFの車両では、ローカルのパンタグラフ状態と高さをRolling Stock Statusへ出力しない。

### 4.3 Inertia Composite Input

N1～N4は、それぞれ無次元係数a～dである。現在これらを使う2つの演算結果は外部出力へ未接続である。

```text
prepared_traction_effort
  = ((speed * abs(speed)) * a
     + speed * b
     + traction_accel * c)
    * prepared_traction_scale

prepared_brake_effort
  = friction_brake_decel * d / abs(speed)
```

`prepared_brake_effort`は停止時に0除算となり得るが、現在は未接続のため車両出力へ影響しない。

## 5. 架線電圧とパンタグラフ

外部`Voltage`が厳密に0の場合は1500 Vを使用し、それ以外は入力値を使用する。M車かつ前後いずれかのパンタグラフが上昇している場合だけ、選択した電圧を牽引供給電圧とする。

パンタグラフ高さは次の固定値である。

| 状態 | 高さ |
|---|---:|
| 上昇 | 0.3 |
| 下降 | 0.02 |

`Output (Watt)`は次式で求める。

```text
catenary_power = catenary_current * traction_supply_voltage
```

Luaの架線電流は回生時に負となるため、出力電力も負になる。

## 6. P2定速制御

1. 力行ノッチ0かつブレーキ指令0で、定速目標の取得を許可するラッチをセットする。
2. ブレーキ指令が入ると取得許可をリセットする。
3. 力行ノッチP2を1秒継続すると立上りパルスを生成する。
4. 取得許可中なら、その時点の絶対速度[m/s]を`cv_target_memory`へ保存する。
5. P2以外へ移動するかブレーキ指令が入ると、記憶値を0へ戻す。

LuaのP2制御は、記憶速度が41 km/hを超える場合に定速追従を行う。高速域で記憶値が0の場合はP2の力行電流を0にする。

## 7. Lua入出力

### 7.1 数値入力

| ch | 意味 |
|---:|---|
| N1 | 車両速度[m/s] |
| N2 | 牽引供給電圧[V] |
| N3 | 力行ノッチ0～7 |
| N4 | ブレーキ指令0～31 |
| N5 | 方向+1/0/-1 |
| N6 | P2定速目標[m/s] |
| N7 | 非常ブレーキ時の減速度1.32 m/s² |
| N8 | T車モードでN30へ転送するT車数1 |
| N9 | T車モードでN31へ転送する最大空気ブレーキ負担3.5 m/s² |
| N15 | Momelink ID。1911を有効データとして扱う |
| N23 | M車から受信した架線電圧[V] |
| N24 | M車から受信した1電動機あたり電流[A] |
| N25 | M車からT車へ割り当てられた空気ブレーキ減速度[m/s²] |
| N29 | M車から受信した架線電流[A] |
| N30 | 受信したユニット両数−1 |
| N31 | 受信した最大空気ブレーキ負担[m/s²] |

### 7.2 Boolean入力

| ch | 意味 |
|---:|---|
| B1 | 非常ブレーキ |
| B2 | 高加速。電流指令を1.25倍し、すべり制限速度を係数の二乗で除算 |
| B3 | 回生無効。Simple IF B18の反転値 |
| B4 | M車フラグ |
| B16 | Momelink上の回生ブレーキ有効状態。T車のN25採用条件に使用 |

### 7.3 数値出力

| ch | 意味 |
|---:|---|
| N1 | 自車が空気ブレーキで補うべき減速度[m/s²] |
| N2 | 車両前後方向を含む電動機加速度[m/s²] |
| N15 | Momelink ID 1911 |
| N23 | 架線電圧[V] |
| N24 | 1電動機あたり電流[A] |
| N25 | T車1両あたりへ割り当てる空気ブレーキ減速度[m/s²] |
| N29 | 架線電流[A] |
| N30 | M車では0、T車では入力N8の1 |
| N31 | M車では0、T車では入力N9の3.5 m/s² |

### 7.4 Boolean出力

| ch | 意味 |
|---:|---|
| B16 | 回生ブレーキ有効 |
| B17 | 毎tick反転するウォッチドッグ |
| B18 | 電動機動作中 |
| B19 | 回生余剰電流あり |
| B20 | 電気ブレーキ作動中。T車では受信B20を中継 |

### 7.5 電動機モデルの要点

- `MASS_M_CAR=35 t`、`MOTOR_PER_UNIT=4`。
- `CONST_VF=0.0256`は、Lua内部で架線電圧をkV、速度をkm/hとして扱うためkV/(km/h)相当。
- 高加速時は電流指令を1.25倍する。
- 生の架線電圧が1.15 kV未満なら力行を停止し、1.05 kV未満なら電気ブレーキも停止する。
- 回生電流は1.70 kVから絞り始め、1.82 kVで0になる。
- 力行ノッチP1は弱め、P2は低速時定電流・高速時定速制御、P3以上はより大きい定電流指令を使用する。

## 8. Luaウォッチドッグとフォールバック

Lua B17の毎tickトグルを、遅延値とのXORで監視する。変化が0.1秒継続して検出されない場合、`motor_lua_fault_cap`がONになる。

次のどちらかでLua出力からフォールバックコンポジットへ切り替える。

```text
fallback_select
  = emergency_brake_held_for_1s
    OR motor_lua_fault
```

フォールバックN1は次の値である。

| 条件 | N1 空気ブレーキ減速度 |
|---|---:|
| 非常ブレーキON | 1.32 m/s² |
| 非常ブレーキOFF | `Simple IF N1 / 8 / 3.6` |

フォールバックコンポジットにはN15=1911、N30=1、N31=3.5も書き込む。

## 9. BC制御

`BC Mode`がSimulatedの場合はIIRによる模擬BC、Realの場合は外部`BC`を有効BCとして使用する。

非常ブレーキが1秒継続し、有効BCが4 atm abs未満の場合は、状態・表示用BCを4 atm absへ引き上げる。4 atm absを超える値を上限カットする処理ではない。

選択された牽引結果N1を空気ブレーキ減速度とし、次式でBC Targetを求める。

```text
brake_active
  = air_brake_decel > 0 OR electric_brake_active(B20)

bc_preload = brake_active ? 0.45 : 0

BC Target [atm abs]
  = air_brake_decel * 3.02 + bc_preload + 1
```

模擬BCの更新式は次のとおり。

```text
simulated_bc
  = clamp(BC_Target, previous_bc * 0.6 - 0.03, 6) * 0.07
    + previous_bc * 0.93
```

Rolling Stock Status N2用のゲージ圧は次式でkPaへ変換する。

```text
bc_gauge_kPa = max((effective_bc - 1) * 101.325, 0)
```

## 10. Momelink

入力N15が1911の場合だけ`Momelink Line from inner Unit`を有効化する。M車ではローカル架線電圧をN23へ書き、T車では有効な入力Momelinkを引き継ぐ。

`To Momelink Input & Advanced`は選択した牽引結果を引き継ぎ、N1だけを選択後BCから求めた摩擦制動減速度で上書きする。

```text
Momelink N1 [m/s²]
  = max(BC[atm abs] - 1.45, 0) / 3.02
```

この値は作動比ではなく減速度[m/s²]であり、常に0以上で方向符号を持たない。N2はLua由来の電動機加速度で、車両前後方向の符号を持つ。

M車は受信N30からユニット両数を`N30+1`として求め、受信N31の最大空気ブレーキ負担を使って、M車自身のN1とT車向けN25へ空気ブレーキ要求を配分する。T車はN8=1、N9=3.5をN30/N31へ中継する。

## 11. Rolling Stock Status

| ch | 意味 |
|---:|---|
| B1 | モータLua故障 |
| B5 | 前パンタグラフのロック状態 |
| B6 | 前パンタグラフの上昇状態 |
| B7 | 後パンタグラフのロック状態 |
| B8 | 後パンタグラフの上昇状態 |
| N2 | BCゲージ圧[kPa] |
| N3 | 4電動機合計電流[A]。Lua N24×4 |
| N4 | 架線電流[A]。Lua N29 |
| N5 | 架線電圧[V]。Lua N23 |
| N6 | 前パンタグラフ高さ |
| N7 | 後パンタグラフ高さ |
| N8 | MR絶対圧[atm abs] |

## 12. 準備済み・未接続ロジック

次の出力は元XMLでも外部ポートへ接続されていない。

- `prepared_traction_effort_calc`
- `prepared_brake_effort_calc`

非常ブレーキ中に0.5秒ON／0.5秒OFFで速度をサンプリングし、非常ブレーキ3秒経過後も速度が増加していれば`prepared_traction_cutout_latch`をセットする回路がある。このラッチは`prepared_traction_effort_calc`の係数を0にするが、同演算自体が未接続のため、現在の車両出力には影響しない。

`unused_and`も未接続のまま保持する。
