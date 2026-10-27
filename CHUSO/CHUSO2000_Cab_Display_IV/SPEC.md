# CHUSO2000_Cab_Display_IV 仕様書

運転台表示マイコン（Display IV）。`Monitor Status` と `Rolling Stock Status` などを読み、次の 6 つを出力する。

- `Main Monitor`（video）: メインモニタの映像
- `ATP Switch`（video）: ATP ページ切り替えのアイコン
- `Electricity Display`（video）: 架線電圧と電流のメータ、ドア状態の表示灯
- `ARC`（number）: 種別、行先、運行番号、上下線の別から決まる番号
- `ATC Train Length`（number）: 編成の長さ
- `Loop Start, ATS/C Settings`（composite）: ループへ返すハイビーム位置などの設定値

ここに書く事実は `main.sw-net` と `scripts/*.lua` から読み取ったものである。チャンネルの意味は `SignalComposite.md` の `Monitor Status(IV)`、`Rolling Stock Status`、`Loop Start` の節に従う。ゲーム内で確かめていない項目には `[unconfirmed]`、コードの配線や名前から推論した項目には `[inferred]` を付ける。

## ポート

| ポート | 方向 | 型 |
|-------|------|----|
| `Monitor Status` | in | composite |
| `Rolling Stock Status` | in | composite |
| `ATS/ATC` | in | composite |
| `ATP Monitor Touch Composite` | in | composite |
| `Main Monitor` | out | video |
| `ATP Switch` | out | video |
| `Electricity Display` | out | video |
| `Loop Start, ATS/C Settings` | out | composite |
| `ARC` | out | number |
| `ATC Train Length` | out | number |

## 設定

| プロパティ | 既定値 |
|-----------|--------|
| `High Beam X` | 0 |
| `High Beam Y` | 0 |
| `Low Beam X` | 0 |
| `Low Beam Y` | −0.5 |

## 数値・composite 出力の作り方

以降、`MS Bn` は `Monitor Status` の bool ch n、`MS Nn` は number ch n、`RS Nn` は `Rolling Stock Status` の number ch n を指す。

### ARC

`ARC = (floor(MS N2) % 100000 + floor(MS N1) × 100000) × max(MS N12, 0)`

