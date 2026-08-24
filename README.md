# Stromworks Train Microcontrollers by Nona Takahara

このリポジトリは、あまりにも複雑になってしまったStormworks向け鉄道車両マイコンを、AI&human readableな文書群に起こし直すことで何とか保守してみようという試みをしているリポジトリです。

作業には[storm-mcl](https://github.com/nona-takahara/storm-microcontroller-language)と[storm-lua-minify](https://github.com/nona-takahara/storm-lua-minify)を使います。

わけあってビルド支援はNode.jsで記述することになっています。

AIがLuaを書く場合は、事前に[LUA_CODING_GUIDE.md](LUA_CODING_GUIDE.md)を読んでください。
AIがマイコンロジックを書く場合は、適宜`storm-mcl spec`を呼び出して仕様のクセを把握してください。

## Stormworksとの入出力

統合支援コマンドを使う前に、`.env.example`を`.env`へ、
`microcontrollers.example.json`を`microcontrollers.local.json`へコピーし、
ローカル環境と管理対象を設定します。どちらの実ファイルもGit管理しません。
バックアップ先は絶対パスで指定します。`.gitignore`済みのリポジトリ内`.backup`を
使用できますが、Stormworksの現用マイコン保存領域内には置けません。

```console
pnpm microcontroller build <name...>
pnpm microcontroller check <name...>
pnpm microcontroller export <name...>
pnpm microcontroller import <name...>
```

全登録対象を操作するときだけ、対象名の代わりに`--all`を指定します。
`export`はLua生成、DSL検査、XML生成、バックアップ、Stormworks保存領域への
配置を行います。変更を伴う配置にはTTY上の確認が必要です。PNGは扱いません。

`import`はstorm-mcl v0.10.0以降の同期機能（`xml2dsl --sync-with`）を使い、既存DSLの
モジュール構造と名前を維持します。まずdry-runの診断を表示し、確認後に同期を
適用します。

設定例のプロジェクト定義は次の形です。

```json
{
  "projects": {
    "example": {
      "project": "Example/project.json",
      "stormworksFile": "Example.xml",
      "luaBuilds": [
        {
          "entry": "Example/src/main.lua",
          "output": "Example/deploy/main.lua",
          "overlay": "scripts/n1.lua",
          "stage": [
            { "source": "lib/shared.lua", "as": "shared.lua" }
          ]
        }
      ]
    }
  }
}
```

`stage`はminify中だけentryと同じディレクトリへ置く依存ファイル、`overlay`は
XML生成用の一時DSLツリー内で生成Luaを差し込むsidecarパスです。
