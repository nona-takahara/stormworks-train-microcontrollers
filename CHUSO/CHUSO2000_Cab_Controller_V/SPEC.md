# CHUSO2000_Cab_Controller_V 仕様書

運転台制御マイコン（Cab Controller V）。座席の操作入力、運転台まわりのスイッチを集めたループ（`Drive Loop`、`Settings Loop`）、ATS/ATC、車掌の操作などを読み、次の 3 つを作る。

- 編成内へ送る制御コマンド（`Control Commands TX`）
- 表示マイコンへ渡す状態（`Monitor Status`）
- ハンドル角度、逆転器位置、標識灯などの運転台側の出力

ここに書く事実は `main.sw-net` から読み取ったものである。`main.sw-net` の取り込み元は `CHUSO2000_Cab_Controller_IV.xml` で、ゲーム内の `CHUSO2000_Cab_Controller_V.xml` とは別のファイルである（確認事項を参照）。信号の意味は `SignalComposite.md` の各節に従う。ゲーム内で確かめていない項目には `[unconfirmed]`、コードの配線から推論した項目には `[inferred]` を付ける。

`switch` が true のとき `a`、false のとき `b` を選ぶ（`COMPOSITE_SWITCHBOX` と `NUM_SWITCHBOX` の両方、verified）。以下の記述は、この対応を前提にしている。

## ポート

### 入力

| ポート | 型 |
|-------|----|
| `Seat Input` | composite |
| `Mas-con Key` | boolean |
| `Drive Loop` | composite |
| `Settings Loop` | composite |
| `Simple Interface RX` | composite |
| `Extended Commands RX` | composite |
| `ATS/ATC` | composite |
| `Crew Handle Right` | composite |
| `Crew Handle Left` | composite |
| `Drive Support` | composite |
| `Physics Sensor [+Z = front]` | composite |
| `Rolling Stock Settings` | composite |
| `Conductor Em brake 1` | boolean |
| `Conductor Em brake 2` | boolean |
| `Conductor Switch Interlock Release` | boolean（`main.sw-net` のどこからも読まれていない） |

### 出力

| ポート | 型 | 内容 |
|-------|----|------|
| `Control Commands TX` | composite | 編成内へ送る制御コマンド |
| `Monitor Status` | composite | 表示用の状態。`Extended Commands RX` を元に重ねて作る |
| `Main Handle Angle` | number | ハンドル角度。プロパティで出力の種類を切り替える |
| `Main Handle Sound` | boolean | ハンドル操作音 |
| `Reverser Position` | number | 逆転器位置（-1 後退、0 中立、+1 前進） |
| `Reverser Sound` | boolean | 逆転器操作音 |
| `Formation Lever` | number | 編成前後選択レバー（-0.25、0、+0.25） |
| `Front Sign` | boolean | 前部標識灯 |
| `Tail Sign` | boolean | 後部標識灯 |
| `Express Light (UMI)` | boolean | `Drive Loop` B13 をそのまま出す |
| `Express Light (YAMA)` | boolean | `Drive Loop` B16 をそのまま出す |
| `High beam` | boolean | `Drive Loop` B4 の否定 |
| `Crew Buzzer` | boolean | 乗務員ブザー |
| `ATS/C Reset Signal` | boolean | ATS/C のリセット（1 tick のパルス） |

### プロパティ

| プロパティ | 値 | 内容 |
|-----------|----|------|
| `Handle Output Type` | `Angle`（既定）/ `TETSUDAN MOD` | `Main Handle Angle` の出力の種類 |

## 運転台の状態を決める信号

以降、`Seat N1` のような表記は `Seat Input` の ch を指す。`Settings Bn`、`Drive Bn` も同様に、`Settings Loop`、`Drive Loop` の bool ch n である。

### 運転台の有効

`Mas-con Key` と、編成前後選択レバー（後述）が前（+1）のとき、運転台が有効である。この信号（コード上の名前は `mascon_key_and_fwd`）は、`Control Commands TX` の B32、`Monitor Status` の B5、運転支援の許可に使う。

### ハンドルの非常位置ラッチ（`seat_latch`）

`SR_LATCH` の `not_q` が true のとき、ハンドルは非常位置にある（ノッチは -8 に固定される）。`q` が true のとき、非常位置にない。`SR_LATCH` の初期状態は `q = false`（verified）である。`not_q` の初期値は記録がないが、起動直後は非常位置と読む `[inferred]`。

