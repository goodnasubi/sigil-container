# sigil-container

Sigil の P5「コンテナ管理」の実装リポジトリです。

## 仕様の正本

仕様は [goodnasubi/sigil](https://github.com/goodnasubi/sigil) の [ADR 0053「P5 コンテナ管理」](https://github.com/goodnasubi/sigil/blob/main/docs/decisions/0053-p5-container-management.md) が正本です。このリポジトリには実装だけを置き、仕様の決定・変更は ADR 側で行います。

## P5 の概要

バックエンドに依存しない「コンテナ仕様」を核に、望ましい状態と観測した状態を調整ループで収束させる、単一ノードのコンテナ管理の仕組みです。隔離と資源の制限は既定で拒否（必要なものだけを仕様に明示する）方針です。

## 段の構成

| 段 | 内容 |
|---|---|
| P5-1 | コンテナ仕様と状態の核（仕様の型と検証、OCI runtime-spec の bundle 生成、状態の保存形式） |
| P5-2 | ランタイム接続（rootfs の展開、OCI ランタイムの起動・停止・削除・状態・ログ） |
| P5-3 | 調整ループ（望ましい状態への収束、再起動の方針、変更の通知の購読） |
| P5-4 | ネットワークと公開（既定は接続なし、宣言したポートの公開、ノード内の名前解決） |
| P5-5 | 管理 API と検証（認証と権限、宣言の版管理との連携、バックアップと復元） |

## 実装の前提（ADR 0053）

- 実装は純 Sigil の `trust none` とし、アプリケーション側に `raw.*`／`unchecked` を足さない。
- 依存する `sigil` の版は完全なコミット SHA で固定し、`Cargo.lock` を使う `cargo build --locked --release` で取得する。
- 状態の保存には P4 のデータベース、宣言の版管理には P4-3・P4-4 のリポジトリ管理（sigil-git）の固定した版を使う。
