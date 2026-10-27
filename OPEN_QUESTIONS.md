# 仕様書の書き直しで残った質問と作業

仕様書（`SPEC.md` など）を書き直す途中で出た、まだ決まっていない質問と、決まったが未着手の作業を集めたファイルである。各項目は、それだけで読めるように書いてある。

回答は各項目の「回答:」に書く。決まった項目は、該当する仕様書に反映し、このファイルから削る。

仕様書の中では、確認が済んでいない記述に `[unconfirmed]` を付けてある。このファイルの項目が決まるまで、その印は動かさない。

## 質問

### `n390.lua` の図形（ATP モード 1 と 2）は、どの保安装置か

- 対象: `CHUSO2000_Cab_Display_IV`
- 状況: `n390.lua` は、ATP モード（1 または 2。`Loop Start` の N5「保安装置選択」と同じ元の値）に応じて、別の図形を描く。モードが 1 か 2 かは、`TOGGLE` で決まる。
- 分からないこと: 1 と 2 が、それぞれどの保安装置か。画面で見える図形が何を示すか。画面で確かめる必要がある。
- 回答:

### `to NITS` の B5 は常に false でよいか

- 対象: `CHUSO2000_Signal_Gateway`
- 状況: NITS バスへ出す `to NITS` の B5 は、`CONST_BOOL`（常時 ON）を `NOT` した値、つまり常に false である。B5 に対応する信号源は、どこにもつながっていない。ノード名は `to_nits_reserved_bit_fixed_value`（予約ビットを固定値にしたもの）である。
- 分からないこと: NITS の仕様で B5 が何を表すか。常に false のままでよいか。
- 選択肢: 予約ビットなので、false のままでよい／何かをつなぐ予定がある。
- 回答:

### `CHUSO1800_Traction_Controller_main_renamed.sw-net` の扱い

- 状況: 利用者の回答は「`rename-and-sort` スキルの残骸なので消してよい」だった。ただし、`CHUSO1800_Traction_Controller/SPEC.md` は、このファイルのノード名（`catenary_input_zero` など）で書いてある。`main.sw-net` は古いノード名で、この名前を持たない。消すと、SPEC が指すノード名が、どのファイルにも無くなる。
- 選択肢 A: `_main_renamed.sw-net` を `main.sw-net` に置き換える（ポート名の綴りも直す）。SPEC はそのまま使える。
- 選択肢 B: `_main_renamed.sw-net` を消し、SPEC を `main.sw-net` のノード名で書き直す。
- 回答:

### 1200系: 絶対上限の回転数（4320 rpm）に達したときの動作

- 対象: `CHUSO1200_Traction_Controller`（`SPEC.md` の 8.2 節）
- 状況: 力行遮断は 3560 rpm、再投入は 3500 rpm、絶対上限は 4320 rpm である（`CHUSO/DC_traction_motor_solver_handoff_1955-1982.md` の 3.2 節）。歯車比 6.07（仮）では、力行遮断が約 95 km/h で先に働き、4320 rpm は約 115 km/h に当たる。ハンドオフには、絶対上限に達したときの動作が書かれていない。
- 分からないこと: 惰行や下り勾配で絶対上限に達したときに、何をするか。
- 選択肢: 非常制動条件と同じく回路を遮断する／発電制動を効かせて抑える／何もしない（力行遮断のみ）。
- 回答: 電気回路のみ遮断

### 1200系: 非常制動中に発電制動を使うか

- 対象: `CHUSO1200_Traction_Controller`（`SPEC.md` の 8.1 節）
- 状況: 旧資料（Dropbox の `Series1000/main.md`）は、非常ブレーキ時は発電ブレーキを行わないとしている。旧資料なので `[unconfirmed]`。1800系 LuaCore の非常制動条件は、成立中に電流と電力を0にして、回路を開放する。
- 分からないこと: 1200系でも、非常制動中は発電制動を使わない（開放する）でよいか。
- 選択肢: 使わない（開放する）／使う。
- 回答: 使用しない

### 1200系: 直列の段数を決める「適度な滑らかさ」の基準

- 対象: `CHUSO1200_Traction_Controller`（`SPEC.md` の 6 節）
- 状況: 直列を11段にするか17段にするかは、抵抗マップを作り、シミュレーションで決める。基準は利用者が定義する予定で、後回しにしている。
- 分からないこと: 何を測り（進段時の電流の段差、加速度の段差など）、どこまで許すか。
- 回答: 利用者が定義する（後回し）。

## 作業（決まったが未着手）

コードや手順の変更を伴うので、仕様書の書き直しでは手を付けていない。

- ゲーム内の XML とリポジトリの DSL のずれ（`CHUSO1800_Traction_Controller`、`CHUSO1800_Traction_Controller_LuaCore`、`CHUSO2000_Cab_Controller_V`、`CHUSO2000_Door_Min`、`CHUSO2000_Driver_Assistance_IV`、`CHUSO2000_Traction_Controller`）は、どちらが新しいか不明なので、手を付けない（利用者の回答）。食い違いの内容は、`xml2dsl --sync-with --dry-run` で見られる。
- `.sw-mcl` の `id` が古い名前（`n###`）のまま残っているプロジェクトがある（`CHUSO2000_Driver_Assistance_IV`、`CHUSO2000_Traction_Controller`。改名のときに `.sw-mcl` が追従していなかった）。この 2 つは XML と DSL にずれがあるため、`id` の対応表を作れない。ずれの扱いが決まってから直す（`CHUSO2000_Cab_Display_IV` と `CHUSO2000_Signal_Gateway` は直した）。
- `CHUSO2000_Cab_Controller_V` の取り込み元を、ゲーム内の `CHUSO2000_Cab_Controller_V.xml`（7/11 更新）に更新し、SPEC を書き直す。`import` は承認が要る操作なので、指示を待つ。ただし、上のずれの扱い（手を付けない）との関係を、確かめてから行う。
- `CHUSO2000_Driver_Assistance_IV/SPEC.md` の n105 のページ、種別、駅、メニューの番号の意味は、モニタ生成ツールの取り込みを待ってから書く。
- `LUA_CODING_GUIDE.md` の規約（位置引数と複数戻り値）を緩める。その前に、キーを共有する場合の実測で検証する。
- （別のセッションで扱う）`GeneralProbe` を使い、`TOGGLE` の初期値、`NUM_SWITCHBOX` の `b` 未接続、`CONST_BOOL`、`THRESHOLD` と `COUNTER` の `min` > `max` を実測する。ゲーム内で `GeneralProbe` が動くことの確認が先に要る。結果は、storm-mcl の Issue #102、#103 の根拠にできる。
