# CHUSO2000_Door_Min 仕様書

ドア 1 枚ぶんの最小マイコン。次の 3 つを出力する。

- ドアが開いているか（`Door is Open`）
- 開閉の切り替わりに合わせたチャイム（`Chime High` / `Chime Low`）
- ドアモーターへの速度指令（`Input`）

ここに書く事実は、`main.sw-net` / `door_position_detector.sw-net` / `door_chime.sw-net` から読み取ったものである。ゲーム内の挙動で確かめていない項目には `[unconfirmed]` を付ける。コードのコメントや名前から読み取っただけの項目には `[inferred]` を付ける。

## ポート

| ポート | 方向 | 型 | 内容 |
|-------|------|----|------|
| `Phys. Input` | in | composite | センサ A の位置。ch1 = X、ch2 = Y、ch3 = Z |
| `Phys. Input_2` | in | composite | センサ B の位置。ch1 = X、ch2 = Y、ch3 = Z |
| `Other Inputs` | in | composite | bool ch10 が NITS 開扉指令の取り込みを制御する（下記） |
| `NITS Ext. Input` | in | composite | NITS の Extended Commands RX（別名）。ドア指令を bool チャンネルで受ける |
| `Door is Open` | out | boolean | センサ距離による開判定、または開扉ラッチのどちらか |
| `Chime High` | out | boolean | 高音チャイム |
| `Chime Low` | out | boolean | 低音チャイム |
| `Input` | out | number | ドアモーターに接続される。方向（±1）× 強さ（0.2 / 0.4） |

`Phys. Input` と `Phys. Input_2` は、プロジェクト上のラベルがどちらも `Phys. Input` である。区別するときは ID を使う。

## 設定

| プロパティ | 値 | 内容 |
|-----------|----|------|
| `Door Side` | `A Right` = 27、`B Left` = 29 | 開扉指令を読む bool チャンネル。閉扉指令は 1 つ上（28 または 30）を読む |
| `Length` | 1.25 | センサ間距離がドア閉のときの基準長 |
| `Width` | 0.1 | 閉判定に許す距離の幅 |

`Door Side` ノードの `v=16` が何を保持しているかは `[unconfirmed]`。ゲームの XML（`CHUSO_2000_Door_Min.xml`）にも `v="16"` があり、storm-mcl の取り込みは XML の値を写している。16 は選択肢の値にない。旧 `SYSTEM_SPEC.md` が `Door Side` の既定を ch16 と書いていたので、古い既定値の名残と読む `[inferred]`。

## ドア状態の決まり方

`Door is Open` は、物理判定と開扉ラッチの OR である。

### 物理判定（`door_position_detector`）

2 つのセンサ間の距離の二乗を `(xA−xB)² + (yA−yB)² + (zA−zB)²` で求める。これが `(Length−Width)²` より大きく、かつ `(Length+Width)²` より小さい間を「閉」とし、閉でなければ開とする。比較は `GREATER_THAN` / `LESS_THAN` なので、境界値ちょうどは閉に含まれない。

### 開扉ラッチ（`door_open_latch`）

- 開扉指令 = `NITS Ext. Input` を通した後の信号の、`Door Side` のチャンネル
- 閉扉指令 = `NITS Ext. Input` の、`Door Side` + 1 のチャンネル
- ラッチの set は開扉指令。reset は「開扉指令が false かつ閉扉指令が true」

閉扉指令は `Other Inputs` を通さず `NITS Ext. Input` から直接読む。開扉指令が true の間は reset されないので、set と reset が同時に true になることはない。

`SR_LATCH` の初期状態は `q = false`（verified）。

### `Other Inputs` ch10 による開扉指令の制御

`COMPOSITE_SWITCHBOX` の `a` は未接続、`b` は `NITS Ext. Input`、`switch` は `Other Inputs` ch10 である。

