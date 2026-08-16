# 外部情報源メモ

> 本文書は参照用の記録であり、現行仕様の正典ではない。現行仕様は各サブプロジェクトの `SPEC.md`・`DESIGN_LOG.md`・実装（`.sw-net`/`.lua`）を参照する。**このリポジトリの現状が常に正であり、本文書に記載する外部情報源との相違は「修正が必要な誤り」ではなく、単なる経緯・背景の記録として扱う。**

## 1. 情報源と優先順位

中宗電鉄（Chuso）は「宗弥急行プロジェクト」という世界観の一部であり、独立した別線区ではない。中宗電鉄の車両は宗弥急行・中宗電鉄ATS、宗弥急行デジタルATCなど、宗弥急行プロジェクト側の保安装置をそのまま使用する。

| 情報源 | 性質 | 優先度 |
|---|---|---|
| **このリポジトリの現状** | 常に正典 | 最優先（不動） |
| `nonasaba.net/sw-train-docs/`（公開サイト） | 宗弥急行プロジェクトの技術資料。作者によれば「なるべく最新追従」 | 高（背景・将来スコープの参照に有効） |
| `wiki.nonasaba.net`（`wiki/sw-train/*`、ローカル限定Wiki.js） | 中宗電鉄の現行・進行中の開発ノート | 高（設計経緯・背景の参照に有効） |
| `/mnt/c/Users/taka/Dropbox/Stormworks`（`inventory.md`/`verify.md`/`survey.md`、2026-08-15付） | Stormworksセーブファイル駆動の旧レガシーツリーの調査 | 低（主に古い情報。provenanceの参考程度。**編集禁止**） |

wiki.nonasaba.netの本文取得は、Wiki.js GraphQL API (`/graphql`) だとグループ権限が反映されず`PageViewForbidden`になることがあった。直接ページURL（`http://wiki.nonasaba.net/ja/<path>`）に認証用の`jwt`をcookieとして付けて取得する方式（`curl -b "jwt=$JWT" http://wiki.nonasaba.net/ja/<path>`）は成功する。

## 2. sys3000生成パイプラインとrepoの対応状況

Dropbox `Chuso_Electric_Railroad/Series2000/sys3000/out.txt`（`generate_lua.py` + `route_data.json` による生成物）は、次の8セクションを持つ。各セクションとこのリポジトリの対応状況（実装の要否は判断せず、現状を記録するのみ）：

| legacyセクション | 内容 | repo対応状況 |
|---|---|---|
| `driver_support_2000.lua` | 行路探索・ARC番号算出 | `CHUSO2000_Driver_Assistance_IV/scripts/n141.lua`・`n61.lua` が対応。データソースは`tools/route-data-sync/`経由でTeinishi氏`route_data.json`（コミットSHA固定）に一本化済み（Dropbox版は参照しない）。詳細は同ディレクトリの`DESIGN_LOG.md`参照 |
| `location_update.lua` | 座標ベースの自列車位置更新 | 未着手 |
| `passenger_guidance_data.lua` | 車内放送・旅客案内の内容データ | 未着手（`SignalComposite.md`にビット名〔旅客案内オン/オフ〕はあるが、内容生成ロジックは無し） |
| `lcd_control.lua` | 車内LCD表示の駅別データ | 未着手 |
| `arc_update.lua` | ARC更新 | `driver_support_2000`に統合済みと解釈 |
| `auto_doorcut.lua` | 駅別の自動戸閉切りゾーン | 未着手（doorcut関連のビット自体は`n141.lua`/`n61.lua`にあるが、駅別ゾーン判定テーブルは無し） |
| `tasc.lua` | 駅ごとの定位置停止座標 | 未着手（TASC関連ビット〔TASC元/TASC有効等〕は`SignalComposite.md`に配線済みだが、停止パターン計算ロジックは無し） |

## 3. 宗弥急行プロジェクトのATS/ATC/ARC資料

`nonasaba.net/sw-train-docs/`には、中宗電鉄の車両が使用する保安装置・運転支援システムの公開資料がある：

- ATS: `protect/Soya-ATS.html`
- ATC: `protect/SK-C-ATC.html`, `protect/Soya-DATC.html`
- ARC（宗弥急行側。中宗2000系の`arc_type_tbl`/`arc_trk_tbl`による行路種別コードとは別の、7桁ダイヤル方式）: `support/Soya-Express-ARC.html`
- NITS: `communicate/NITS.html`, `communicate/NITS-Simple-Bridge.html`
- Momelink: `communicate/Momelink.html`

このリポジトリには現時点でATS/ATC実装が存在しない（`grep`で確認済み、0件）。将来ATS/ATCを扱う際の参照先として記録する。

## 4. CommonControl-old.md調査は不要と判明

Dropbox `CER/Series2000/sys2000-25/CommonControl-old.md`（2000系NITS仕様の旧資料）の28信号一覧を「未検証の仮説」として持ち込む案を検討したが、実地確認の結果、**このリポジトリの`SignalComposite.md`が、wikiの`NITS-C2000/signal-list`および`NITS-C2000/2000-crew-composite`ページと一字一句一致**しており、既に最新の情報源から反映済みであることが判明した（Driving Loop/Settings Loopの全ビット、0x47〜0x60のNITS拡張コマンド全表を突き合わせ確認）。追加作業は不要。

## 5. スコープ外と判断した事項

- **N-TRACS（連動装置）**：`storm-n-tracs-editor`という別リポジトリが正本（Dropbox `build.json`のパス記述から確認）。このリポジトリの対象外。
- **CHUSO3000のビークルデータ・Lua本体**：wiki `NITS-C3000`ページによれば、3000系のビークルデータ・Luaは別作者（Teinishi氏）が別GitHubリポジトリ（`github.com/Teinishi/soya_chuso_train_vehicle`）で管理している。現状JSMS対応仕様のみ。このリポジトリでの新規ディレクトリ作成は対象外（ただし同リポジトリの`route_data.json`は上記2節の通りデータソースとして利用している）。同リポジトリにLICENSEファイルが無いことを記録しておく（同じ制作者コミュニティ内のデータ利用として運用上の問題にはしないが、事実として記録）。
- **CHUSO2500**：repo内に存在せず、Dropbox調査でも独立した設計資料は見つからなかった。
- **Series1000のATC計算式**（`declen`/`getOrpPattern`等、Dropbox `SoyaExpressATCATS/atc_old.lua`・`CER/Series1000/atc.lua`由来）：このリポジトリにATC実装が無いため、移植は時期尚早。`CHUSO1000_SAP_Cab_Controller/SPEC.md`から本節へのポインタのみ置く。
- **wav/mp4/画像アセット、Dropbox内のファイル整理自体**：このリポジトリと無関係。
- **~~`route_data.json`の駅座標データそのものの移植~~**：2026-08-16、`tools/route-data-sync/`として実施済み（Teinishi氏`route_data.json`をコミットSHA固定でフェッチし、`n61.lua`/`n141.lua`向けのdofileモジュールを生成。詳細は`CHUSO2000_Driver_Assistance_IV/DESIGN_LOG.md` #2参照）。

## 6. NITS Emergency Brake Converter（計画段階）

wiki `wiki/sw-train/nits` ページに、NITS車と非NITS車が混在する場合の非常ブレーキ指令の読み替えロジック（前線/後線/非常ブレーキ指令線の使い分け）が構想レベルで記載されている（実装コードなし、計画段階）。`CHUSO1000_SAP_Cab_Controller/SPEC.md`の主題（非常ブレーキ・NITS）に近い将来参照として記録する。
