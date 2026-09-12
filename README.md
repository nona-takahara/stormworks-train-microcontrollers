# Stromworks Train Microcontrollers by Nona Takahara

このリポジトリは、あまりにも複雑になってしまったStormworks向け鉄道車両マイコンを、AI&human readableな文書群に起こし直すことで何とか保守してみようという試みをしているリポジトリです。

作業には[storm-mcl](https://github.com/nona-takahara/storm-microcontroller-language)と[storm-lua-minify](https://github.com/nona-takahara/storm-lua-minify)を使います。

わけあってビルド支援はNode.jsで記述することになっています。

AIがLuaを書く場合は、事前に[LUA_CODING_GUIDE.md](LUA_CODING_GUIDE.md)を読んでください。
AIがマイコンロジックを書く場合は、適宜`storm-mcl spec`を呼び出して仕様のクセを把握してください。

## Stormworksとの入出力

統合支援コマンドを使う前に、`.env.example`を`.env`へコピーしローカル環境を
設定します。`.env`はGit管理しません。バックアップ先は絶対パスで指定します。
`.gitignore`済みのリポジトリ内`.backup`を使用できますが、Stormworksの
現用マイコン保存領域内には置けません。

管理対象とするマイコンには、そのプロジェクトディレクトリ直下(`project.json`と
同じ場所)に`build.json`を置きます。中身はゲーム側保存領域での現在のファイル名
だけです。

```json
{
  "stormworksFile": "Example.xml"
}
```

```console
pnpm microcontroller build <project-path...>
pnpm microcontroller check <project-path...>
pnpm microcontroller export <project-path...>
pnpm microcontroller import <project-path...>
```

`<project-path>`はプロジェクトディレクトリのリポジトリルートからの相対パス
です(例: `CHUSO/CHUSO1800_Traction_Controller_LuaCore`)。ネストしたディレクトリも
可能です。全登録対象を操作するときだけ、対象パスの代わりに`--all`を指定します。
`export`はLua生成、DSL検査、XML生成、バックアップ、Stormworks保存領域への
配置を行います。変更を伴う配置にはTTY上の確認が必要です。PNGは扱いません。

`import`はstorm-mcl v0.10.0以降の同期機能（`xml2dsl --sync-with`）を使い、既存DSLの
モジュール構造と名前を維持します。まずdry-runの診断を表示し、確認後に同期を
適用します。

Luaノードのビルド対象は自動で決まります。`main.sw-net`などのLUAノードが持つ
`script_ref`（例: `scripts/n1.lua`）から拡張子と`_deploy`サフィックスを除いた
名前（`n1`）に対応する`<project>/src/n1.lua`が実在すれば、そのノードは管理対象
になります。ビルドすると`<project>/deploy/n1_deploy.lua`が生成され、`export`時に
`script_ref`が指す場所へ差し替えられます。実在しないノードはまだ手貼りの
Luaとして無視されます。`<project>/deploy/`は生成物専用でGit管理しません。
