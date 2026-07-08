# NITS Simple Bridge 詳細仕様

> - 対象: `NITS_Simple_Bridge/main.sw-net` および `scripts/n440.lua`(`nits_tx_encoder_lua`)・`scripts/n466.lua`(`nits_rx_decoder_lua`)・`scripts/n458.lua`(`simpleif_tx_encoder_lua`)・`scripts/n848.lua`(`ext_output_decoder_lua`)
> - 種別: NITS（Nona's Integrated Train System）バスと車両内制御系（Simple IF）・拡張データバス（NITS Extension）を仲介するブリッジマイコン
> - 参照仕様: 公式ドキュメント [NITS](https://nonasaba.net/sw-train-docs/communicate/NITS.html)・[NITS Simple Bridge](https://nonasaba.net/sw-train-docs/communicate/NITS-Simple-Bridge.html)（ユーザ提供のMarkdown原文に基づく）
> - 本書は sw-net の配線と Lua 実装を、公式仕様のビット定義と突き合わせて検証した解析結果である。突き合わせが取れた箇所は確定情報として、ツールの内部仕様に依存し検証未了の箇所は明示的に留保して記述する。

---

## 0. 位置づけ・全体像

NITSは編成内の車両間をデイジーチェーンで結ぶコマンドベース総括制御システムであり、各車両は0x41-0x47の共通コマンドを解釈・生成する必要がある。「NITS Line Node」がフル実装のマイコンであるのに対し、本機「NITS Simple Bridge」は0x41-0x47の生成・解読ロジックを肩代わりし、車両側には次の簡易インターフェースのみを提供する簡易版である。

- **Simple IF**（TX/RX）: 自車の運転・サービス機器状態を0x41-0x43に変換／NITSから解読した編成全体の状態を自車機器へ中継する composite インターフェース
- **NITS Extension**（Input/Output）: 0x48-0x4Fの拡張コマンドを使い、ユーザ定義の任意データ（N1-N16, 3モード選択可）を前後の車両と交換するための入出力

すなわち本機は「生の0x41-0x47/0x48-0x4Fバイナリを直接読み書きするNITSバス」と「読み書きしやすいSimple IF / NITS Extension composite」の間の変換ブリッジである。

### 0.1 ポート一覧

| ポート | 方向 | 型 | 役割 |
|---|---|---|---|
| `from NITS` | in | composite | NITSバスの生データ（N1-N31=各車両の直近送信ワード、N32=コモンライン情報） |
| `to NITS` | out | composite | 自車が生成した0x41-0x47ワード（前後両方向）＋Lua健全性(B1=Lua動作異常なし)・Simple IF由来ビットの中継 |
| `Simple IF TX` | in | composite | 自車の運転・サービス機器からのコマンド入力（B1-B32, N1-N3 等） |
| `Simple IF RX` | out | composite | NITSから解読した編成全体の状態を自車機器へ返す |
| `NITS Extension Output` | out | composite | 拡張コマンド(0x48-0x4F)の受信結果。N1-N8=瞬時値、N9-N16=メモリ保持値（`project.json`記載どおり） |
| `NITS Extension Input` | in | composite | 拡張コマンドとして送信したい任意データ。N1-N8=後方向、N9-N16=前方向（`project.json`記載どおり、任意） |

### 0.2 内部ブロック構成

```
"Simple IF TX" ──┐
                 ├─▶ simpleif_tx_encoder_lua (n458.lua) ─▶ simpleif_tx_encoder_lua_composite ─┬─▶ nits_tx_command_composite ─▶ nits_tx_encoder_lua (n440.lua) ─▶ "to NITS"
"NITS Extension  │                                                                            │        ▲
 Input" ─────────┘                                                                            │        │
                                                                                               │  nits_rx_decoder_lua (n466.lua) ◀── "from NITS"
                                                                                               │        │
                                                                          rx_addr_conflict/total_car ────┘
                                                                                                        │
                                                                                                        ▼
                                                                                              "Simple IF RX" (中継)

"from NITS" ─▶ nits_rx_gate_switch (COMPOSITE_SWITCHBOX, switch=local_mode_timer) ─▶ ext_output_decoder_lua (n848.lua) ─▶ MEMORY_REGISTER×8(N9-16保持) ─▶ "NITS Extension Output"
```

---

## 1. sw-net 表記の前提（本書での解釈）

- `inst TYPE name (params) : in=... -> out=...` 形式。`channel=` は composite 上のスロット指定で、**元XMLの属性値をそのまま転記した0始まりの値**である（sw-net変換ツール`storm-mcl`は`channel`に対して一切の演算を行わないパススルー値であることを確認済み）。
- 各 Lua スクリプトの `input.getBool(i)/getNumber(i)`・`output.setBool(i)/setNumber(i)` は **1始まり**。**「XMLでのチャンネル0 = Luaでのチャンネル1」が確定仕様**であるため、sw-net の `channel=N` は Lua 側の **index N+1** に一致し、`channel=null`（XML上`i`属性が省略された既定スロット）は Lua 側の **index 1** に一致する。この対応は本書の解析中に複数箇所で独立に突き合わせても矛盾がないことを確認済み（§3.3 の `rx_addr_conflict`→B6 一致、§2 の `push_ext` back/front 値の意味一致、`nits_tx_watchdog_read`→`output.setBool(1,watchdog)` 一致）。以降の記述はこの対応関係に基づく。
- `COMPOSITE_WRITE_BOOLEAN/NUMBER (count=N, offset=M)` は `inc=` で指定された既存 composite をベースに、`in1..inN` を（0始まりの）チャンネル `offset, offset+1, ..., offset+N-1` へ書き込む（Lua側 index では `offset+1 .. offset+N`）。`inc` 側の他チャンネルはそのまま透過する。
- `SR_LATCH`・`CAPACITOR`・`MEMORY_REGISTER`・`COMPOSITE_SWITCHBOX`の詳細挙動（reset/set優先度・充放電中の出力値・switch=false時のb未接続時の既定値等）は、リポジトリ内の`SYSTEM_SPEC.md`/`SignalComposite.md`には明文化されておらず、Stormworks標準ロジックノードの一般的挙動（reset優先のSRラッチ、charge/dischargeタイマとしてのCAPACITOR、`switch?a:b`かつb未接続時は0/false）を前提に解析した。これは本リポジトリの他のSPEC.md（例:`CHUSO1800_Traction_Controller/SPEC.md`§0.1）と同じ前提である。
- Lua ノード（`inst LUA name (script_ref=...)`）の出力 composite は、`output.set***` で上書きしない限り**直前tickの出力値を保持し続ける**（レジスタ的な保持動作。入力compositeからの自動透過は無い）。一度も設定されていないチャンネルの初期値は0/false（作者確認済み）。したがって「スクリプトが一度も触れないチャンネル」は恒久的に初期値0/falseのまま変化しない。

---

## 2. NITS TXフレーム生成 (`nits_tx_encoder_lua` / n440.lua)

### 2.1 入力（`nits_tx_command_composite_out`、sw-net上の配線経由）

| 種別 | sw-net channel (0始まり) | Lua index | 内容 |
|---|---|---|---|
| bool | 5 | curB[6] | `rx_addr_conflict_read_out`（後述、自ID競合検出） |
| bool | 6 | curB[7] | `tx_interrupt_flag_out`（即時送信要求） |
| bool | 7 | curB[8] | `simpleif_push_flag_out`（拡張コマンド新規エンコード通知） |
| bool | 8 | curB[9] | `tx_override_flag_out`（同上、即時送信系） |
| number | 5 | curN[6] | `simpleif_cmd_value_back_read_out` = Simple IF TX 由来の「後方向」拡張値 |
| number | 6 | curN[7] | `simpleif_cmd_value_front_read_out` = 同「前方向」拡張値 |
| number | 7 | curN[8]（未使用） | `rx_total_car_count_read_out`（総車両数、本スクリプトでは未参照） |

さらに `curB[1..32]`／`curN[1..9]` は Simple IF TX 起源の運転・サービス機器状態（後述 §2.2 で個別対応）を、`input.getBool/getNumber` で直接読む。これらは `nits_tx_command_composite_out` 自体が `inc="Simple IF TX"` を経由して合成されているため（`tx_override_number_write` の `inc="Simple IF TX"`）、Simple IF TX の生チャンネルがそのまま透過している。

### 2.2 0x41-0x43 共通ビット (b19-b23) の抽出

```lua
b43 = bit_arr(curB, 1, 5) << 19
```

`bit_arr` は `curB[1]`をMSB、`curB[5]`をLSBとする5bit値を組み立てる。すなわち:

| Lua bit | 意味 (Simple IF TX 共通表) | 出力ビット |
|---|---|---|
| curB[1] | B1 = 非常ブレーキ | bit23 |
| curB[2] | B2 = 連絡ブザー | bit22 |
| curB[3] | B3 = 故障通報 | bit21 |
| curB[4] | B4 = 扉A側 開扉状態 | bit20 |
| curB[5] | B5 = 扉B側 開扉状態 | bit19 |

これは公式仕様の0x41/0x42/0x43共通ビット（rowspan=3, bit23-19）と完全一致する。

### 2.3 0x41-0x42 共通ビット (b13-b18) — エッジ検出

```lua
b41_42 = b43 | bit_arr(riseB, 10, 15) << 13
```

`riseB[i]` は「直前tickでfalse→今tickでtrueになった」立ち上がりエッジのみを保持するフラグ（onTick冒頭で毎tick更新）。

| Lua bit (rise) | 意味 | 出力ビット |
|---|---|---|
| riseB[10] | B10 = パンタグラフ上昇 | bit18 |
| riseB[11] | B11 = パンタグラフ降下 | bit17 |
| riseB[12] | B12 = エンジン始動 | bit16 |
| riseB[13] | B13 = エンジン停止 | bit15 |
| riseB[14] | B14 = 走行用バッテリー起動 | bit14 |
| riseB[15] | B15 = 走行用バッテリー停止 | bit13 |

公式表のbit18-13（パンタ上/下・エンジン始/停・バッテリ始/停、0x41/0x42共有のrowspan=2領域）と一致。**これらは状態ではなく単発パルス（押した瞬間の1コマンドのみ送信）として設計されている**点に注意（B19-B23は状態値、B10-B15は動作トリガという明確な使い分け）。

### 2.4 0x41 フレーム（力行・制動・方向・DB自動 — 状態値）

```lua
if curB[32] and (force41 or (arr_or(refB, 16, 18) or arr_or(refN, 1, 3))) then
  local p = (0x41 << 24)|b41_42
  p = p|bit(curB[18], 12)|bit(curB[16], 9)|bit(curB[17], 8)
  p = p|shift(curN[3], 10, 2)|shift(curN[2], 5, 3)|shift(curN[1], 0, 5)
  ...
  return p, bit_ex(bit_ex(p, 20, 19), 9, 8), true
```

| Lua | 内容 | 出力ビット |
|---|---|---|
| curB[18] | B18 = ダイナミックブレーキ(自動) | bit12 |
| curB[16] | B16 = 前進 | bit9 |
| curB[17] | B17 = 後退 | bit8 |
| curN[3] (2bit) | N3 = ダイナミックブレーキ(手動) | bit11-10 |
| curN[2] (3bit) | N2 = 力行 | bit7-5 |
| curN[1] (5bit) | N1 = ブレーキ | bit4-0 |

公式表の0x41行と全ビット完全一致。**送信条件**は「B32(運転台起動)がON」かつ「(強制送信タイマ切れ) または (前進/後退/DB自動のいずれかが変化) または (N1-N3のいずれかが変化)」。強制送信タイマ (`n41time`, 60tick=1秒でリロード) により、状態が変化しなくても**1秒に1回は必ず0x41を再送**し、変化があれば即座に送信する。これは公式仕様の「0x41は、もっとも最近送られてきた値を編成全体の制御情報とする」（＝latest-wins・都度上書き型）の設計と整合的（一種のハートビート付き状態同期）。

送信後、`riseB[1..5]`・`riseB[10..15]`・`refB[16..18]`・`refN[1..3]` をクリアする（`riseB[1..5]`は本フレームの計算にcurBを使っており未使用だが、慣習的にまとめてクリアしている＝実害のない冗長操作、§5参照）。

**返り値の2ワード**: `p`（そのまま）と `bit_ex(bit_ex(p,20,19),9,8)`（bit20↔19、bit9↔8を交換した鏡像）の2つを返す。前者は「前方向」、後者は「後方向」（あるいはその逆）用の送信ワードであり、**扉A/B状態(bit20/19)と前進/後退(bit9/8)のみを入れ替えた鏡像を、もう一方の方向へ同時送出する**。これは本ブリッジを境に前後で車両の物理的な向き（A側=前を向いて右、B側=前を向いて左）が反転するための補正であり、§3.4のRX側デコードで行われる同種の入れ替えと対をなす。

### 2.5 0x42 フレーム（動作トリガ群 — パルス値）

```lua
if arr_or(riseB, 10, 15) or arr_or(riseB, 19, 30) then
  local p = (0x42 << 24)|b41_42|bit_arr(riseB, 19, 30)
  ...
  return p, bit_ex(bit_ex(bit_ex(p, 20, 19), 3, 1), 2, 0), false
```

`bit_arr(riseB,19,30)` は12bit値（riseB[19]がMSB→bit11、riseB[30]がLSB→bit0）:

| Lua (rise) | 内容 | 出力ビット |
|---|---|---|
| riseB[19] | B19=案内表示 起動 | bit11 |
| riseB[20] | B20=案内表示 停止 | bit10 |
| riseB[21] | B21=チャイム 起動 | bit9 |
| riseB[22] | B22=チャイム 停止 | bit8 |
| riseB[23] | B23=室内灯 起動 | bit7 |
| riseB[24] | B24=室内灯 停止 | bit6 |
| riseB[25] | B25=ヒータ 起動 | bit5 |
| riseB[26] | B26=ヒータ 停止 | bit4 |
| riseB[27] | B27=扉A 開扉 | bit3 |
| riseB[28] | B28=扉A 閉扉 | bit2 |
| riseB[29] | B29=扉B 開扉 | bit1 |
| riseB[30] | B30=扉B 閉扉（公式表記は「開扉」表記だが対称性から閉扉の誤記と判断） | bit0 |

公式表の0x42行と一致（b18-13はb41_42経由で0x41と共有）。送信条件は「いずれかのパルス系ビットが立ち上がった」場合のみ（B32のチェックなし＝運転台起動していなくても機器操作コマンドは送出される）。鏡像側は 扉A/B状態(20/19) に加え、扉A開/扉B開(3/1)・扉A閉/扉B閉(2/0) も入れ替える。

### 2.6 0x43 フレーム（力行パラメータ・ブレーキ力 — アナログ値）

```lua
b43 = 0x43 << 24|b43|shift(curN[5], 9, 10)|shift(curN[4] / 2, 0, 9)
return b43, bit_ex(b43, 20, 19), false
```

| Lua | 内容 | 出力ビット |
|---|---|---|
| curN[5] (10bit) | N5=力行パラメータ | bit18-9 |
| curN[4]/2 (9bit) | N4=ブレーキ力[kPa]の**半分の値** | bit8-0 |

公式表「ブレーキ力（kPa単位とし、半分の値を伝送）」の記述と`/2`が完全一致。0x41-0x43はいずれの分岐にも該当しない場合、**tick毎に必ず0x43が送信される**（elseに相当するデフォルト経路）。

### 2.7 0x47 フレーム（ID宣言／異議申し立て）・拡張キュー・割り込み

```lua
if curB[6] then                      -- deny (=rx_addr_conflict, 自ID競合検出時)
  ext2b, ext2f = {}, {}
  return 0x47 << 24, 0x47 << 24, false
end
if curB[7] then                      -- interrupt (=tx_interrupt_flag)
  return unpk(input.getNumber(6)), unpk(input.getNumber(7)), false
end
if refN[8] or refB[32] then          -- 拡張モード確認宣言
  refN[8] = false; refB[32] = false
  return 0x47 << 24|EXT_ID, 0x47 << 24|EXT_ID, false
end
...
if extlast >= 1 then                 -- 拡張FIFOキューの送出
  local e1,e2=pop_ext(); return e1, e2, false
end
if curB[9] then                      -- override (=tx_override_flag)
  return unpk(input.getNumber(6)), unpk(input.getNumber(7)), false
end
```

- **`curB[6]`(=`rx_addr_conflict_read_out`)**: n466.lua が自ID(`EXT_ID`)と異なる非ゼロIDの0x47を検出した（真の競合）ときにON。ONの間、拡張キューを空にし、**`0x47<<24`（=`0x47000000`）を即座に送出**する。これは公式仕様の「宣言後3秒以内に異議申し立てとして0x47000000が届いた場合は移行を阻止する」の**異議申し立て側**の送信ロジックそのものである。
- **`refN[8] or refB[32]`**: N8（後述、拡張入力用途と推測）または B32（運転台起動）の変化をトリガに、`0x47<<24|EXT_ID` を1回宣言送出する。
- **`extlast>=1`**: `curB[8]`(push要求)により `curN[6]/curN[7]` からpushされた拡張FIFOキュー(`ext2b`/`ext2f`)を1件ずつ`pop_ext()`で送出する。
- **`curB[7]`/`curB[9]`（interrupt/override）**: いずれも `input.getNumber(6)/(7)` の生値（＝Simple IF TX由来の拡張コマンド値、sw-net上 `simpleif_cmd_value_back/front`）を無変換でそのまま即時送出する、優先度の高いバイパス経路。**ただし`curB[7]`(=`tx_interrupt_flag_out`)・`curB[9]`(=`tx_override_flag_out`)は、その供給元である`ext_input_interrupt_req`/`ext_input_override_req`が§6・§7 F8のとおり常時false固定のデッド配線であるため、現在の配線では両分岐とも実質到達不能である。**

### 2.8 Luaクラッシュ検知ウォッチドッグ

```lua
watchdog = not watchdog
...
output.setBool(1, watchdog)
```

`watchdog` は毎tick反転するトグル。sw-net側では:

```
nits_tx_watchdog_not     = NOT(nits_tx_watchdog_read_out)
nits_tx_watchdog_xor     = XOR(nits_tx_watchdog_read_out, nits_tx_watchdog_not_out)
nits_tx_watchdog_xor_not = NOT(nits_tx_watchdog_xor_out)
nits_tx_strobe_cap       = CAPACITOR(charge_time=0, discharge_time=0.1)(enable=nits_tx_watchdog_xor_not_out)
```

一見すると`XOR(a, NOT a)`は同一tick内なら恒真（常にtrue）であり、この回路は無意味に見える。しかし実機Stormworksのロジックゲートはチェーンした各ゲートが1tickずつ遅延して伝搬する（本リポジトリの`CHUSO1800_Traction_Controller/SPEC.md`§0.2が採用するのと同じ解析上の前提）ため、`nits_tx_watchdog_not_out`は`nits_tx_watchdog_read_out`の**1tick前**の値のNOTになる。`watchdog`が正常に毎tickトグルしている間は、この「1tickずれたNOT」と「現在値」の関係が一定のパターンで安定し、`nits_tx_watchdog_xor_not_out`（延いては`nits_tx_strobe_cap`のenable）は安定した値を取り続ける。**ところがLuaがエラーで実行停止すると、Stormworksの仕様上そのマイコンのLuaは以後のtickで一切実行されなくなり、`output.setBool(1,watchdog)`の値（＝`nits_tx_watchdog_read_out`）はエラー発生時の値のまま凍結する**。トグルという前提が崩れるため、上記のNOT/XOR遅延段の整合が崩れ、`nits_tx_strobe_cap`のenableが反転し、`discharge_time=0.1`のCAPACITORにより約0.1秒後に`nits_tx_strobe_cap_out`がfalseへ変化する。

これは**意図的なLuaクラッシュ検知ウォッチドッグ**であり、「Luaがエラーで停止すると以後のtickで実行されなくなる」というStormworksの仕様を逆手に取った設計である（当初解析でこの回路を「常時false固定のデッド回路」としたのは誤りであり、本節で訂正する）。`nits_tx_strobe_cap_out`は`nits_tx_bus_write`のin1(offset=0→"to NITS"のbool ch1)として送出されており、これは公式仕様の「基本マイコンのインターフェース」入力欄に記載された **`B1: Lua動作異常なし`** に正確に対応する。すなわち本ブリッジは、自身の0x41-0x47エンコードLua(`n440.lua`)が健全に動作している間は`"to NITS"`のB1をtrueに保ち、クラッシュした場合は約0.1秒でfalseへ落とすことで、下流（NITS Line Node等）に自身の異常を通知する。

---

## 3. NITS RXフレーム解読 (`nits_rx_decoder_lua` / n466.lua)

### 3.1 概要

「from NITS」の31個の数値チャンネル(N1-N31、各車両の直近送信ワードをfloat再解釈したもの)を毎tickスキャンし、オペコード(`(dt>>24)&0xff`)ごとに処理する。

### 3.2 車両在線判定と保持(ラッチ)ロジック

```lua
dt = unpk(input.getNumber(32))
local front_car = dt & 31       -- 前方車両数 (5bit)
local last_car  = (dt >> 5) & 31 -- 後方車両数 (5bit)

for i = front_car+1, 15 do data_s4x[i] = 0 end
for i = 17, 31-last_car do data_s4x[i] = 0 end

for i = 1, 31 do
  dt = unpk(input.getNumber(i))
  ch = (dt >> 24) & 0xff
  ...
  if ch >= 0x41 and ch <= 0x43 then
    s4x = true
    data_s4x[i] = dt
  end
  ...
end
```

`data_s4x`はスクリプトのトップレベルで宣言されたモジュール永続テーブルであり、tick間で値を保持する。これにより:

- 0x41-0x43を受信したスロットのみ`data_s4x[i]`を更新する（受信しなければ前回値を保持）
- `front_car`/`last_car`の範囲外（＝車両が存在しない）スロットは明示的に0クリアする

という、公式仕様の「0x41-0x43共通の信号（b19-b23）について」の節に書かれたアルゴリズム（車両存在時は更新、非更新時は直前値保持、車両不在時は消去）を**本ブリッジ自身がこのRXデコーダ内で実装している**ことが確認できる。以降のOR集約(§3.3)はこの`data_s4x`（＝現在有効な車両のみを保持したキャッシュ）に対して行われるため、離脱済み車両の古い値が誤って混入することはない。

`front_car`/`last_car`はN32（コモンライン情報）から抽出している。公式仕様の0x46行では後方車両数側のフィールドが「（後方両数　伝送無し）」と明記されているが、これはNITS Line Nodeが**他車へは**後方車両数を送出しないという意味であり、NITS Line Node自身は前後両方向から届く前方両数を内部でマージし、本ブリッジには（マージ済みの）後方両数として`last_car`を正しく与えている（公式仕様書側にこの内部合成処理の記載が欠落している。§7 F5、作者確認済み）。また、公式仕様の0x46行では「前方両数」列が4bit(colspan=4)と記載されているが、本スクリプトは`dt & 31`で5bitマスクしている。この差異は、NITSが本来対応しない「16両以上の編成」を検知するための意図的な設計である（§7 F4、作者確認済み）。

### 3.3 0x41/0x42共通ビット・0x42固有ビットのOR集約と前後入れ替え

```lua
if ch == 0x41 then
  s41 = i
  for j = 10, 15 do op[j] = op[j] or gbit(dt, 28 - j) end
end
if ch == 0x42 then
  for j = 10, 15 do op[j] = op[j] or gbit(dt, 28 - j) end
  for j = 19, 26 do op[j] = op[j] or gbit(dt, 30 - j) end
  if i <= 16 then
    op[27]=op[27] or gbit(dt,3); op[28]=op[28] or gbit(dt,2)
    op[29]=op[29] or gbit(dt,1); op[30]=op[30] or gbit(dt,0)
  else -- i>16 = 自分より後の車両。扉A/B(左右)が反転する
    op[27]=op[27] or gbit(dt,1); op[28]=op[28] or gbit(dt,0)
    op[29]=op[29] or gbit(dt,3); op[30]=op[30] or gbit(dt,2)
  end
end
```

`j=10..15`（パンタ上/下・エンジン始/停・バッテリ始/停）と`j=19..26`（案内表示・チャイム・室内灯・ヒータ 起動/停止）は前後で入れ替えない（左右非対称な機構ではないため）。一方`j=27..30`（扉A/B 開/閉）は**スロット番号 i>16（＝自分より後の車両。公式仕様のN17-N31=後方車両の並び順に対応）のとき、扉A系と扉B系のビットを入れ替える**。これは「A側は前を向いて右側、B側は前を向いて左側」という向きの定義上、後方の車両からは前後が逆転して見えるための補正である。

同様の入れ替えは、扉状態(b19-23由来)のうち扉A/B開扉状態(op[4]/op[5])および前進/後退(B16/B17)にも適用される:

```lua
for i = 1, 32 do
  dt = data_s4x[i] or 0
  op[1] = op[1] or gbit(dt, 23)             -- 非常ブレーキ: 前後不問
  if i ~= 16 then op[2] = op[2] or gbit(dt, 22) end  -- 連絡ブザー: 自車(i=16)は除外して集約
  op[3] = op[3] or gbit(dt, 21)             -- 故障: 前後不問
  if i <= 16 then
    op[4]=op[4] or gbit(dt,20); op[5]=op[5] or gbit(dt,19)   -- 扉A/B状態
  else
    op[5]=op[5] or gbit(dt,20); op[4]=op[4] or gbit(dt,19)   -- 後方車両は入れ替え
  end
end
```

`op[2]`（連絡ブザー）のみ自スロット(i=16、自車の直近送信値)を集約対象から除外している。これは自分が鳴らしたブザーを自分への着信として扱わないための意図的な設計と考えられる。

前進/後退(B16/B17)は0x41単一送信元(`s41`, 最新の0x41送信スロット)からのみ取得し、OR集約ではなく**最新値をそのまま採用**する（公式仕様「0x41は、もっとも最近送られてきた値を編成全体の制御情報とする」に対応）:

```lua
if s41 ~= 0 then
  dt = unpk(input.getNumber(s41))
  output.setNumber(1, dt & 31)        -- N1 = ブレーキ (5bit)
  output.setNumber(2, (dt>>5)&7)      -- N2 = 力行 (3bit)
  output.setNumber(3, (dt>>10)&3)     -- N3 = ダイナミックブレーキ(手動) (2bit)
  output.setBool(18, gbit(dt,12))     -- B18 = ダイナミックブレーキ(自動)
  if s41 <= 16 then
    output.setBool(16, gbit(dt,9)); output.setBool(17, gbit(dt,8))
  else
    output.setBool(16, gbit(dt,8)); output.setBool(17, gbit(dt,9))  -- 後方車両由来は前進/後退を入れ替え
  end
  output.setBool(9, true)
else
  output.setBool(9, false)
end
```

### 3.4 0x47（ID宣言/異議）処理

```lua
if ch == 0x47 then
  if (dt & 0xffffff) == ID then
    output.setBool(8, true)                       -- 自ID一致 = OK
  else
    if (dt & 0xffffff) ~= 0 then
      output.setBool(6, true)                     -- 非ゼロの他ID = 真の競合
    end
    output.setBool(7, true)                       -- 不一致全般 = Reject
  end
end
```

`ID`は`property.getText("NITS Ext. ID")`を16進数として解釈した値。ペイロード下位24bitが0の`0x47000000`は公式仕様上の「異議申し立て」専用フレームであり、`ID`（0や201-255は仕様上未割当のため実運用では非ゼロ）とは一致し得ないため、`B6`(競合)は立てず`B7`(Reject)のみを立てる、という条件分岐が公式仕様の異議申し立て仕様と正確に対応している。

- **B6 = 内部用(Reject and data is not 0)**: 自分と異なる非ゼロIDの宣言を検出（真のID重複）
- **B7 = 内部用(Reject)**: 自ID宣言が一致しなかった全ケース（異議申し立てを含む）
- **B8 = 内部用(OK)**: 自分の宣言したIDがそのまま返ってきた（宣言成立）

### 3.5 拡張モード（ローカルモード）ラッチとゲート

sw-net側:

```
ext_mode_latch = SR_LATCH(r=rx_addr_not_mine_read_out(B7), s=rx_addr_matched_read_out(B8))
local_mode_timer = CAPACITOR(charge_time=3, discharge_time=0)(enable=ext_mode_latch_q)
nits_rx_gate_switch = COMPOSITE_SWITCHBOX(a="from NITS", switch=local_mode_timer_out)
ext_output_decoder_lua ← nits_rx_gate_switch_out
```

自ID宣言が確定(B8)するとラッチがセットされ、以後**いずれかの0x47不一致(B7)を観測するたびにリセット**される。ラッチがONの状態が3秒(`charge_time=3`)継続すると`local_mode_timer_out`が立ち、`from NITS`が`ext_output_decoder_lua`（拡張コマンドのデコーダ、§4）へ通される。discharge_time=0のため、ラッチが落ちると1tickも待たず即座にゲートも閉じる。

これは公式仕様の「両数が変化した場合とその他必要なトリガによって宣言を行い、宣言から3秒後に固有モードに移行する。宣言後3秒以内に異議申し立てとして0x47000000が届いた場合は移行を阻止する」を実装したものである。

**留意点**: `ext_mode_latch`のリセット条件(`rx_addr_not_mine`=B7)は、自分のID宣言に対する異議申し立てだけでなく、**編成中の別のマイコンが自分とは無関係な別のIDを宣言した場合にも成立してしまう**（B7は「0x47かつ自ID不一致」全般を検出するため）。したがって、多数の拡張マイコンが同時多発的にID宣言を行う起動直後などは、無関係な宣言の連鎖により各車の`local_mode_timer`が繰り返しリセットされ、拡張モードへの移行が想定以上に遅延する可能性がある（要検証、§5）。

---

## 4. Simple IFコマンドエンコーダ (`simpleif_tx_encoder_lua` / n458.lua)

### 4.1 概要

「NITS Extension Input」(N1-N8=後方向値, N9-N16=前方向値, B1-B16=有効フラグ)を、チャンネルごとに設定可能な3モード（Integer same / Binary same / Binary separate、`NITS Extension Output`側の説明を参照）に従い、0x48-0x4Fの拡張コマンドへラウンドロビン方式で変換する。

```lua
MODE={}
for i=1,8 do
  MODE[i]=_pg(("M%d/N%d Mode"):format(i,i+8))
  ...
```

### 4.2 【要注意】プロパティ名の不一致（M vs N）

本スクリプトは`property.getNumber("M1/N9 Mode")`のように**先頭を`M`**として8つのモード設定値を取得している。しかし`main.sw-net`で実際に宣言されているプロパティは:

```
inst PROPERTY_DROPDOWN n1_n9_mode (name="N1/N9 Mode") ...
...
inst PROPERTY_DROPDOWN n8_n16_mode (name="N8/N16 Mode") ...
```

と、先頭が**`N`**である。つまりスクリプトが参照するプロパティ名（`"M1/N9 Mode"`等）と実際に定義されているプロパティ名（`"N1/N9 Mode"`等）が一致しない。Stormworksの`property.getNumber`は存在しない名前に対して既定値0を返す仕様であるため、これが事実であれば **`MODE[i]`は常に0（`Integer same`相当のビットパターン）に固定され、ユーザがドロップダウンで`Binary same`/`Binary separate`を選択しても一切反映されない**という実質的な不具合になっている可能性が高い。

同一の`"M%d/N%d Mode"`参照は`n848.lua`（受信側デコーダ、§5.2）にも存在し、両者で一貫してこの名前を使っているため、送受信間の不整合（片方だけ違うモードになる）は生じない。**影響は「モード選択機能そのものが常時Integer sameに固定され、選択が反映されない」という一方向の機能欠落にとどまる**と考えられる（要ゲーム内検証）。

### 4.3 ラウンドロビン送信ロジック

```lua
for i=1,8 do
  if curB[i] or curB[i+8] then
    local b,f = curN[i], curN[i+8]
    if (MODE[i] & 1)==0 then f=b; chgN[i+8]=false end        -- bit0=0: 前後同一値
    if (MODE[i] & 2)==0 then b=toi(b); f=toi(f)               -- bit1=0: 整数化(Integer)
    else b=unpk(b); f=unpk(f) end                              -- bit1=1: Composite to Number相当(Binary)
    if chgN[i] or chgN[i+8] or riseB[i] then
      sig[i].b=b; sig[i].f=f; sig[i].up=true
    end
  end
end
```

`curB[i]`(後方向有効フラグ)または`curB[i+8]`(前方向有効フラグ)がONのチャンネルのみ処理対象とし、値変化(`chgN`)または後方向フラグの立ち上がり(`riseB[i]`)で送信保留(`sig[i].up`)を立てる。**前方向フラグの立ち上がり(`riseB[i+8]`)は保留トリガの条件に含まれていない**ため、前方向の値が変化せずフラグだけが新規に立った場合、その回では送信保留が起きない。これは前後非対称のまま**意図された仕様**である（§7 F6、作者確認済み）。

```lua
interval = interval - 1
if interval <= 0 then
  while channel < 8 do
    channel = channel + 1
    if sig[channel].up then
      db,df = sig[channel].b, sig[channel].f
      cmd = 0x48 - 1 + channel
      sig[channel].up = false
      break
    end
  end
  if channel >= 8 then interval = 2; channel = 0 end
end
```

保留中のチャンネルを`channel`から順に走査し、見つかったら1tickにつき1チャンネルずつ送信（`cmd`=0x48-0x4F）。全8チャンネルを走査して保留がなければ`interval=2`をセットして2tick休止してから`channel=1`から再走査する。保留があれば連続tickで詰めて送信できる（走査自体は毎tick進むため、次にどのチャンネルに保留があるかによって実質的な送信間隔は変動する）。

出力: `output.setNumber(6, pk((cmd<<24)|(db&0xffffff)))`（後方向）、`output.setNumber(7, ...)`（前方向）、`output.setBool(14, cmd~=0)`（今tick送信したか＝`simpleif_push_flag`の実体）。

---

## 5. NITS Extension Output デコーダ (`ext_output_decoder_lua` / n848.lua)

```lua
MODE={}
for i=1,8 do MODE[i]=_pg(("M%d/N%d Mode"):format(i,i+8)) end

for i=1,31 do
  f = input.getNumber(i)
  o = unpk(f)
  c = ((o>>24)&0xff) - 0x48 + 1
  if c>=1 and c<=8 then
    if (MODE[c] & 2)==0 then opN[c] = (o & 0xffffff) * 1.0   -- Integer
    else opN[c] = f end                                        -- Binary(生floatのまま)
    opB[c] = true
  end
end
for i=1,8 do output.setNumber(i, opN[i]); output.setBool(i, opB[i]) end
```

`from NITS`の31スロットを毎tickスキャンし、オペコードが0x48-0x4F(`c=1..8`)のものを見つけたらチャンネル`c`の値として採用する（複数スロットに該当があった場合、走査順で後のものが上書きで残る＝OR集約ではなく単純上書き）。§4.2と同一のプロパティ名不一致があるため、`MODE[c]`は常に0となり、実運用では常に「整数値として`(o&0xffffff)`をそのまま採用（Integer模式）」の分岐固定になっていると考えられる。

出力`N1-N8`/`B1-B8`はこの評価結果を**その場でそのまま**出力する（前tick以前の値は保持しない、＝該当opcodeを受信しないtickでは0/falseに戻る瞬時値）。

### 5.1 N9-N16への保持（メモリレジスタ）

sw-net側:

```
ext_out_n9_memory = MEMORY_REGISTER(reset_value=0)(reset=rx_addr_not_mine_read_out, set=ext_out_n1_flag_read_out, value=ext_out_n1_value_read_out)
... (N10-N16も同様にN2-N8対応)
ext_output_bus_write (count=8, offset=8): in1..in8 = ext_out_n9..n16_memory_out, inc=ext_output_decoder_lua_composite -> "NITS Extension Output"
```

n848.luaが出力したN1-N8の瞬時値を、対応するフラグ(B1-B8)が立った時にMEMORY_REGISTERへラッチし、`rx_addr_not_mine_read_out`（自ID不一致＝§3.5のB7と同一）でリセットする。この結果、`NITS Extension Output`composite は:

- **N1-N8**: 受信した瞬間だけ値が流れる瞬時値
- **N9-N16**: 直近に受信した値を保持し続ける連続値（対応関係はN9←N1, N10←N2, ..., N16←N8）

という2系統を同時に提供する。これは`project.json`の"NITS Extension Output"欄の記述「N1-N8 momentary / N9-N16 with memory」と正確に一致する。

---

## 6. TXコマンドフラグ組み立て（main.sw-net グルーロジック）

```
ext_input_interrupt_req = COMPOSITE_READ_BOOLEAN(channel=12)(composite=simpleif_tx_encoder_lua_composite)
tx_interrupt_flag       = OR(ext_input_interrupt_req_out)
ext_input_override_req  = COMPOSITE_READ_BOOLEAN(channel=14)(composite=simpleif_tx_encoder_lua_composite)
tx_override_flag        = OR(ext_input_override_req_out)
simpleif_cmd_ready_read = COMPOSITE_READ_BOOLEAN(channel=13)(composite=simpleif_tx_encoder_lua_composite)
simpleif_push_flag      = OR(simpleif_cmd_ready_read_out)
rx_addr_conflict_read   = COMPOSITE_READ_BOOLEAN(channel=5)(composite=nits_rx_decoder_lua_composite)
```

`simpleif_cmd_ready_read`(channel=13→Lua index14)は`n458.lua`が自ら`output.setBool(14, cmd~=0)`として明示的に設定している値と一致し、これは§4.3で述べた「今tick拡張コマンドを送信したか」を`simpleif_push_flag`としてn440.luaへ伝えるための配線であることが確認できる。

一方`ext_input_interrupt_req`(channel=12→Lua index13)と`ext_input_override_req`(channel=14→Lua index15)は、`n458.lua`のスクリプト本体を見る限り該当インデックスへの明示的な`output.setBool`呼び出しが存在しない。**Luaの出力composite は `output.set***` で上書きしない限り直前tickの出力値を保持し続け（入力compositeからの自動透過は無い）、一度も設定されていないチャンネルの初期値は0/falseである**（作者確認済み）。`n458.lua`はLua index13・15を一度も設定しないため、これらは常に初期値0/falseのまま変化せず、`ext_input_interrupt_req`/`ext_input_override_req`ひいては`tx_interrupt_flag`/`tx_override_flag`は**実質的に常時false固定のデッド配線**である（§7 F8）。

---

## 7. 既知の疑問点・軽微な冗長箇所まとめ

作者(nona-takahara)によるレビューを反映済み。

| ID | 箇所 | 内容 | 状態 |
|---|---|---|---|
| F1 | n458.lua / n848.lua `"M%d/N%d Mode"` | sw-netで宣言されたプロパティ名は`"N%d/N%d Mode"`であり、スクリプトが参照する`"M..."`と不一致。モード選択(3モード)が機能していない | **確定バグ**（作者確認済み。Luaコードの誤り） |
| F2 | n440.lua Luaクラッシュ検知ウォッチドッグ（§2.8） | 当初「XOR(watchdog,NOT(watchdog))は恒真につき常時false固定のデッド回路」と誤解析していたが、ゲート1tick遅延を考慮すると「Luaがエラー停止すると以後のtickで実行されなくなる」性質を利用したクラッシュ検知ウォッチドッグとして機能する | **意図的設計**（作者確認済み。§2.8で解析を訂正済み） |
| F3 | §3.5 `ext_mode_latch`のリセット条件 | 自ID宛の異議申し立てだけでなく、編成中の無関係な他IDの0x47宣言でもラッチがリセットされてしまう | **意図的な保守的動作**（作者確認済み。問題なし） |
| F4 | §3.2 0x46/N32のフィールド幅 | 公式仕様は「前方両数」列をcolspan=4(4bit)と記載するが、実装は`dt & 31`で5bitマスクしている | **仕様として確定**（作者確認済み。NITSが本来対応しない「16両以上の編成」を検知するための意図的な設計とする） |
| F5 | §3.2 後方両数の非伝送 | 公式仕様が0x46の後方両数フィールドを「伝送無し」と明記している点について、当初「`last_car`は常に0になる可能性」とした解析は誤り。実際にはNITS Line Nodeが他車へは後方両数を送出しない一方、**前後両方向から届く前方両数を内部でマージし、本ブリッジには（マージ済みの）後方両数として与える**。公式仕様書はこのNITS Line Node内部の合成処理の記載が欠落している | **仕様書側の記載漏れ**（作者確認済み。コードは正しい） |
| F6 | n458.lua ラウンドロビン保留トリガ | 前方向フラグ(`riseB[i+8]`)の立ち上がりのみでは送信保留が起きない（後方向フラグの立ち上がりのみ判定） | **仕様として確定**（作者確認済み。前後非対称のままでよい） |
| F7 | n440.lua 0x41送信後のクリア | `riseB[1..5]`は0x41フレームの計算には使われておらず(`curB`を直接参照)、クリアのみ行われる | **意図的な冗長処理**（作者確認済み。問題なし） |
| F8 | §6 `ext_input_interrupt_req`/`ext_input_override_req` | LUAノードの出力compositeにおける未設定チャンネルの扱い | **確定**（作者確認済み。Luaの出力は`output.set***`で上書きしない限り**直前tickの出力値を保持し続ける**（inputからの透過は無い）。初期値は0/false。`n458.lua`はLua index13/15に一度も`output.setBool`しないため、これらは初期値0/falseのまま変化せず、**実質デッド配線**である） |

参考: `TOOLTIP_BOOLEAN`（`local_mode_tooltip`, §3.5関連配線には現れないUI専用ノード）は`storm-mcl`の型定義(`definitions.json` type44)で出力ポートが定義されておらず(`"outputs": []`)、`value`入力を表示するのみで下流に一切の信号を渡さないことが確認できる。sw-net上も`local_mode_tooltip`の行に`-> `以降の出力指定が無く、この点と整合する。

---

## 8. 参考

- [NITS（共通コマンド仕様）](https://nonasaba.net/sw-train-docs/communicate/NITS.html)
- [NITS Simple Bridge（Simple IF / Extension チャンネル対応表）](https://nonasaba.net/sw-train-docs/communicate/NITS-Simple-Bridge.html)
- ワークショップ: [NITS Line Node](https://steamcommunity.com/sharedfiles/filedetails/?id=3568542650) / [NITS Simple Bridge](https://steamcommunity.com/sharedfiles/filedetails/?id=3568542738)
