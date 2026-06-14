# CHUSO2000 Driver Assistance IV — SPEC

## 機能概要

運転支援マイコン。物理入力・Monitor Status を受け取り、駅停車情報・締切案内・タッチ UI を制御して `Drive Support` コンポジットと映像出力を生成する。

### 主な機能ブロック

| ブロック | Lua | 役割 |
|---------|-----|------|
| 運転支援ロジック | `scripts/n61.lua` | GPS+距離程から次駅・接近判定・扉締切テーブル |
| Monitor Status 解析 | `scripts/n130.lua` | Monitor StatusのN/Bチャンネルを行路・ARC・停車情報へデコード |
| タッチ UI | `scripts/n105.lua` | タッチ座標判定、ページ切替、メモリレジスタ操作 |
| 表示データ生成 | `scripts/n106.lua` | 現在ページに応じた描画コマンド列を生成（ツール生成） |
| 描画 BG/FG/出力 | `scripts/n107.lua`, `n115.lua`, `n127.lua` | 映像レイヤー合成・最終出力（ツール生成） |
| Drive Support 出力 | `scripts/n141.lua` | メモリレジスタ・ページ・ds_num・締切フラグをパックして送出 |

## 命名規則

snake_case を基本とし、以下のプレフィックスで機能グループを示す。

| プレフィックス | 意味 |
|--------------|------|
| `phys_` | Physics Input から読み取った物理量 |
| `mon_` | Monitor Status から読み取った状態値 |
| `ds_` | Drive Support Lua (n61) の入出力信号 |
| `ui_` | タッチ UI Lua (n105) の出力・内部レジスタ |
| `lua_` | Lua インスタンス名およびその composite/video ネット |
| `draw_` | 描画系 video ネット |
| `spd_` | 速度補正関連 |
| `approach_` / `arrival_` | 接近・停車ラッチ信号 |
| `door_` | 扉状態信号 |
| `const_` | 定数 |

## インスタンス → ネット名 マッピング（主要）

| インスタンス名 | 旧番号 | 役割 |
|--------------|--------|------|
| `lua_drive_support` | n61 | 運転支援ロジック |
| `lua_monitor_decode` | n130 | Monitor Status 解析 |
| `lua_touch_ui` | n105 | タッチ UI |
| `lua_display_gen` | n106 | 表示データ生成 |
| `lua_draw_bg` | n107 | BG 描画 |
| `lua_draw_fg` | n115 | FG 描画 |
| `lua_draw_out` | n127 | 最終映像出力 |
| `lua_drive_support_out` | n141 | Drive Support 出力 |
| `notch_calc` | n55 | ノッチ換算 (速度×補正+加速度) |
| `approach_latch` | n67 | 接近フラグ SR ラッチ |
| `arrival_latch` | n98 | 停車ランプ SR ラッチ |
| `ui_display_pack` | n114 | 表示データ → UI Lua へのパック |
| `ds_out_pack` | n177 | Drive Support 出力パック |
| `ds_out_bool_pack` | n196 | Drive Support ブール出力パック |
| `physics_pack` | n50 | 物理量 → Drive Support Lua へのパック |

## ポート

| ポート | 型 | 方向 | 内容 |
|-------|----|------|------|
| Monitor Status | composite | in | Cab Controller から各種状態値 |
| Physics Input | composite | in | GPS・加速度など物理センサ |
| Drive Support Monitor Touch | composite | in | タッチスクリーン座標 |
| Drive Support | composite | out | 運転情報まとめ (SignalComposite Drive Support 定義準拠) |
| Output | video | out | 運転支援ディスプレイ映像 |
| Monitor Beep | boolean | out | タッチ時ビープ信号 |

---

## Lua スクリプト詳細

### lua_drive_support (n61.lua) — 運転支援ロジック

GPS 座標・距離程・行路コードから次駅・接近判定・締切テーブルを計算する。

**路線データ（ハードコード）**

- 駅数: 13 駅（coord_tbl の有効エントリ）
- 座標テーブル (`coord_tbl`): 各駅の GPS X/Y 座標
- 距離程テーブル (`meterage`): 各駅の kp [m]（最大 9220 m）
- 経路グラフ (`link_tbl`): 上下線別の隣接リスト（BFS ルート探索）
- 停車種別テーブル (`stop_type_tbl`): 種別ごとに停車する駅リスト
- 締切テーブル (`doorcut_tbl`): 特定駅（6/10番）でドアカット適用

**入力**

| ch | 内容 |
|----|------|
| N1 | GPS X |
| N2 | GPS Y |
| N3 | 距離程 kp [m] |
| N4 | code A（行路コード、Memreg2[N3]相当） |
| B1 | Enable（運転支援有効） |
| B2 | start_ctrl（出発確認） |
| B3 | isap（接近中かつ出発前） |
| B4 | door open |
| B5 | dop_start（戸開出発確認） |