| 条件 | 内容 |
|------|------|
| set（非常位置を出る） | `Seat N2` が -0.5 以下になった瞬間、`Seat B31`、`Seat N1` が -0.5 以下、`Seat N1` が 0.5 以上になった瞬間のいずれか |
| reset（非常位置に入る） | (`Seat N2` が 0.5 以上 かつ `Seat B1`)、または 運転台が有効でない |

`Seat N2` は [W][S] の軸（+ が [W]、ブレーキ側）、`Seat N1` は [A][D] の軸（- が [A]、+ が [D]）、`Seat B1` は 1 キー、`Seat B31` はトリガキーである（`SignalComposite.md`）。

`ATS/C Reset Signal` は、`not_q` の立ち下がり（非常位置を出た瞬間）の 1 tick のパルスである。

### ノッチ（`handle_notch`）

`COUNTER` で、次のように数える。

| 方向 | 条件 |
|------|------|
| down（ブレーキ側） | `Seat N2` が 0.5 以上になった瞬間、または 0.5 以上を押し続けているときの繰り返し。`Seat N1` の [D] で、ノッチが正のとき 1 段戻す。`not_q` が true の間は毎 tick |
| up（力行側） | `Seat N2` が -0.5 以下になった瞬間、またはその押し続けの繰り返し。`Seat N1` の [D] で、ノッチが負のとき 1 段戻す。`q` が true のときだけ有効 |
| reset（0 に戻す） | `Seat B31`、または `Seat N1` が -0.5 以下 |

押し続けの繰り返しは、0.3 秒押し続けた後、0.1 秒周期で出す（`CAPACITOR` と `BLINKER`）。

`COUNTER` の指定は `min=4, max=-7, clamp=on` で、大小が逆である。範囲は -7〜+4 と読むが、`min` が `max` より大きいときの `clamp` の挙動は storm-mcl に記録がない `[unconfirmed]`。この指定は、取り込み元の `CHUSO2000_Cab_Controller_IV.xml`（6/16 更新）にある値のとおりである。ゲーム内の `CHUSO2000_Cab_Controller_V.xml`（7/11 更新）のハンドルの `COUNTER` は `min=-4, max=7` で、取り込み元と違う。

ハンドルの出力値（`handle_notch_sw`）は、`not_q` が true のとき -8、false のとき `handle_notch` である。

| 出力 | 内容 |
|------|------|
| `Main Handle Angle` | `Handle Output Type` が `Angle` のとき `(-x - 2) / 25`、`TETSUDAN MOD` のとき `x`（`x` は `handle_notch_sw`） |
| `Main Handle Sound` | `handle_notch_sw` の変化が 0 の間 true、変化した tick だけ false の信号を `TOGGLE` に入れた値。`TOGGLE` は入力の立ち上がりで反転する `[unconfirmed]`ので、ノッチが変わるたびに 1 回反転する `[inferred]` |

`control_handle.sw-net` は、ハンドルまわりを取り出したモジュールで、`main.sw-net` からは使っていない。このモジュールは `COUNTER` を `min=-4, max=7` としていて、`main.sw-net` と逆である（コメントに「ミス？」とある）。

### 逆転器

- `Seat N4` が 0.5 以上になった瞬間に +1、-0.5 以下になった瞬間に -1 を数える（範囲 -1〜+1）。
- `Mas-con Key` が false のとき、0 に戻す。
- `Reverser Sound` は、逆転器位置の変化が 0 の間 true、変化した tick だけ false である。音の発生原理が音源ごとに異なるので、この極性は問題にしない（利用者の回答）。

### 編成前後選択レバー

- `Settings B13` の立ち上がりで +1、`Settings B14` の立ち上がりで -1 を数える（範囲 -1〜+1）。
- `Formation Lever` は、この値を 4 で割る（-0.25、0、+0.25）。
- 値が +1 のとき前、-1 のとき後である。後の信号は、`Control Commands TX` の B7（前は B6）と、`Tail Sign` に使う。
- 値が 1 tick で減ったとき、`Control Commands TX` の B31 が true になる。
- `COUNTER` の `reset_value` は -1 だが、`reset` が未接続のため、起動直後の値は `[unconfirmed]`。

## 非常制動とブレーキ上限

### EB（`Control Commands TX` B1）

