# CHUSO

中宗電鉄の各系列マイコンをまとめたディレクトリ。系列ごとに独立したプロジェクト
ディレクトリを持つ。

- `CHUSO1000_SAP_Cab_Controller/`
- `CHUSO1800_Traction_Controller/`・`CHUSO1800_Traction_Controller_LuaCore/`
- `CHUSO2000_Cab_Controller_V/`・`CHUSO2000_Cab_Display_IV/`・
  `CHUSO2000_Driver_Assistance_IV/`・`CHUSO2000_Traction_Controller/`・
  `CHUSO2000_Onecar_Control/`・`CHUSO2000_Door_Min/`・`CHUSO2000_Signal_Gateway/`

## ドキュメント

| ファイル | 役割 |
|---|---|
| [`SYSTEM_SPEC.md`](./SYSTEM_SPEC.md) | 2000系列システム全体の詳細仕様（正典）。全体データフロー、マイコン間インターフェース、各マイコン詳細、NITS通信プロトコル、制動・力行/ドア制御フロー |
| [`SignalComposite.md`](./SignalComposite.md) | 2000系列で使うコンポジット信号の全定義（正典）。チャンネル割付・負論理・NITSフレーム仕様 |

このREADMEの表と図は、上記2文書のうち関連性の把握に必要な部分だけを
要約したものである。チャンネル番号・負論理・ビット単位の仕様は必ず
上記2文書で確認すること。

## 2000系列の7マイコン

| マイコン | 役割 |
|---|---|
| **Cab Controller V** | 運転台制御の中核。マスコン・逆転器・ドア・標識灯・各種スイッチを集約し、制御コマンドと表示ステータスを生成 |
| **Cab Display IV** | 運転台モニタ表示。Monitor Status / Rolling Stock Status を映像化 |
| **Driver Assistance IV** | 運転支援。GPS+距離程から次駅・接近・停車・締切を判定 |
| **Traction Controller** | 牽引制御 (VVVF)。力行・回生・空気ブレーキ協調、パンタグラフ、高加速、Momelinkを管理 |
| **Onecar Control** | 単車制御。前後2運転台のControl Commands Type 3 (CC3)を合成。Simple IF前後反転 |
| **Door Min** | ドア最小制御。センサ間距離で開閉エリア判定、NITS指令で開扉、モータ速度とチャイムを出力 |
| **Signal Gateway** | NITS busとの出入口。CC3をSimple IF RX/Extended Commands RX/Rolling Stock Settingsへ変換し、`from NITS`/`to NITS`で編成内の他車と繋がる |

（`Signal Gateway`以外は`SYSTEM_SPEC.md`「1. システム概要」の表を要約。
`Signal Gateway`は`project.json`の入出力ポート宣言から判明した役割で、
SYSTEM_SPEC.md本文にはまだ記載がない。各マイコンの入出力ポート詳細は
`SYSTEM_SPEC.md`「3. 各マイコン詳細」および各プロジェクトの`SPEC.md`を参照）

## 2000系列マイコン間の関連

以下は2000系列マイコン間のコンポジット信号の概略図である。7マイコンのうち
Onecar Controlは、Cab Controller VとSignal Gateway/Traction Controllerの
間を中継するだけで図が煩雑になるため描いていない（後述）。

この図は**電気指令ブレーキ系統の標準構成**を示すものであり、系列番号で
対象範囲が決まるわけではない。電磁直通ブレーキ系統については別図を参照
（別図は未作成）。

正典は[`SYSTEM_SPEC.md`](./SYSTEM_SPEC.md)（特に「1.1 全体データフロー」
「2. マイコン間インターフェース」）だが、`Signal Gateway`はまだ同文書に
記載がないため、この図の該当部分は`CHUSO2000_Signal_Gateway/project.json`の
入出力ポート宣言のみを根拠にしている（sw-net内部のロジックは未確認）。
各信号のチャンネル割付や負論理は`SYSTEM_SPEC.md`/`SignalComposite.md`を
参照すること。この図は関連性の見取り図に留める。

