# CHUSO2000_Door_Min — 仕様書

## 機能概要

ドア制御の最小マイコン。2つの物理センサ間距離を測定してドアの開閉エリア判定を行い、
NITSネットワーク経由でドア開扉指令を受け付け、ドアモーターへ速度信号を出力する。
開閉時のチャイム（High/Low 2系統）も生成する。

## ポート

| ポート | 方向 | 型 | 説明 |
|-------|------|----|------|
| Phys. Input | in | composite | センサA用 物理位置 (ch1=X, ch2=Y, ch3=Z) |
| Phys. Input | in | composite | センサB用 物理位置 (ch1=X, ch2=Y, ch3=Z) |
| Door is Open | out | boolean | ドア開状態フラグ |
| Chime Low | out | boolean | チャイム低音信号 |
| Chime High | out | boolean | チャイム高音信号 |
| Other Inputs | in | composite | ch10: NITS外部コンポジット切り替えフラグ |
| NITS Ext. Input | in | composite | NITS外部入力 (COMPOSITE_SWITCHBOX の b 側) |
| Input | out | number | ドアモーター速度 (正=開、負=閉、0=停止) |

## 命名規則

snake_case を使用。接頭辞・接尾辞の慣習は以下のとおり。

| パターン | 意味 |
|---------|------|
| `sensor_a_*` / `sensor_b_*` | Phys. Input の2センサ読み取り値 |
| `*_sq` | 二乗値ネット |
| `*_thresh` | 閾値ネット |
| `door_open` | SRラッチ Q 出力（ドア開状態ビット） |
| `door_change` | ドア状態変化パルス |
| `door_moving` | ドア動作中フラグ（CAPACITORで生成） |
| `chime_tick` | チャイムカウンタ出力 |
| `chime_high_*` / `chime_low_*` | チャイム高音/低音の各タイミング |
| `prop_*` | PROPERTYノード |
| `const_*` | CONSTノード |

## 論理グループ

1. **物理センサ読み取り** — `sensor_a_ch1-3`, `sensor_b_ch1-3`
2. **ドア開閉エリア判定** — 距離二乗計算 → GREATER_THAN / LESS_THAN → NAND で`in_door_zone_out`
3. **ドア開扉判定** — NITS信号 → SRラッチ `door_open_latch` → `door_open`、`in_door_zone_out` とOR → `Door is Open`
4. **チャイムタイマー** — ドア変化でリセットするCOUNTER、0〜120tick計測
5. **チャイム出力** — THRESHOLD × 4 → OR 2系統 (High/Low)
6. **ドアモーター速度出力** — 方向スイッチ × 速度スイッチ → MULTIPLY → `Input`

## チャイムタイミング

カウンタ tick は `door_change_pulse`（ドア変化）でリセットされる。
モードは `COUNTER m=1` でカウントアップのみ（`const_false` で up 入力を常時 false にしてタイムベース駆動）。

| 信号 | min tick | max tick | タイミング |
|------|---------|---------|----------|
| Chime High (開扉) | 1 | 79 | 開扉後すぐ |
| Chime Low (開扉) | 21 | 99 | 開扉後少し遅れ |
| Chime High (閉扉) | 81 | 120 | 閉扉後すぐ |
| Chime Low (閉扉) | 101 | 120 | 閉扉後少し遅れ |

## ドアモーター速度

- 通常速度: `0.4`（`door_moving` が false = ドア停止後）
- チャイム中速度: `0.2`（`door_moving` が true = ドア動作中）
- 方向: 開扉 `+1`、閉扉 `-1`
- `door_moving` は CAPACITOR (charge=0, discharge=1) で `door_change` パルスから生成
