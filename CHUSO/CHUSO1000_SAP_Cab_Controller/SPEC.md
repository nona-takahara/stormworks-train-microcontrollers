# CHUSO 1000 (SAP) 仕様書

## 2000との主な差分

- NITS Simple Bridgeを使用するため、Control Commands Type 3、Simple Interface RXを使用しない
  - よく見たらほとんど一緒
- ただし、自車他車締切を使用するため、直接NITSを読むマイコンが必要

ブレーキは非常位置以外、すべて電磁直通ブレーキの制御下に置かれる。

非常ブレーキの信号を受けると、各車で非常管を減圧する。一定時間後に最小限ブレーキが立ち上がる。

## 参考（未実装・将来検討）

- NITS車と非NITS車混在時の非常ブレーキ読み替え構想（計画段階）：`EXTERNAL_SOURCE_NOTES.md` 6節
- 保安装置（ATS/ATC）・運転支援（ARC）の外部資料：`EXTERNAL_SOURCE_NOTES.md` 3節
