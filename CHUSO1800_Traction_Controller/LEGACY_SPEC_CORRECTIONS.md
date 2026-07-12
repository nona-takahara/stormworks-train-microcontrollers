# 旧SPECの誤認点・修正記録

> 本文書は履歴資料であり、現行仕様の正典ではない。現行仕様は `SPEC.md`、実装は `CHUSO1800_Traction_Controller_main_renamed.sw-net` と `scripts/n409.lua` を参照する。

## 1. 目的

旧 `SPEC.md` は、当時のsw-net名と不完全なパース結果から意味を推定したため、誤命名を前提とした連鎖的な誤認を含んでいた。本書では、それらを現行仕様から分離して記録する。

## 2. 主要な誤認

| 旧認識・旧名称 | 正しい理解 | 影響 |
|---|---|---|
| 本機は「VVVF風」の牽引制御 | Luaは直流電動機、直列・並列抵抗表、界磁制御をモデル化する | システム概要を全面修正 |
| Phase 1 / Phase 2 | それぞれ直列接続／並列接続 | 状態遷移、進段、転換点の説明を全面修正 |
| `regen_latch`は回生中だけを示す | 並列抵抗制御完了後の界磁制御モード。力行と回生の両方で使用 | Lua B3と状態遷移の意味を修正 |
| 1900形はデータ中継専用、牽引は別ユニット | 1800形・1900形は同じ1800系マイコンを使用し、Propertyで動作を切替 | 車種構成の説明を修正 |
| 1800系にLuaウォッチドッグがある | 1800系にはXOR/NOT型Luaウォッチドッグはない。これは2000系列参考資料との混同 | 故障監視節を修正 |
| `startup_delay`はLuaウォッチドッグタイマ | enable未接続の未消費CAPACITOR | デッド／保留ロジックへ移動 |
| `speed_raw`は速度 | Lua N7の空気ブレーキ補完減速度要求 | BC Target系の説明を修正 |
| `speed_display`は表示速度 | N7を`x*3.6+1`でBC絶対圧目標へ変換 | Momelink N25、BC Target出力を修正 |
| `bc_target_raw`はBC目標 | Lua N3の車両加速度 | Momelink N2/N26の説明を修正 |
| `bc_target_smooth`はBC目標平滑 | 車両加速度の一次平滑 | Momelink加速度情報として修正 |
| `brake_current_fb`はブレーキ電流 | Lua N6の補助界磁電流・界磁制御量 | 300/400 A閾値の意味を修正 |
| `current_src_mux`は電流源切替 | Lua結果コンポジット全体と、N7のみを持つ空気ブレーキフォールバックの切替 | 牽引禁止時の全出力挙動を修正 |
| `eb_condition`は非常制動そのもの | Controller Stop、故障、中立、過速度、低BPをまとめた牽引禁止条件 | 名称と状態収束説明を修正 |
| Simple IF B18は非常制動 | B18はDB自動。非常制動はB1 | 回生自動許可とECB非常制動を分離 |
| `DANRYU`は電流ゼロだけを示す | 電機子電流が正でない状態。回生負電流も含む | 外部出力仕様を修正 |
| 回生保護は低速失効・界磁電流高止まりだけ | 設計意図は架線電圧上昇時の回生遮断・再投入抑制。界磁電流を代理量として検出 | 保護目的を修正 |
| `Brake Limit@320kPa`は現在の界磁電流閾値に使われる | ブレーキ時限流値スケーリング用に用意されたPropertyだが現状未消費 | 未消費項目へ移動 |
| `cam`はカム1周完了パルス | DELTAのゼロ判定をNOTしているため、カム位置が変化したtickのパルス | 外部出力仕様を修正 |
| カム始動・界磁移行条件は位置0～1 | 実機THRESHOLDは0～0で、位置0だけ | 状態遷移を修正 |
| `catenary_active_thresh`は0～1 V判定 | 実機設定は0 V一致判定 | 架線入力フォールバック条件を修正 |
| `direction_nonzero`は0～1判定 | 実機設定は方向値0の中立判定 | 前進時に牽引禁止になるという誤診を撤回 |

## 3. THRESHOLDパース不具合

元のsw-net出力処理は、一部の`max=0`を`max=1`として出力していた。確認済みの対象は次の6ノード。

| 旧名 | 現行名 | 実値 |
|---|---|---|
| `catenary_active_thresh` | `catenary_input_zero` | 0～0 |
| `position_changing` | `cam_position_unchanged` | 0～0 |
| `notch_active` | `power_notch_zero` | 0～0 |
| `notch_fb_ge1` | `cam_at_zero` | 0～0 |
| `regen_available` | `field_control_cam_ready` | 0～0 |
| `direction_nonzero` | `direction_neutral` | 0～0 |

この不具合により、旧仕様ではカム0～1、架線0～1 V、前進を含む方向判定など、実在しない範囲条件を推定していた。

## 4. 旧ティックモデルの扱い

旧仕様は「すべてのゲート出力が一律に1 tick遅延する」と仮定していた。この仮定は本マイコン固有資料から確認されておらず、状態遷移の競合分析を過度に複雑化した。

現行仕様では、SRラッチ、CAPACITOR、Lua、自己帰還など状態を持つ要素だけを明示し、組合せゲートの一律遅延を前提にしない。tick単位の厳密な競合解析が必要な場合は、Stormworks実機または変換前XMLで評価順序を確認する。

## 5. 旧異常ステート分析の扱い

次の旧結論は、誤ったTHRESHOLD値または誤命名に依存するため破棄する。

- カム0～1をホーム位置とする説明。
- カム周回時だけ`cam`が発火する説明。
- 前進選択で牽引禁止になるというH1分析。
- Phase 1/Phase 2の準安定共存を、名称だけから異常と断定した分析。
- `power_cut_latch`をLuaウォッチドッグまたは通常の過電流保護とみなした説明。
- 1900形モードを「中継専用」とみなした説明。

直並列ラッチの同時成立可能性や遷移中の挙動を今後検証する場合は、現行名称、実値0判定、Luaの`SR`/`PR`テーブルを前提に改めて評価する。

## 6. 再命名の方針

再命名版sw-netでは、次の原則を採用した。

- `notch`を、運転指令の力行ノッチとカム位置フィードバックに分離。
- `phase1/phase2`を`series/parallel`へ変更。
- `regen`を、界磁制御、回生減速度指令、DB自動、過電圧保護、空気ブレーキ補完へ分離。
- `brake_current`を`field_current`へ変更。
- `bc_target_raw`を`model_acceleration`へ変更。
- `speed_raw`を`pneumatic_brake_decel_demand`へ変更。
- `eb_condition`を`traction_inhibit`へ変更。
- Momelinkの抽象チャンネル名を、既知の電圧・電流・加速度・BC目標名へ変更。

## 7. 残る確認事項

- `Momelink-A` N22の35は車両質量[t]と推定されるが、プロトコル正典での確認が望ましい。
- Physics Sensor N9の入力結線欠落がsw-net生成側の問題か、元データ側の問題かを確認する。
- `scripts/n409.lua`の実ファイル名と配置をリポジトリ上で確認する。
- `unused_startup_delay`、`power_notch_ge4`、`cam_nonzero_epsilon`、Lua B6は削除せず、将来の利用意図を確認する。
