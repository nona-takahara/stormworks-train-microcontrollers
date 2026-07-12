# Stromworks Train Microcontrollers by Nona Takahara

このリポジトリは、あまりにも複雑になってしまったStormworks向け鉄道車両マイコンを、AI&human readableな文書群に起こし直すことで何とか保守してみようという試みをしているリポジトリです。

作業には[storm-mcl](https://github.com/nona-takahara/storm-microcontroller-language)と[storm-lua-minify](https://github.com/nona-takahara/storm-lua-minify)を使います。

わけあってビルド支援はNode.jsで記述することになっています。

AIがLuaを書く場合は、事前に[LUA_CODING_GUIDE.md](LUA_CODING_GUIDE.md)を読んでください。
AIがマイコンロジックを書く場合は、適宜`storm-mcl spec`を呼び出して仕様のクセを把握してください。
