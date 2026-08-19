# 設計変更の経緯（意思決定ログ）

本文書は、`CHUSO2000_Driver_Assistance_IV`の設計判断の経緯（なぜそうなったか）を記録する。現在の姿（信号・チャンネル仕様）は`SPEC.md`を参照。エントリは追記のみで、既存エントリの番号・内容は変更しない。

## #1 `n141.lua`/`n61.lua`のARC算出ロジックの出自と、著者の将来設計メモ（v4）について

**背景**：`lua_drive_support_out (n141.lua)`が持つ`arc_type_tbl`/`arc_trk_tbl`/`link_tbl`（行路種別・目的地から行路探索・ARC番号を算出するテーブルとロジック）の出自を、外部資料（`wiki.nonasaba.net`、著者本人が管理する中宗電鉄の開発ノート）と突き合わせて確認した。

**確認した事実**：

- `wiki/sw-train/NITS-C2000/2000-driver-support`ページの「v3開発方針」に掲載されたLuaコードは、`link_tbl`/`find_rte`/`arc_type_tbl`/`arc_trk_tbl`を含め、`n141.lua`と同じ構造・同じアルゴリズムを持つ。この設計（GPS+タコメータのハイブリッド地点認識、ARCから種別行先指令を生成する方式）が、現行`n141.lua`/`n61.lua`のもとになっている設計メモである。
- 同じwikiページには「v3」の下に、より新しい「v4開発方針」という設計メモがある（本稿執筆時点でコードは未実装、方針のみ）。そこには次の記述がある：
  > 1000系列はARC指令かつ次駅案内なし。2000系列はタッチパネル指令かつ次駅案内あり。相互に互換性なし（なお、7000系も2000系列のタッチパネル指令を採用予定）
  
  これは、ARCコードによる種別行先指令という現行`n141.lua`の方式が、著者の設計ノート上では2000系ではなく1000系列側の方式として位置づけ直される可能性がある、という将来的な設計方向性を示すものである。あわせて、指令スワップの廃止（指令A・Cのみ使用）も v4 のメモに含まれる。

**影響箇所**：この記録は`n141.lua`/`n61.lua`の現行実装を変更するものではない。`SPEC.md`の`lua_drive_support_out (n141.lua)`節に本エントリへの参照ポインタを追加した。

**備考**：上記のwiki記載事項は著者自身の設計ノートであり、このリポジトリの現行実装を検証・修正する目的の情報ではない。`n141.lua`のテーブル内容自体は、wikiのv3コードや他の関連資料（`EXTERNAL_SOURCE_NOTES.md`参照）と細部が完全一致するとは限らないが、その相違の当否についてはここでは扱わない。

## #2 route_data.json生成パイプラインの導入（Teinishi氏リポジトリ準拠、`src/`・`deploy/`分離）

**当初案**：`n61.lua`/`n141.lua`にハードコードされている`link_tbl`/`stop_type_tbl`/`coord_tbl`/`meterage`/`not4srv`/`doorcut_tbl`/`arc_type_tbl`/`arc_trk_tbl`（#1参照）を、Dropbox内`sys3000/route_data.json`＋`generate_lua.py`から手作業で移植・更新していた。

**現在の設計**：`tools/route-data-sync/`を新設し、GitHub `Teinishi/soya_chuso_train_vehicle`の`route_data.json`（3000系を開発する別作者が管理、ユーザー自身も更新を担当）を単一の情報源として、Node.jsで自動生成するパイプラインに置き換えた。

- `fetch.mjs`：`route_data.json`をコミットSHA固定で取得し、`tools/route-data-sync/vendor/route_data.snapshot.json`＋`route_data.snapshot.meta.json`（出典URL・SHA・取得日時）として保存する。
- `generate.mjs`：スナップショットから、`n141.lua`向け`src/route_data_arc.lua`（`link_tbl`/`arc_type_tbl`/`arc_trk_tbl`）と、`n61.lua`向け`src/route_data_position.lua`（`link_tbl`/`stop_type_tbl`/`coord_tbl`/`meterage`/`not4srv`/`doorcut_tbl`）の2モジュールを生成する。`local`宣言なし・`return`なしのグローバル代入のみとし、storm-lua-minify式`dofile(...)`で取り込める形式にした（`lib/state_sync.lua`と同じ流儀）。
- `link_tbl`は両モジュールに重複して持たせている。1モジュールに全8テーブルを詰めると、`dofile`展開時に各ノードが使わないテーブルまで抱え込み、文字数を無駄に消費するため（CHUSO1800の`DESIGN_LOG.md` #14「8192文字を一時的に再超過」と同種の問題）。

**きっかけ**：ユーザーからの指示「Dropbox管理だったこのツールを、Dropboxの個人管理データではなくTeinishi氏の`route_data.json`を単一の情報源としてビルドパイプラインへ正式に組み込みたい」。また「`generate.mjs`の出力はstorm-lua-minify式`dofile`で取り込み可能な形式にしてほしい」との追加指示を受けた。

**`src/`・`deploy/`分離を導入した理由**：`scripts/n61.lua`・`scripts/n141.lua`は`reimport.sh`（`pnpm exec storm-mcl xml2dsl ... --out-dir CHUSO2000_Driver_Assistance_IV`）が書き込む対象そのものであることを`git log --follow`で確認した（コミットは一括インポート1回のみ、以後の手編集なし）。minifyビルドの出力を`scripts/`に直接書くと、`reimport.sh`と書き込み先が競合し、どちらを後に実行したかでビルド結果かゲーム側の変更のどちらかがサイレントに消える。そのため、手書きロジックは`src/n61.lua`・`src/n141.lua`（`dofile("route_data_position")`・`dofile("route_data_arc")`を使用）に置き、`deploy/build.js`（CHUSO1800の`deploy/build.js`に準拠）でstorm-lua-minifyを実行し、`deploy/n61_deploy.lua`・`deploy/n141_deploy.lua`へ出力する構成にした。

その後、個別の`deploy/build.js`とXML再取り込みスクリプトはリポジトリ共通の
`microcontroller` CLIへ統合した。生成物は引き続き`deploy/`へ置き、Stormworksへ
書き出す際だけ一時DSLツリーのsidecarへ差し込むため、二つの書き手を作らない。

**`scripts/n61.lua`・`scripts/n141.lua`は今回変更していない。** `deploy/`の生成結果とのdiffはtrack 2（掘戸町）の座標のみで、他の全テーブル値は一致していた（`coord_tbl`が`{303,-4819}`→`{158,-4590}`。Teinishi氏側でこの駅の座標が更新されたもので、追従して問題ないとユーザーに確認済み）。`scripts/`への反映は、この記録とは別の明示的な作業として行う。

**影響箇所**：`tools/route-data-sync/`（新規）、`CHUSO2000_Driver_Assistance_IV/src/`（新規）、`CHUSO2000_Driver_Assistance_IV/deploy/`（新規）、`package.json`（`scripts`ブロック新設）、`EXTERNAL_SOURCE_NOTES.md`（§2・§5更新）。