**code A ビット構成**: `(ttype<<12) | (frm<<6) | dest`（各 6 bit）

**出力**

| ch | 内容 |
|----|------|
| N1 | 次駅 SID（mode 1/3 時: 次停車駅） |
| N2 | 次次駅 SID（mode 1/3 時: 次次停車駅） |
| N3 | mode（0=off, 1=停車中扉開, 2=走行中, 3=接近中） |
| N4 | 方向（dir3000: 1=上り, 2=下り） |
| N9 | kp（デバッグ用） |
| N31/N32 | 距離程更新フラグ/値（upkp=true 時のみ） |
| B1 | en（Enable パススルー） |
| B2 | start_ctrl パススルー |
| B3 | doorcut（停車駅でドアカット適用） |
| B4 | set_ap（接近フラグセット: 次停車駅まで 400–520 m） |
| B5 | reset_ap（接近フラグリセット: 520 m 超） |

---

### lua_monitor_decode (n130.lua) — Monitor Status 解析 / 操作エンコーダ

タッチ UI からの操作指示と、運転支援からのステータスを FIFO キューにパックして出力する。

**入力（運転支援から）**

| ch | 内容 |
|----|------|
| N11 | 次駅 SID (id1) |
| N12 | 次次駅 SID (id2) |
| N13 | mode |
| N14 | dir |
| B11 | Enable |
| B12 | start_ctrl |
| B13 | doorcut |
| B14 | forward（前方向） |

**入力（タッチ UI から）**

| ch | 内容 |
|----|------|
| N1 | operation.type |
| N2 | operation.departure 駅番号 |
| N3 | operation.destination 駅番号 |
| N4 | idp.type（点呼行路） |
| N5 | idp.to_go |
| N6 | menu ID |
| N8 | opid（操作ID） |
| B3 | up_arc（ARC 更新トリガ） |
| B5 | idp_up_arc |
| B6 | up_menu |
| B10 | up_opid |

**出力パックフォーマット（N1, float←→int 変換済み）**

| type bits [22:20] | 内容 |
|-------------------|------|
| 0b101 (5) | 運転支援ステータス: `5<<20 | (dir&3)<<14 | (mode&3)<<12 | (id1&63)<<6 | (id2&63)` |
| 0b001 (1) | ARC: `arc | (1<<20)` |
| 0b010 (2) | 行路コード: `arc_teinishi | (2<<20)` |
| 0b100 (4) | 点呼行路: `idp_arc_teinishi | (4<<20)` |
| 0b110 (6) | メニュー: `menu | (6<<20)` |
| 0 | 操作ID: `opid`（型ビット 0） |

センチネル: `1<<24`（キュー空時）

**ARC 計算**

`arc_type_tbl` と `arc_trk_tbl` で行路種別・目的地から ARC 番号を算出:
- 上り: +10000, 下り: +20000
- 行路種別: min 値または固定値
- 目的地: 到着ホームによる追加値

**出力**

| ch | 内容 |
|----|------|
| N1 | packed value（1 件/tick、センチネル = 1<<24） |
| N2 | キュー残件数 |
| B2 | Doorcut A（NOT forward AND doorcut） |
| B3 | Doorcut B（forward AND doorcut） |
| B4 | 接近中（mode == 3） |

---

### lua_touch_ui (n105.lua) — タッチ UI ハンドラ

2 点タッチ入力を受け取り、現在ページに応じたコマンドを出力する。
入力 N32 がカレントページ ID。ページ構造:

| ページ ID | 内容 |
|-----------|------|
| 0 | メインメニュー |
| 100 | （確認ページ） |
| 200/201 | 種別1 停車操作 |
| 300–303 | 種別2 停車（4ページ） |
| 400–403 | 種別3 停車（4ページ） |
| 1000/1001 | 種別4 停車 |
| 1100–1103 | 種別5 停車（4ページ） |
| 2000/2001 | 種別6 停車 |
| 3000 | 特殊ページ |
| 3100–3103 | 種別7 停車（4ページ） |
| 4000 | デバッグ |

---

### lua_drive_support_out (n141.lua) — Drive Support 出力 FIFO

入力 N1/N2（2値/tick）を内部キューに積み、1値/tick で出力する。センチネル `1<<24` が来た値はキューに積まない。キューが空の時もセンチネルを出力。

---

### lua_draw_out (n127.lua) — 映像最終出力（デバッグ付き）

通常はビデオを合成して出力するだけ。ページ ID が 4000（デバッグ）の場合に限り、N7 と N17 の 4桁数値を画面に重ね書きする（座標 N7 を `I1`、N17 を `I2` として表示）。
