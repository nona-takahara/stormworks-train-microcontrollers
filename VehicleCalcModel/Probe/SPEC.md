# プローブ コア仕様

`src/probe_core.lua` は Stormworks の API に依存しない純粋なロジックである。
composite の読み書きと HTTP は、これを呼ぶ入口（未着手）が担う。
全体の設計は [../VehicleProbe.md](../VehicleProbe.md)、結線は
[../ProbeWiring.md](../ProbeWiring.md) を参照する。

## 公開関数（グローバル）

| 関数 | 内容 |
|---|---|
| `probe_set(delay, ...)` | 実験（プログラム）を予約する。`delay` tick 後から、区間を順に空白なしで実行する。1 区間は 17 個の数: `len`（最長 tick）, `vend`, `vmin`, モーター `c0 c1 c2 ci ct A f`, ブレーキ `c0 c1 c2 ci ct A f`。区間の間 `u = c0 + c1·v + c2·v² + ci/max(v,vmin) + ct·τ + A·sin(2π f τ)`（τ は区間開始からの秒）を出す。`vend > 0` は \|v\| が達したら、`vend < 0` は \|v\| が -vend 以下になったら次の区間へ進む。出力は ±10^6 で止めるだけで飽和させない。走行中の予約は無視する |
| `probe_cancel()` | 予約中または実行中のプログラムを取り消す。次の tick から出力は 0 |
| `probe_tick(x, y, v, ready)` | 毎 tick 呼ぶ。`モーター, ブレーキ, 状態, 中断理由, t` を返す |
| `probe_ack(v)` | 中断を解除する。停止中（\|v\| < 0.1 m/s）だけ受け付ける |
| `probe_dir(d)` | +モーターで x が増える向きを +1、減る向きを -1 で与える。0 は不明 |
| `probe_jog(motor, brake, len)` | 実験エリア外で IDLE のとき、エリアへ戻る向きにだけモーターを通す |

限界は `SITE_LO` / `SITE_HI`（`src/probe_site.lua`、グローバル）。利用者が測った「継続不能になる直前」の x 座標で、-8480 / 480 である（余裕は含まない）。どちらかが nil の間は実験を始めない。

## 定数と確度

| 定数 | 値 | 確度 |
|---|---|---|
| 速度上限 | 55.56 m/s（200 km/h） | verified（利用者の指定） |
| 自動中断距離 | `max(200, v²/(2·3))` m | 200 m は verified。減速度 3 m/s² は unconfirmed（最初の低速ブレーキ実験で測る） |
| 復帰時の速度上限 | 5 m/s | 仮置き |
| 落下判定 | y が 1 tick で 1 m を超えて下がる → 状態 3（FALLEN、理由 4）。中断とは別の終端状態 | 「y が急に下がれば継続不能」は verified（利用者の説明）。閾値 1 m は inferred |

## 確認テスト（実装前に計画したもの）

`test/run_all.lua` に実装した。分類は次のとおり。

- 式: 定数・\|v\| 比例・反比例・`vmin` による下限・出力範囲の clamp
- 時間窓: 予約から開始、終了後の IDLE 復帰
- 開始拒否: Ready が 0、エリア外、限界が未設定
- 中断: Ready OFF・エリア外・速度超過のそれぞれで、モーター 0・ブレーキ 1。
  中断距離が速度で広がること
- 解除: 動いている間は拒否、停止後に受理
- 復帰: 向き不明で拒否、エリアに近づく側だけ通過（低側・高側）、速度上限で遮断、
  時間切れで 0、エリアに入れば終了

## 無人運転のための保護と設定

- **IDLE の保護:** 実験の外でも、エリア外で \|v\| > 10 m/s、または \|v\| > 55.56 m/s なら中断（状態 2、
  理由 2 / 3）してブレーキを出す。プログラムが速度を持ったまま終わったときや、取り消したとき、
  スクリプトが再読み込みされたときに、無保護で走り続けないため。中断のときは予約済みの
  プログラムも捨てる。
- **向き:** `src/probe_site.lua` の `SITE_DIR`（+モーターで x が増える向き。測定済み）が既定値で、
  `probe_dir` が上書きする。再読み込みのあとでも復帰が使える。
- **不正なコマンド:** 引数が足りない、数でない、旧形式の区間を送っても、スクリプトは落ちない
  （欠けた値は 0 として扱う）。NaN（0/0）は 0 を出す。
- **実行時の設定コマンド:** `5,interval,batch`（記録間隔と 1 リクエストあたりの数）、
  `6,ch1,ch2`（補助チャンネル aux1/aux2 に記録する入力チャンネル）、`8`（取り消し）。
- **記録:** 末尾に `slip,aux1,aux2`。状態 1 の `reason` は実行中の区間番号。

## 状態の意味

- 中断（状態 2、理由 1〜3）: 保護条件が成立して止めた状態。停止後に `probe_ack` で解除でき、
  エリア外なら `probe_jog` で戻せる。実験を続けられる。
- 続行不能（状態 3、理由 4）: 線路から落ちたとみなす状態。何も解除できず、出力はモーター 0・
  ブレーキ 1 のまま固定される。実験者は実験を止め、利用者を呼ぶ。復帰は人が行う。

## 入口とサーバー

- `src/probe.lua`: composite の入出力と HTTP。記録の末尾 `slip` は、入力 ch18〜21（Slip 1〜4）をビット 0〜3 にまとめた整数（0〜15）。ビット 0・1 が一方のボギー（2 軸）、ビット 2・3 がもう一方のボギー（2 軸）に対応する。ボギーごとに 1 台のモーターを持つ。通信の形式は先頭のコメントを正本とする。
  Stormworks の `async.httpGet(port, path)`（path は `/` で始まる）と
  `httpReply(port, request_body, response_body)` を使う。この名前と引数は verified
  （ゲーム内ヘルプの貼り付けによる）。
- `server/probe_server.mjs`: 受け口。記録を `data/log.csv` に追記し、`POST /ctl` で積んだ
  コマンドを次の `/l` の返信で一つずつ渡す。`GET /state` で最終記録と待ち行列を読める。
- Windows の PowerShell から WSL 内のサーバーへ `127.0.0.1` で届くことを確認済み（verified）。
  Stormworks からの到達は、実機の確認待ち。

## 検証

- `lua test/run_all.lua`（コア）、`lua test/entry_smoke.lua`（入口。Stormworks API はモック）、
  `node --test server/probe_server.test.mjs`（サーバー）。
- 配備物は `node.exe tools/microcontroller/cli.mjs build VehicleCalcModel/Probe` で生成する
  （`.env` が Windows のパスのため、WSL の `pnpm` ではなく Windows の Node で動かす）。
  生成物は 2219 文字で、制限の 8192 文字以内である。

## 未着手・未確認

- `.sw-net` の `typecheck` は通る。`export`（XML 生成）はまだ行っていない。
- URL の長さ制限と呼び出し頻度、`localhost` 以外へ出られるかどうかは、実機で確認する（ゲーム内ヘルプには書かれていない）。
- Ready が 0 に落ちた後の復帰が Ready に依存しない前提は unconfirmed のまま。
