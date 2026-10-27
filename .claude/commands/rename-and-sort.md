---
allowed-tools: Bash(*), Read(*), Edit(*), Write(*)
description: sw-net のノードを改名・並べ替えし、サブサーキットを切り出す。compare-dsl で意味が変わっていないことを確かめる
model: haiku
effort: high
---

`$ARGUMENTS` で指定されたディレクトリの `.sw-net` について、ノードの改名と並べ替え（必要ならサブサーキットの切り出し）を行う。`.sw-net` が無ければ、もっともらしい XML を利用者に尋ね、`pnpm exec storm-mcl xml2dsl <xml> --out-dir <dir>` で変換する。不明なら停止する。

意味が変わっていないことの保証は、`storm-mcl compare-dsl` が行う。`compare-dsl` は、ノードの名前と並び順に左右されず、サブモジュールを展開して結線と属性を比べる。だから改名と並べ替えは、sed でも手書きでも、好きな方法で行ってよい。`compare-dsl` が `equivalent` と言えば合格である。

バックアップのファイル（`.pre-sort` など）と、行の保存を調べる別のスクリプトは使わない。`storm-mcl` は、リポジトリのルートで `pnpm exec` から実行する。

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

変えてはいけないもの（`compare-dsl` が見逃す、または再結線が要る）:

- ポート名（マイコン上の位置は `project.json` 側で決まる。変えるなら再結線が要るので、利用者に伝えてから）
- `PROPERTY_*` の `name` / `n` / `label` / `items`（ゲーム内で利用者に見える）
- `module` の名前（`compare-dsl` が見逃す。`project.json` の参照が切れる）
- `LUA` の `script_ref`

### 3. 改名表を書く

変えたインスタンスの名前を、`旧 → 新` の表にまとめる。`use` のインスタンス名（`compare-dsl` が見逃す）と、サブモジュール内の改名も含める。

### 4. compare-dsl で確かめる

```bash
pnpm exec storm-mcl compare-dsl "$base/base/main.sw-net" <dir>/main.sw-net
```

`Network comparison: equivalent` が合格の条件である。サブモジュールの比較（`Module comparisons`）も、すべて `equivalent` でなければならない。`different` なら、差分を読んで直す。

`compare-dsl` が比べないもの（別に確かめる）: コメント、`module` の名前、`use` のインスタンス名、`.sw-mcl`、`project.json`。

### 5. 改名表を突き合わせる

`--json` を付けて実行し、`matchedPairs` のうち `a.node.id` と `b.node.id` が違う組を取り出す。すべてが手順 3 の改名表にあることを確かめる。

```bash
pnpm exec storm-mcl compare-dsl "$base/base/main.sw-net" <dir>/main.sw-net --json
```

同じ形のノード（同じ値の `CONST` など）は、グラフの対応づけで取り違えられることがある。取り違えは `equivalent` のままだが、対応表が誤る。食い違ったら、停止して調べる。改名表は、自分で書いた表を正とする。

### 6. `.sw-mcl` を追従させる

各 `.sw-mcl` の `instances[].id` に、改名表を適用する（`"id": "旧"` を `"id": "新"` に。JSON の書式は保つ）。確認は次のとおり。

```bash
pnpm exec storm-mcl layout-dsl <dir>/project.json --dry-run
```

どのファイルも `0 added` でなければならない。`added` が出ていれば、改名表の適用漏れである。

ただし、改名の前から `added` が出るプロジェクトがある（例: `CHUSO2000_Cab_Display_IV` は、改名前でも `73 added`）。その場合は、改名の前後で `added` の数が増えていないことを確かめる。あわせて、各 `.sw-mcl` の `instances[].id` が、すべて対応する `.sw-net` のインスタンス名（`inst` と `use`）にあること（改名前の名前が残っていないこと）を確かめる。

### 7. 参照を更新する

改名前の名前が、リポジトリのほかの場所に出ていないかを探す。

```bash
grep -rnw -e <旧名1> -e <旧名2> --include='*.md' --include='*.lua' --include='*.sw-net' .
```

- 現在の状態を書く文書（`SPEC.md`、`README.md`、`SIGNAL_MAP.md`、`SYSTEM_SPEC.md`、`SignalComposite.md` など）と、コードのコメントは、新しい名前に直す。
- 履歴の文書（`DESIGN_LOG.md`、`LEGACY_SPEC_CORRECTIONS.md`、`analysis/RESULTS*`、`*_PLAN`）は、直さない。該当の箇所を、報告に書く。

### 8. 仕上げる

- `pnpm exec storm-mcl typecheck-dsl <dir>/project.json` を通す。
- 初回の命名なら、`grep -P '\bn\d+\b' <dir>/*.sw-net` で、未改名の `n\d+` が残っていないことを確かめる。
- 一時ディレクトリを削除する。`.pre-sort` や `.renamed` などの残骸ファイルを、リポジトリに作らない。

### 9. 報告する

次を報告する: 改名した数、`compare-dsl` の結果、`layout-dsl --dry-run` の結果、更新した文書、履歴の文書の該当箇所。コミットはしない（依頼があったときだけ行う）。

## サブサーキットの切り出し

機能のまとまりをサブモジュール（`use`）に切り出してよい。ただし、**切り出す前に、利用者へ尋ねる**（協働が前提）。示す内容は、候補のグループ、含めるノード、入力と出力のポート、切り出す理由である。承認されたものだけを行う。

- 方法は、手書きでも `storm-mcl split-module` でもよい。`split-module` には、スペースを含む composite ポートの境界を跨ぐと `use` がパースできなくなる既知の不具合がある。結果を `compare-dsl` で必ず確かめる。
- 検証は同じである。`compare-dsl` はサブモジュールを展開して比べるので、正しく切り出せていれば、切り出し前と `equivalent` になる（実験で確認済み）。
- 新しいモジュールとポートの名前は、英語の `snake_case` にする。新しい `.sw-mcl` は、`layout-dsl` で位置を計算して生成する。配置が変わることを、報告に書く。

## 既知の限界

- **同形のノードの取り違え**: 結線が同じで、属性だけが違うノード（例: 未接続の `PROPERTY_DROPDOWN` が 2 つ、`CHUSO2000_Signal_Gateway` の `side_doors_property` と `double_decker_property`）は、`compare-dsl` が取り違えて対応づけ、等価なグラフを `different`（属性の食い違い）と判定することがある。基準点との比較（同じファイルの改名）では出にくいが、別の入口（XML の取り込み直しとの比較など）では出る。属性の食い違いだけが差分のときは、取り違えを疑い、属性で対応づけ直す。
- **`layout-dsl` の `added`**: 改名の前から `added` が出るプロジェクトがある。手順 6 の確認を参照する。

## 実験で確認した事実（2026-10-21）

- 改名、改名と並べ替え: `equivalent`。結線を 1 本変える、定数、`THRESHOLD`、式、`a` と `b` の入れ替え、チャンネル、`PROPERTY` の名前と値、ポート改名、ノード削除、`script_ref` の変更: すべて `different`。
- コメント、`module` の名前、`use` のインスタンス名の変更: `equivalent`（検出されない）。
- `use` と、そのモジュールをインラインに展開した形: `equivalent`。
- 改名は、`xml2dsl --sync-with` の同期の結果に、追加や削除として現れない（改名は `import` で保たれる）。