次のいずれかが true のとき、true になる。

- 非常位置にあり（`seat_latch` の `not_q`）、かつ 編成前後選択が前（+1）
- `Conductor Em brake 1`
- `Conductor Em brake 2`
- `ATS/ATC` B8

### ノッチの上限

有効なノッチ（`effective_limit`）は、次の 4 つの最小値である。

| 値 | 条件 |
|----|------|
| `handle_notch_sw` | 常に |
| -8 | `ATS/ATC` B8 が true のとき（それ以外は既定値） |
| -8 | `ATS/ATC` B7 が true のとき（それ以外は既定値） |
| -4 | `ATS/ATC` B9 が true のとき（それ以外は既定値） |

既定値は、次の条件が true のとき 100、false のとき 0 である（0 は、未接続の入力を 0 と読む `[inferred]`）。

- `Simple Interface RX` の B4 と B5 がどちらも false、または `Settings B9` が true

この既定値のため、`Simple Interface RX` の B4 または B5 が true で、かつ `Settings B9` が false のとき、ノッチは 0 以下に抑えられ、力行はなくなる。

### `Control Commands TX` の N1、N2

| ch | 内容 | 式（`x` は有効なノッチ） |
|----|------|------------------------|
| N1 | ブレーキ | `clamp((-x - min(0, x+6)) × 4, 0, 31)` |
| N2 | 力行 | `max(x, 0)` |

ブレーキは次のとおり。

| x | N1 |
|---|----|
| 0 以上 | 0 |
| -1〜-6 | 4、8、12、16、20、24 |
| -7、-8 | 31 |

## ドア

### 許可条件

ドアの開操作は、次の条件（`conductor_speed_ok_or`）が true のときだけ通る。

- `Settings B9` が true、または 速度（`Physics Sensor` ch9）が -1.5 以上 1.5 以下

### 操作

| `Control Commands TX` | 内容 | 条件 |
|------|------|------|
| B27 | A 側（右）の開扉 | (`Settings B20` または `Crew Handle Right` B1 または 乗務員用の `Drive Loop` B6) かつ 許可条件 |
| B28 | A 側（右）の閉扉 | `Settings B21` または `Crew Handle Right` B2 または 乗務員用の `Drive Loop` B7 |
| B29 | B 側（左）の開扉 | (`Settings B25` または `Crew Handle Left` B1 または 乗務員用の `Drive Loop` B8) かつ 許可条件 |
| B30 | B 側（左）の閉扉 | `Settings B26` または `Crew Handle Left` B2 または 乗務員用の `Drive Loop` B9 |

「乗務員用の `Drive Loop`」は、`Settings B5` が false のときだけ `Drive Loop` を通す（`COMPOSITE_SWITCHBOX` の `a` が未接続なので、true のとき通さない）。`Settings B5` は `SignalComposite.md` で負論理のワンマン（`^`）である。

## 乗務員ブザーと発車予告

| 出力 | 条件 |
|------|------|
| `Crew Buzzer` | 次のいずれか、またはこの出力の立ち上がりの 1 tick。`Simple Interface RX` B2、`Seat B4`、`Settings B24`、`Settings B29`、`Drive B12`、`Crew Handle Right` B4、`Crew Handle Left` B4 |
| `Control Commands TX` B2 | `Crew Buzzer` の条件のうち、`Simple Interface RX` B2 と自分自身の立ち上がりを除いたもの |
| `Control Commands TX` B21、B22 | 次のいずれかの立ち上がり、立ち下がり。`Settings B23`、`Settings B28`、`Crew Handle Right` B3、`Crew Handle Left` B3、乗務員用の `Drive Loop` B10 |

## 標識灯

| 出力 | 条件 |
|------|------|
| `Front Sign` | ラッチ。set は (`Drive B3` の立ち上がり、または `Drive B3` かつ 編成前後選択が前)。reset は (`Drive B3` の立ち下がり、または 編成前後選択が前から外れた瞬間) |
| `Tail Sign` | 編成前後選択が後（-1）、または `Drive B15` |

`Express Light (UMI)` と `Express Light (YAMA)` は、それぞれ `Drive B13`、`Drive B16` をそのまま出す。`High beam` は `Drive B4` の否定である。`SignalComposite.md` は `Drive B4` と `Monitor Status` の B2 を「ON でハイビーム、OFF で減光」と書くので、この書き方だと `High beam` の極性と合わないように見える。利用者の記憶では、出力が 0 のときにハイビームである `[inferred]`。この記憶は、`Drive B4` の ON がハイビームで、その否定を出す配線と合う。