ARC は、中宗車では、種別、行先、運行番号、上下線の別から決まる番号である（verified。利用者の回答）。[宗弥急行プロジェクト ARC](https://nonasaba.net/sw-train-docs/support/Soya-Express-ARC.html)の 7 桁（運行番号 `pp`、路線/上下線 `b`、種別 `tt`、行先 `dd`）に当たる。MS N1 が運行番号 `pp`、MS N2 の下位 5 桁が `b tt dd` である。MS N12 は編成向きで、負のとき 0 に切り詰めるため、`ARC` も 0 になる。

### ATC Train Length

`ATC Train Length = (MS N31 + MS N32 + 1) × 18`

MS N31 と MS N32 は前側と後側の両数である。1 両あたり 18 を掛けるので、単位は m と読む `[inferred]`。

### Loop Start, ATS/C Settings

| ch | 内容 | 作り方 |
|----|------|--------|
| N1 | ハイビーム X | MS B2 が true なら `High Beam X`、false なら `Low Beam X` |
| N2 | ハイビーム Y | MS B2 が true なら `High Beam Y`、false なら `Low Beam Y` |
| N3 | レバーサ | MS N11 |
| N4 | 編成向き | MS N12 |
| N5 | 保安装置選択 | 後述の ATP モード（1 または 2）を、MS B5 が true のとき通す。MS B3 が true のときは ATP モードを通さない |
| N6 | マスコン非常位置 | MS B4 が true のとき 1 |
| B18 | 自車締切 | MS B14 |
| B19 | 他車締切 | MS B15 |
| B22 | A 側ドア状態 | MS B12 |
| B27 | B 側ドア状態 | MS B13 |

N5 と N6 で `switch` が false のときの値は、`NUM_SWITCHBOX` の `b` が未接続なので 0 と読む `[inferred]`（利用者は 0 を期待してよいとしている。storm-mcl に記録はない）。B18、B19、B22、B27 以外の bool は、元の入力にこのチャンネルが無いため false である `[inferred]`。

### ATP モードとページ切り替え

1. `ATP Monitor Touch Composite` の bool ch1 の立ち下がりで 1 tick のパルスを出す。
2. そのパルスと MS B4（マスコン非常位置）の AND が、`TOGGLE` を反転させる。
3. `TOGGLE` が true のとき ATP モードは 1、false のとき 2 になる。

起動直後は ATC で起動する（利用者の回答）。`TOGGLE` の初期値は `[unconfirmed]`。ATP モードは `ATP Switch` の Lua（`n390.lua`）の N1 と、`Loop Start` の N5 に使われる。

## 電気表示の平滑化

`RS N3` と `RS N5` を、それぞれ次式で平滑化する。

`out = e^(−a) × (Δout + (out_prev − raw) × (a + 1)) + raw`

- `a` = 0.4、`e` = 2.71828182846
- `raw` は `RS N3` または `RS N5` の値
- `out_prev` は同じ式の前 tick の出力
- `Δout` は `DELTA` による出力の 1 tick の差（今の tick から前の tick を引いたもの、verified）

平滑化した値は `Electricity Display` の Lua に N3 と N4 として渡す。

| Lua 入力 | 元の信号 | 内容 |
|---------|---------|------|
| N1 | MS N27 | 車両情報 info0（packed） |
| N2 | MS N29 | 車両情報 info2（packed） |
| N3 | `RS N5` の平滑値 | 架線電圧 [V] |
| N4 | `RS N3` の平滑値 | モータ電流 [A] |
| B1 | MS B16 | 上下線方向 |

`main.sw-net` のノード名は、`RS N3`（モータ電流）を `motor_current_*`、`RS N5`（架線電圧）を `line_voltage_*`、`MS N27` と `MS N29` を `car_info0_read`、`car_info2_read` と呼ぶ。

## 映像の経路

`Main Monitor` は、次の順に Lua が重ね描きして作る。

| 順 | スクリプト | 入力 | 内容 |
|----|-----------|------|------|
| 1 | `n347.lua` | なし | 全面を灰色（160,160,160）で塗る |
| 2 | `n81.lua` | 数値 composite | メータ（速度、ブレーキ、BC 圧、MR 圧） |
| 3 | `n4.lua` | なし | 固定図形を重ねる |
| 4 | `n334.lua` | `ATS/ATC` | ATS/ATC の灯と速度パターン |
| 5 | `n349.lua` | bool/数値 composite | 非常ブレーキなどのアイコン |
| 6 | `n419.lua` | `Monitor Status`（B1 のみ MS B16 に置換） | 車両ごとの状態パネル |
| 7 | `n415.lua` | `Monitor Status` | 種別コードから選ぶ文字（アイコンのように見える圧縮した文字）と色、2 桁の数字 |

`n417.lua`（`display_init_lua`）は出力ポートを持たず、矩形を 1 つ描く（色は 0,0,5）。

### n81.lua のメータ

入力は次のとおり。

| 入力 | 元の信号 |
|------|---------|
| N1 | MS N9（ブレーキ [0–31]） |
| N4 | MS N13（速度 [m/s]） |
| N5 | `RS N2`（BC 圧 [kPa]） |
| N6 | `RS N8`（MR 絶対圧 [atm abs]） |
| B1 | MS B6（非常ブレーキ作用） |

- 速度は絶対値を 3.6 倍して km/h の 2 桁で表示する。針は平滑を通した値で動かす。
- ブレーキ針の目標値は、B1 が true または N1 が 32 以上のとき 0.25、N1 が 0 以下のとき 1.25、その間は `1.25 − N1 / 32` である。針の角度は、平滑を通した目標値に π を掛けたものである。
- BC 圧は 98 で割ってゲージにする。MR 圧は 1 を引いてゲージにする（`SignalComposite.md` の注記どおり）。

### n334.lua の ATS/ATC 画面

`ATS/ATC` の入力を次のように使う。

| 入力 | 内容 |
|------|------|
| N1 | パターン速度 [km/h]。5 km/h 刻みの座標へ対応づけてドットで示す（0 未満は描かない、110 以上は最後の座標） |
| B1 | ATC 文字 |
| B2 | 赤信号灯 |
| B3 | 青信号灯 |
| B4 | バツ灯 |
| B5 | 点滅表示（高精度パターン内。コード上の名前は `Patt`） |
| B6 | 点滅表示（前方予告。コード上の名前は `Notice`） |
| B10 | ATS 文字 |

B5 と B6 の点滅は、60 tick 周期のうち 30 tick が点灯である。B5 が高精度パターン内、B6 が前方予告を表す（verified。利用者の回答）。

### n349.lua のアイコン

| 入力 | 元の信号 | 表示 |
|------|---------|------|
| N1 | MS N9 | 0 より大きければブレーキアイコン（橙） |
| N2 | MS N10 | 0 より大きく、かつ非常ブレーキでなければ、力行アイコン（緑）と 1 桁の数字 |
| B1 | MS B6 | 非常ブレーキアイコン（赤） |
| B2 | MS B11 | NITS アイコン（緑） |
| B3 | MS B5 | `DCls` と同時に true のとき、緑の矩形 |
| B4、B5 | MS B12、MS B13 | 両方 false のとき `DCls` が true になり、戸閉アイコン（緑） |
| B6 | MS B8 | 乗客ブザーのアイコン（橙） |
| B7 | MS B7 | 次停車のアイコン（橙） |
| B8 | なし | TASC アイコン（緑）。入力側で接続されていないため、実際は表示されない |

コード中の `ConstB` はどこでも代入されないため、対応するアイコンは表示されない。TASC の B8 と `ConstB` は、未接続のまま残す（利用者の回答）。B6 に入る MS B8 は、`SignalComposite.md` では「増圧有効」であり、乗客ブザーと食い違う。信号名が誤っている可能性がある。現状の配線を優先し、今は直さない（利用者の回答）。

### n419.lua の車両状態パネル

`Monitor Status` の MS N27、MS N28、MS N29 を整数として読み、6 両分（`i = 1〜6`）を表示する。B1（MS B16 に置換）が true のときは `x = 73 + (7 − i) × 3`、false のときは `x = 73 + i × 3` に並べる。`n419.lua` は MS N31 と MS N32 から両数を計算するが、描画には使わない。

`MS N27`、`MS N28`、`MS N29`（`Extended Commands RX` のコピー）は、`CHUSO2000_Signal_Gateway` の `scripts/n523.lua` が、編成の各車の状態を詰めたものである。1 両（番号 `i`）のビットの位置と意味は次のとおり。ビットの位置は、`n419.lua` が読む位置である。

| 数値 | ビット | 名前（`n523.lua`） | 意味 |
|------|--------|-------------------|------|
| info0（N27） | `i+23` | `mcrr` | 力行（0x4B のビット 23） |
| info0 | `i+15` | `bcrr` | 回生（0x4B のビット 22） |
| info0 | `i−1` | `ext` | その車両がある |
| info1（N28） | `i+23`、`i+15`、`i+7` | `merr`、`berr`、`batl` | `n523.lua` のどこでも設定されないので、常に 0 |
| info1 | `i−1` | `sos` | 通報装置動作（0x4B のビット 21） |
| info2（N29） | `i+23` | `dclose` | 扉 A または B の開扉状態（0x41〜0x43 のビット 20、19 のどちらか） |
| info2 | `i+15` | `dcut` | 締切中（0x4B のビット 20） |
| info2 | `i+7` | `err` | 故障（0x41〜0x43 のビット 21） |
| info2 | `i−1` | `bpow` | 0x4A のビット 23（`n419.lua` では使わない） |

各両の判定と色は次のとおり。

| 行（y） | 条件 | 色 |
|--------|------|----|
| 15 | `CE` = info0 のビット `i−1`。`DClose` = `CE` かつ info2 のビット `i+23` | 赤成分が `DClose` で 255、緑成分が `CE` で 160 |
| 19 | 優先順に `Me` = `CE` かつ info1 のビット `i+23`、`Mc` = (`CE` かつ info0 のビット `i+23`) または info0 のビット `i+15` | `Me` は赤、`Mc` は橙（255,50,0）、それ以外は黒 |
| 23 | `DC` = `CE` かつ info2 のビット `i+15` | `DC` のとき赤、それ以外は黒 |
| 27 | `PNr` = `CE` かつ info2 のビット `i+7`。`PNg` = `PNr` かつ info1 のビット `i−1` かつ info1 のビット `i+7`、`i+15`、`i+23` がすべて 0 | `PNg` は橙、`PNr` は赤、それ以外は黒 |

行 19 の `Mc` は、`CE` が false でも info0 のビット `i+15`（回生）が立っていれば true になる式である。ただし、`n523.lua` は `bcrr` を、車両がある（`ext`）ときにしか立てないので、実際には `CE` が false で `Mc` が true になることはない。

### n415.lua の種別コード表示

MS N2 から種別コードを読む。`i = (N2 // 100) % 100`、`K = i // 10`、`L = (N2 // 10000) % 10`、`J` = MS N1 とする。

アイコンの選び方は次のとおり。

| 条件 | アイコン番号 | 色 |
|------|-------------|----|
| `K` = 1 | 4 | 緑 |
| `K` = 2 | 9 | 緑 |
| `K` = 3 | 5 | 緑 |
| `K` = 4 | 6 | 橙赤（255,22,0） |
| `K` = 5 | 7 | 赤 |
| `K` = 7 | 8 | 橙赤 |
| 上以外で `i` = 2 | 1 | 赤 |
| 上以外で `i` = 1 | 2 | 赤 |
| 上以外で `i` = 3 | 3 | 赤 |

上のいずれにも当たらなければ、アイコンは描かない。アイコン番号 10〜13 の描画コードがあるが、どの条件でも選ばれない。選ぶのは、種別を表す文字（アイコンのように見える圧縮した文字）と、その色である `[inferred]`（利用者の推測。ARC か 3000 系かは分からない）。`K` と `i` の値と種別の対応は `[unconfirmed]`。

`J` が 0 でなければ、下 2 桁を 2 つの数字で描く。`L` が 2 のとき右側（x=22）、1 のとき左側（x=6）に緑の印を描き、それぞれ該当しない側は黒で塗る（上下線方向の表示と読む `[inferred]`）。

### n576.lua のメータとドア状態灯

入力は前節「電気表示の平滑化」の表のとおり。

- 架線電圧（N3）は `N3 / 20 × 3` を 0〜300 に切り詰め、モータ電流（N4）は `N4 × 0.2` を −150〜150 に切り詰めて、それぞれ針の角度にする（単位は度）。
- ドア状態灯は、`Closed` が true のとき緑（3,128,3）、false のとき暗灰（6,6,6）である。

`Closed` の求め方は次のとおり。info0 の `CE` の数を `cc` とする。info2 のビット `i+15`（`DC`）が立つ両を、`i = 1` から数える。

- `sc`: `i = 1` から続く `DC` の両数。`CE` かつ `DC` でない両が現れたら、そこで数えるのをやめる。
- `ec`: 末尾（`i = 6` 側）から続く `DC` の両数。`CE` かつ `DC` でない両が現れたら 0 に戻す。

`Closed` は、B1 が true のとき `ec == cc − 1`、false のとき `sc == cc − 1` である。`DC` は info2 の `dcut`（締切中）で、`n419.lua` でも行 23（赤）に使われている。`Closed` の判定は、このコードの挙動を正とする（利用者の回答）。

## ATP Switch の Lua（`n390.lua`）

N1 を読み、32×32 の枠と地の図形を常に描く。N1 は ATP モード（`TOGGLE` が true のとき 1、false のとき 2）で、`Loop Start` の N5（保安装置選択）の元になる値と同じである。選択中の保安装置を示すアイコンと読む `[inferred]`。N1 が 1 のときと 2 のときに、それぞれ別の図形を重ねる（色は灰色と青緑）。N1 がそれ以外のときは、重ねる図形はない。旧版は「パンタグラフアイコン」と呼んでいたが、利用者は、この説明はおそらく正しくないとしている。1 と 2 がどの保安装置で、図形がどう見えるかは `[unconfirmed]`。

## 未確認事項

`[unconfirmed]` の項目の確認状況は、リポジトリ直下の `OPEN_QUESTIONS.md` にある。
