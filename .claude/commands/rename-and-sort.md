---
allowed-tools: Bash(*), Read(*), Edit(*), Write(*)
description: sw-net ファイルの n\d+ ノードを命名・sed 置換・ソート・検証する
model: haiku
effort: high
---

`$ARGUMENTS` ディレクトリに.sw-netがあれば、sw-net ファイルの n\d+ ノードを命名・sed 置換・ソート・検証する一連の作業を開始。ない場合はもっともらしいxmlを尋ね、`pnpm exec storm-mcl xml2dsl`に、指定されたディレクトリ名を与えて変換する。不明なら停止する。

## Phase 1: 準備

対象ディレクトリの `main.sw-net` と `project.json` を Read して全体を把握する。

## Phase 2: 命名と sed スクリプト生成

`main.sw-net` 内のすべての `n\d+` ノードに英語の説明的な識別子を自律的に付ける。

**命名ルール:**
- ノードの種類 (inst type)・パラメータ・接続先から機能を推測する
- CONST/PROPERTY ノードは値や label と接続先の文脈から命名する
- snake_case を使う
- 既存の命名済みノード（ポート名など）との整合性を保つ
- 同じ役割グループに属する複数ノードは末尾に `_1`, `_2` など連番を付ける

命名が決まったら `rename.sed` を生成する:
- **長い識別子から先に並べる**（部分マッチ防止）
- 識別子の境界マッチに `-E` の `\b` を使用
- `n\d+_out`, `n\d+_q`, `n\d+_not_q`, `n\d+_value`, `n\d+_composite` など suffix ごとに行を作る
- フォーマット例: `s/\bn9_value\b/catenary_voltage_ref_value/g`

## Phase 3: sed 適用

```bash
sed -E -f rename.sed main.sw-net > main.sw-net.renamed
grep -oP '\bn\d+\b' main.sw-net.renamed
```

未置換の `n\d+` が残っていれば `rename.sed` を修正して再適用する。
問題なければ `mv main.sw-net.renamed main.sw-net` で上書きし、`pnpm exec storm-mcl typecheck-dsl project.json` を通す。
エラーがあれば原因を調査して修正する。

## Phase 4: バックアップとソート

1. `cp main.sw-net main.sw-net.pre-sort` でバックアップを作成する。
2. inst 行を信号の流れと機能ブロックを基準にロジカルグループ順で並べ替える:
   - **inst 行の内容は一切変更しない**（移動のみ）
   - コメント行（`#` で始まる行）はグループ見出しとして挿入してよい
3. 並べ替えた内容で `main.sw-net` を上書きする。

## Phase 5: 検証と最終チェック

1. `<repo-root>/verify_sort.sh main.sw-net.pre-sort main.sw-net` を実行する。
   MISSING が出た場合は必ず修正してから進む。
2. `pnpm exec storm-mcl typecheck-dsl project.json` で最終タイプチェックを通す。
3. 問題なければ完了を報告する。`main.sw-net.pre-sort` は残しておく（ユーザーが削除する）。
