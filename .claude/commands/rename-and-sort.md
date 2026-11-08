---
allowed-tools: Bash(*), Read(*), Edit(*), Write(*)
description: sw-net のノードを改名・並べ替えし、サブサーキットを切り出す。compare-dsl で意味が変わっていないことを確かめる
model: haiku
effort: high
---

`$ARGUMENTS` で指定されたディレクトリの `.sw-net` について、ノードの改名と並べ替え（必要ならサブサーキットの切り出し）を行う。`.sw-net` が無ければ、もっともらしい XML を利用者に尋ね、`pnpm exec storm-mcl xml2dsl <xml> --out-dir <dir>` で変換する。不明なら停止する。

意味が変わっていないことの保証は、`storm-mcl compare-dsl` が行う。`compare-dsl` は、ノードの名前と並び順に左右されず、サブモジュールを展開して結線と属性を比べる。だから改名と並べ替えは、sed でも手書きでも、好きな方法で行ってよい。`compare-dsl` が `equivalent` と言えば合格である。

このスキルの範囲は、基準点を作る、編集する、`compare-dsl` が `equivalent` になる、までである。それ以上の妥当性の確認（`.sw-mcl` の追従、ほかの文書の参照の更新、型検査など）は、必要だと自分が考える範囲で行う。

`storm-mcl` は、リポジトリのルートで `pnpm exec` から実行する。基準点などの作業用のファイルは、一時ディレクトリに置き、リポジトリには作らない。

## 手順

### 1. 基準点を作る

作業の前に、対象のディレクトリ全体（サブモジュールの `.sw-net`、`.sw-mcl`、`project.json` を含む）を、OS の一時ディレクトリへ複製する。作業の後で、この複製と比べる。git の HEAD は基準点にしない（作業ツリーに未コミットの変更があるため）。

```bash
base=$(mktemp -d) && cp -r <dir> "$base/base"
```

対象の `main.sw-net` と、`use` で読み込むサブモジュールの `.sw-net`、`project.json` を Read して、全体を把握する。

### 2. 編集する

`n\d+` などの機械的な名前や、実態に合わない名前を、役割を表す英語の `snake_case` に改める。並べ替えは、信号の流れと機能ブロックを基準にグループ順にし、グループの見出しコメント（`#`）を入れてよい。命名は、利用者に確認しなくてよい。

命名のルール:

- ノードの種類、パラメータ、接続先から機能を推測する。
- `CONST` と `PROPERTY` は、値や label と、接続先の文脈から命名する。
- 同じ役割グループの複数ノードは、末尾に `_1`、`_2` を付ける。
- 既存の名前（ポート名など）との整合性を保つ。
- 改名は、インスタンス名と、そのネット名（`_out`、`_q`、`_value`、`_composite` など）を、そろえて変える。
- `LUA` の `script_ref` を変更するときは、ファイル名も合わせて変える。

変えてはいけないもの（`compare-dsl` が見逃す、または再結線が要る）:

- ポート名（マイコン上の位置は `project.json` 側で決まる。変えるなら再結線が要るので、利用者に伝えてから）
- `PROPERTY_*` の `name` / `n` / `label` / `items`（ゲーム内で利用者に見える）
- `module` の名前（`compare-dsl` が見逃す。`project.json` の参照が切れる）

### 3. compare-dsl で確かめる

```bash
pnpm exec storm-mcl compare-dsl "$base/base/main.sw-net" <dir>/main.sw-net
```

`Network comparison: equivalent` が合格の条件である。サブモジュールの比較（`Module comparisons`）も、すべて `equivalent` でなければならない。`different` なら、差分を読んで直す。

`compare-dsl` が比べないもの: コメント、`module` の名前、`use` のインスタンス名、`.sw-mcl`、`project.json`。これらを確かめるかは、必要に応じて自分で判断する。

## サブサーキットの切り出し

機能のまとまりをサブモジュール（`use`）に切り出してよい。ただし、**切り出す前に、利用者へ尋ねる**（協働が前提）。示す内容は、候補のグループ、含めるノード、入力と出力のポート、切り出す理由である。承認されたものだけを行う。

- 方法は、手書きでも `storm-mcl split-module` でもよい。`split-module` には、スペースを含む composite ポートの境界を跨ぐと `use` がパースできなくなる既知の不具合がある。結果を `compare-dsl` で必ず確かめる。
- 検証は同じである。`compare-dsl` はサブモジュールを展開して比べるので、正しく切り出せていれば、切り出し前と `equivalent` になる。
- 新しいモジュールとポートの名前は、英語の `snake_case` にする。新しい `.sw-mcl` は、`layout-dsl` で位置を計算して生成する。

## 既知の限界

- **同形のノードの取り違え**: 結線が同じで、属性だけが違うノード（例: 未接続の `PROPERTY_DROPDOWN` が 2 つ）は、`compare-dsl` が取り違えて対応づけ、等価なグラフを `different`（属性の食い違い）と判定することがある。基準点との比較（同じファイルの改名）では出にくいが、別の入口（XML の取り込み直しとの比較など）では出る。属性の食い違いだけが差分のときは、取り違えを疑い、属性で対応づけ直す。
- **`layout-dsl` の `added`**: 改名の前から `added` が出るプロジェクトがある（例: `CHUSO2000_Cab_Display_IV`）。`.sw-mcl` を確かめるなら、改名の前後で `added` の数が増えていないことを見る。

## compare-dsl の挙動

- 改名、改名と並べ替えは、`equivalent` と判定される。
- 結線を 1 本変える、定数、`THRESHOLD`、式、`a` と `b` の入れ替え、チャンネル、`PROPERTY` の名前と値、ポート改名、ノード削除、`script_ref` の変更は、すべて `different` と判定される。
- コメント、`module` の名前、`use` のインスタンス名の変更は、検出されず `equivalent` になる。
- `use` と、そのモジュールをインラインに展開した形は、`equivalent` になる。
- 改名は、`xml2dsl --sync-with` の同期の結果に、追加や削除として現れない。