```mermaid
flowchart TD
    CC[Cab Controller V]
    CD[Cab Display IV]
    DA[Driver Assistance IV]
    TC[Traction Controller]
    DM[Door Min]
    GW[Signal Gateway]
    NITS{{NITS bus}}
    INERTIA[("Inertia DB")]
    ATSATC["ATS/ATC"]

    CC -->|Monitor Status| CD
    CC -->|Monitor Status| DA
    DA -->|Drive Support| CC
    CD -->|"Loop Start, ATS/C Settings"| CC

    ATSATC -->|ATS/ATC| CC
    ATSATC -->|ATS/ATC| CD
    CC -->|ATS/C Reset Signal| ATSATC

    CC -->|"Control Commands TX"| GW
    GW -->|to NITS| NITS
    NITS -->|from NITS| GW

    GW -->|Simple IF RX| CC
    GW -->|Simple IF RX| TC
    GW -->|Extended Commands RX| CC
    GW -->|Extended Commands RX| TC
    GW -->|"Extended Commands RX"| DM
    GW -->|Rolling Stock Settings| CC
    GW -->|Rolling Stock Settings| TC
    DM -->|"Door Open (A)/(B)"| GW

    TC -->|Rolling Stock Status| CD
    TC -->|"Rolling Stock Status<br/>(Inertia Compositeと合成)"| GW
    INERTIA --> GW
    INERTIA --> TC
    TC -. "Momelink chain" .-> TC
```

Onecar Controlはこの図から省いた。前位・後位2台のCab ControllerのControl
Commands TXを1つのCC3へ合成し、Gatewayから戻ってきたSimple IF RXの前後を
入れ替えてTraction Controllerへ渡す、という中継の役割そのものは実在するが、
図の見通しを優先してその変換の中身は省略し、Cab Controller VとSignal Gateway/
Traction Controllerを直結する形で表した。合成・反転の詳細は`SYSTEM_SPEC.md`と
`CHUSO2000_Onecar_Control/project.json`を参照。

- **Signal Gateway**は実在するプロジェクト（`CHUSO2000_Signal_Gateway/`）で、
  `Control Commands TX`（Onecar Control経由でCC3に合成された形）を受け取り、
  `Simple IF RX`・`Extended Commands RX`・`Rolling Stock Settings`へ変換して
  各マイコンへ配る。`from NITS`/`to NITS`ポートで編成内の他車と繋がる（＝この
  図の「NITS bus」の実体）。Door Minからは`Door Open (A)/(B)`が戻り、Traction
  Controllerからは`Rolling Stock Status`（Inertia Compositeと合成された形）が
  入る。CP Request・SOS Button・Batteryなど他の車両物理系の入出力も持つが、
  マイコン間の関連の主題ではないためこの図では省略した。
- **CC3(≒Control Commands TX)はTraction Controllerへ直接渡らない。**
  必ずGateway→NITS bus→Gatewayと往復し、戻ってきた時点で`Simple IF RX`という
  別名になる。行き(Control Commands TX/CC3)と帰り(Simple IF RX)は同じデータの
  往復であり、並存する2経路ではない。
- **Cab Display IV → Cab Controller V**の`Loop Start, ATS/C Settings`は、
  Cab Controller Vの`Drive Loop`/`Settings Loop`入力に対応すると見られる
  （名前が完全一致ではないため、同じ配線かは要確認）。
- **Door Min**はCC3を直接受け取らない。開扉指令はGatewayからの
  `Extended Commands RX`(Door_Minでの別名`NITS Ext. Input`)経由で受け、
  状態は`Door Open (A)/(B)`としてGatewayへ返す。project.json上のDoor Min
  自身の出力は`Door is Open`1系統だけなので、Traction Controllerの自己ループ
  (M車/T車)と同様に、扉グループA/Bで2台構成になっていると見られる
  （未確認）。
- **Traction Controllerの自己ループ（Momelink, ID=1911）**は、他の信号と違い
  異なるマイコン間ではなく、同じTraction Controllerを積んだM車とT車の間を結ぶ
  専用線である。T車はローカルに電動機計算を持たないため、M車からMomelink経由で
  架線電圧・電流・空気ブレーキ分担を受け取る（いわゆる遅れ込め制御 ─
  電気制動の実際の効きに合わせて空気ブレーキ側の負担を配分する仕組み）。
  詳細は[`SYSTEM_SPEC.md`](./SYSTEM_SPEC.md) §5「制動・力行制御フロー」を参照。
- **Inertia Composite**は車両内の別マイコンから供給されるため、図では
  データストア(円柱)として表した。Signal GatewayとTraction Controllerの
  両方が独立にこれを受け取る（`Traction Controller`側は`Inertia Composite
  Input`という別ポート）。どのマイコンが実際の供給元かは未確認。
- **ATS/ATC**はCab Controller V・Cab Display IVへ`ATS/ATC`信号を供給し、
  Cab Controller Vから`ATS/C Reset Signal`を受け取る別マイコンである。
  この7マイコン（このディレクトリ配下のプロジェクト）には含まれず、
  まだこのリポジトリに実体を持たないため、図では他と区別して示した。