## 運転支援

`Drive Support` の B2、B3 は、次の信号と AND して、`Control Commands TX` の N7（後述）のビット 12、13 になる。

- `Settings B10` の否定（`SignalComposite.md` で負論理の自動締切装置）
- 運転台が有効

`Drive Support` N1 は、そのまま `Control Commands TX` の N6 になる。`Drive Support` B4 は、`Monitor Status` の B7 になる。

## `Control Commands TX`

### 数値

| ch | 内容 |
|----|------|
| N1 | ブレーキ |
| N2 | 力行 |
| N6 | `Drive Support` N1 |
| N7 | 下表の bool を数値にまとめたもの（bit 0 が下表の ch1） |

N7 の bool は次のとおり。ch9 は未接続で、false である。

| ch | 内容 |
|----|------|
| 1 | `Settings B4` |
| 2 | `Settings B3` |
| 3 | `Drive B19` かつ 条件（`Settings B9` が true、または `Simple Interface RX` の B4 と B5 がどちらも false）かつ 許可条件 |
| 4 | `Drive B20` に、ch3 と同じ条件 |
| 5 | `Drive B21` に、ch3 と同じ条件 |
| 6 | `Settings B12` かつ 運転台が有効 |
| 7 | `Settings B17` |
| 8 | `Settings B16` |
| 10 | ドアの開操作（A 側）の条件（B27 と同じ） |
| 11 | ドアの開操作（B 側）の条件（B29 と同じ） |
| 12 | 運転支援（前） |
| 13 | 運転支援（後） |

### bool

| ch | 内容 |
|----|------|
| 1 | EB |
| 2 | 乗務員ブザー（`Simple Interface RX` 由来を除く） |
| 6 | 編成前後選択が前 |
| 7 | 編成前後選択が後 |
| 9 | `Settings B15` |
| 10 | `Settings B2` |
| 11 | `Drive B2` |
| 16 | 逆転器が前（+1） |
| 17 | 逆転器が後（-1） |
| 18 | `Drive B14` の否定 |
| 19、20 | `Settings B7` の立ち上がり、立ち下がり |
| 21、22 | 発車予告の立ち上がり、立ち下がり |
| 23、24 | `Settings B8` の立ち上がり、立ち下がり |
| 27〜30 | ドア（前節） |
| 31 | 編成前後選択レバーが 1 つ減った |
| 32 | 運転台が有効 |

上記以外の ch は、出力しない（false）。

`SignalComposite.md` が付けた各 ch の名前は、同じ節にある。

## `Monitor Status`

`Extended Commands RX` を元に、次の bool と数値を重ねる。重ねない ch は、`Extended Commands RX` の値がそのまま出る。

### bool

| ch | 内容 |
|----|------|
| 1 | `Drive B1` |
| 2 | `Drive B4` |
| 3 | `Settings B6` |
| 4 | ハンドルが非常位置（`not_q`） |
| 5 | 運転台が有効 |
| 6 | `Simple Interface RX` B1 |
| 7 | `Drive Support` B4 |
| 8、9、10 | 常に false（`CONST_BOOL` の否定。`CONST_BOOL` は常時 ON の定数である。verified、利用者の回答） |
| 11 | `Extended Commands RX` B1 |
| 12 | `Simple Interface RX` B4 |
| 13 | `Simple Interface RX` B5 |
| 14 | `Extended Commands RX` B10 |
| 15 | `Extended Commands RX` B32 |
| 16 | `Rolling Stock Settings` B2 |

### 数値

| ch | 内容 |
|----|------|
| N9 | `Simple Interface RX` N1 |
| N10 | `Simple Interface RX` N2 |
| N11 | 逆転器位置 |
| N12 | 編成前後選択レバーの値（-1、0、+1） |
| N13 | `Physics Sensor` ch9（前後速度） |

## 使われていない入力

- `Conductor Switch Interlock Release`（ポート）
- `tail_sign_latch_unused`（出力が未接続のラッチ）

## 未確認事項

`[unconfirmed]` の項目の確認状況は、リポジトリ直下の `OPEN_QUESTIONS.md` にある。