`COMPOSITE_SWITCHBOX` は、`switch` が false のとき `b`、true のとき `a` を選ぶ（verified。ゲーム内で、`NITS Ext. Input` が Off のとき選ばれるポートにつながっていることを利用者が確認した）。storm-mcl にはこの対応表の記録がない。

- ch10 が false のとき `NITS Ext. Input` が開扉指令として通る
- ch10 が true のとき開扉指令は常に false になる（`a` が未接続のため）

`main.sw-net` の「ch10 で有効になる」というコメントは、この挙動と逆である。ch10 自体の意味（誰が何のために立てるか）は、開発者が開発意図を忘れており、不明である。コメントも、そのままにしてある。

## チャイム（`door_chime`）

`door_open_latch_q` の立ち上がりと立ち下がりの両方で、1 tick のパルス（`PULSE mode="both"`）を出す。このパルスを `COUNTER` の reset に入れる。物理判定だけが変わったときはパルスが出ない。

`COUNTER` は `up` が `CONST_BOOL`（Constant On）につながっているため、毎 tick 1 ずつ増える（`CONST_BOOL` が true を出すことは verified。利用者の回答）。範囲は 0〜120 で、`clamp = on` のため 120 で止まる。120 tick は 2 秒に当たる。

| 出力 | カウンタが入る範囲 |
|------|-------------------|
| `Chime High` | 1〜79、81〜120 |
| `Chime Low` | 21〜99、101〜120 |

- 開扉と閉扉で同じ波形を出す。違いはカウンタの起点がどちらの変化かだけである。
- 変化から 0 tick は両方とも無音である。1 tick で High が鳴り始め、21 tick で Low が加わる。80 tick の High と 100 tick の Low は、それぞれ 1 tick だけ切れる。
- カウンタは 120 で止まり、120 は両方の範囲に含まれる。そのため、変化から 2 秒以降は High / Low とも true のまま残る。これは意図どおりである（verified。利用者の回答）。音源はループではなくワンショットなので、鳴り続けない。音源には音量フェードがあり、出力が false になる tick を 1 にして、フェードを打ち消す手法を使う。
- `THRESHOLD` の min / max の境界値は、範囲に含まれる（verified。利用者の回答。`storm-mcl spec` には記載がない）。

## `Input` 出力

`Input` は、方向と強さの積で決まる。

| 要素 | 内容 |
|------|------|
| 方向 | `door_open_latch_q` で `+1` と `−1` を切り替える |
| 強さ | `CAPACITOR`（charge_time = 0、discharge_time = 1）の出力で `0.4` と `0.2` を切り替える |
| 出力 | 方向 × 強さ |

`CAPACITOR` の `enable` は、チャイムと共通の `door_state_edge_out`（ドア状態の変化パルス）である。`CAPACITOR` は、`enable` が 1 秒間 false のあいだ続くと out が false になる On/Off のバッファである（verified）。つまり変化パルスの直後は out が true で、約 1 秒後に false へ戻る。

`Input` はドアモーターにつながる（利用者の確認による）。

`NUM_SWITCHBOX` も `switch` が true のとき `a`（On 側）を選ぶ（verified。ゲーム内で、方向を決める `NUM_SWITCHBOX` の On 側に `+1`、Off 側に `-1` がつながっていることを利用者が確認した）。強さの `NUM_SWITCHBOX` も、同じノード種別なので同じ対応と読む `[inferred]`。この対応では次のようになる。

- 方向: ラッチが true（開）のとき `+1`、false（閉）のとき `-1`（verified）。
- 強さ: ドア状態が変わってから約 1 秒間は `0.4`、その後は `0.2`。

扉が動き始めの約 1 秒は速く、その後は遅い速度になる。強さを切り替える意図は、電力の削減と、動きのリアリティの向上である（verified。利用者の回答）。

## 未確認事項

`[unconfirmed]` の項目の確認状況は、リポジトリ直下の `OPEN_QUESTIONS.md` にある。
