# CHUSO2000 Onecar Control 仕様書

> 実車 `CHUSO2000_2001` と `CHUSO2000_2101` には、このマイコンは搭載されていない。運転台が前位の 1 つだけなので、Cab Controller の `Control Commands TX` が Signal Gateway の `Control Commands Type 3 front` へ直接入る（`../SYSTEM_SPEC.md` §8）。以降は、前後に運転台を持つ車両での動作である。

単車制御マイコン。前方運転台側と後方運転台側から届く `Control Commands Type 3`（CC3）を 1 つにまとめ、下流（牽引制御・ドア制御など）に `Control Commands Type 3` として出力する。あわせて `Simple IF RX` の N4 / N5 と B4 / B5 を入れ替えて出力する。

ここに書く事実は `main.sw-net` と `scripts/n200.lua` から読み取ったものである。信号の意味は `SignalComposite.md` の CC3 の節を参照する。ゲーム内で確かめていない項目には `[unconfirmed]`、コードの配線から推論した項目には `[inferred]` を付ける。

## ポート

| ポート | 方向 | 型 |
|-------|------|----|
| `Control Commands Type 3 from Front` | in | composite |
| `Control Commands Type 3 from Back` | in | composite |
| `Control Commands Type 3` | out | composite |
| `Simple IF RX` | in | composite |
| `Simple IF RX inverted` | out | composite |

以降、前方側の入力を F、後方側の入力を B と書く。たとえば `F.B6` は前方側 CC3 の bool ch6 である。

## 有効側の判定

B6 は、Control Commands TX の B6（前後選択 前）と同じ意味と読む `[inferred]`。Cab Controller V の `Control Commands TX` の B6 は、編成前後選択レバーが前（+1）のときの信号である（`CHUSO2000_Cab_Controller_V/SPEC.md`）。

| 信号 | 条件 |
|------|------|
| 前方マスタ | `F.B6` かつ `B.B6` でない |
| 後方マスタ | `B.B6` かつ `F.B6` でない |
| どちらか有効 | `F.B6` または `B.B6` |

前方マスタが成り立つときだけ F の CC3 を通し、後方マスタが成り立つときだけ B の CC3 を通す。通した後の信号を「ゲート後」と呼ぶ。`COMPOSITE_SWITCHBOX` の `a` に CC3、`switch` にマスタを入れた配線である。`switch` が true のとき `a` が通る（verified。`CHUSO2000_Door_Min` でゲーム内確認済み）。

## 出力チャンネル

### 数値

| 出力 | 作り方 |
|------|--------|
| N1、N2、N3 | F と B のゲート後の値を足す |
| N4、N5 | F の値をそのまま通す（ゲートなし、B は使わない） |
| N6 | F の N6 と B の N6 を Lua（`scripts/n200.lua`）に入れ、その出力 ch1 を使う |
| N7 | 後述。F と B の N7 を bool 15 本に展開し、合成して数値に戻す |

N4、N5、N6 の意味は `SignalComposite.md` では、ブレーキ力 [kPa]、力行パラメータ、NITS 情報とされている。

### bool

出力 B_n の作り方は次のとおり。F と B は、特記しない限りゲートなしの値である。

| 出力 | 作り方 |
|------|--------|
| B1〜B3、B9〜B15、B19〜B26、B31 | `F.Bn` OR `B.Bn` |
| B4 | `F.B4` OR `B.B5` |
| B5 | `F.B5` OR `B.B4` |
| B6 | (`F.B6` OR `B.B6`) かつ スレーブでない |
| B7 | (`F.B7` OR `B.B7`) かつ スレーブでない |
| B8 | スレーブ |
| B16 | F ゲート後の B16 OR B ゲート後の B17 |
| B17 | F ゲート後の B17 OR B ゲート後の B16 |
| B18 | `F.B18` かつ `B.B18` |
| B27 | `F.B27` OR `B.B29` |
| B28 | `F.B28` OR `B.B30` |
| B29 | `F.B29` OR `B.B27` |
| B30 | `F.B30` OR `B.B28` |
| B32 | (`F.B32` OR `B.B32`) かつ (前方マスタ OR 後方マスタ) |

「スレーブ」は、(`F.B6` かつ `B.B7`) OR (`B.B6` かつ `F.B7`) である。ノード名 `slave_ch7_and` から取った呼び名で、Control Commands TX の「前後選択 前」と「後」が前後で組み合わさること、つまり「単行 前後選択正常」（Control Commands TX の B8）を表す（verified。利用者の回答）。

B4 と B5、B16 と B17、B27 と B29、B28 と B30 は、後方側の読み取りで入れ替わっている。前方車と後方車で A 側と B 側、前進と後退が反転するための処置である `[inferred]`。

### N7（packed bool）

F と B の N7 をそれぞれ数値から composite に戻し、bool の ch1〜15 を取り出す。出力の各ビットは次のとおり。出力 N7 は、この 15 ビットを composite にして数値に戻したものである。

| 出力ビット | 作り方 |
|-----------|--------|
| 1、2、5、6、8、14、15 | F の同じビット OR B の同じビット |
| 3 | F のビット 3 OR B のビット 4 |
| 4 | F のビット 4 OR B のビット 3 |
| 7 | F のビット 7 のみ |
| 9 | B のビット 7 のみ |
| 10 | F のビット 10 OR B のビット 11 |
| 11 | F のビット 11 OR B のビット 10 |
| 12 | F のビット 12 OR B のビット 13 |
| 13 | F のビット 13 OR B のビット 12 |

F のビット 9 と B のビット 9 は、出力に使われていない。

## Simple IF RX

`Simple IF RX` に対して、N4 と N5、B4 と B5 を入れ替えたものを `Simple IF RX inverted` に出す。他のチャンネルは `COMPOSITE_WRITE_*` の `inc` に元の `Simple IF RX` を入れているため、そのまま通る（`storm-mcl spec` で verified）。

## NITS キュー（`scripts/n200.lua`）

入力 N1、N2 は、float のビット列を 32bit 整数として読み直した値（NITS のパックデータ）である。毎 tick、次の順に処理する。

1. N1 を整数にデコードする。センチネル値 `1<<24`（16777216）でなければキューの末尾に積む。
2. N2 も同様に処理する。
3. キューが空でなければ先頭 1 件を出力 N1 に出し、キューから取り除く。出力は整数を float のビット列として書き戻した値である。
4. キューが空なら、センチネル値を同じ形式で出力 N1 に出す。

入力は 1 tick に 2 件まで積める。出力は 1 tick に 1 件である。キューの長さに上限はない。上限がないため、入力が出力より多い状態が続くと増え続ける。
