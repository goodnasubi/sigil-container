# sigil-container

Sigil の P5「コンテナ管理」の実装リポジトリです。

## 仕様の正本

仕様は [goodnasubi/sigil](https://github.com/goodnasubi/sigil) の [ADR 0053「P5 コンテナ管理」](https://github.com/goodnasubi/sigil/blob/main/docs/decisions/0053-p5-container-management.md) が正本です。このリポジトリには実装だけを置き、仕様の決定・変更は ADR 側で行います。

## 隔離境界についての重要事項

> [!WARNING]
> **コンテナはカーネルを共有する。信頼できないコードの実行に対する完全な境界とは扱わず、その用途はマイクロ VM のバックエンド（後続）を前提にする。**

## P5 の概要

バックエンドに依存しない「コンテナ仕様」を核に、望ましい状態と観測した状態を調整ループで収束させる、単一ノードのコンテナ管理の仕組みです。隔離と資源の制限は既定で拒否（必要なものだけを仕様に明示する）方針です。

## 段の構成

| 段 | 内容 | 状態 |
|---|---|---|
| P5-1 | コンテナ仕様と状態の核（仕様の型と検証、OCI runtime-spec の bundle 生成、OCI Image Layout 検査、状態の保存形式） | 本 PR で実装 |
| P5-2 | ランタイム接続（rootfs の展開、OCI ランタイムの起動・停止・削除・状態・ログ） | 後続 |
| P5-3 | 調整ループ（望ましい状態への収束、再起動の方針、変更の通知の購読） | 後続 |
| P5-4 | ネットワークと公開（既定は接続なし、宣言したポートの公開、ノード内の名前解決） | 後続 |
| P5-5 | 管理 API と検証（認証と権限、宣言の版管理との連携、バックアップと復元） | 後続 |

## 実装の前提（ADR 0053）

- 実装は純 Sigil の `trust none` とし、アプリケーション側に `raw.*`／`unchecked` を足さない。
- 依存する `sigil` の版は完全なコミット SHA で固定し、`Cargo.lock` を使う `cargo build --locked --release` で取得する。
  - 固定コミット SHA: `97e22263d5fe2fbf390e4a38c66e4c38388b904a` (ADR 0053 マージコミット)
- 状態の保存には P4 のデータベース（`sigil-db`）の固定した版を使う。
  - 固定コミット SHA: `344675649426c42dd807d7635d7bd86fb24f6f6c`
- 宣言の版管理には P4-3・P4-4 のリポジトリ管理（`sigil-git`）の固定した版を使う。

## モジュール構成

- `container/limits.sigil`: ADR 0053 決定 3・6 に基づくシステム上限値定数（仕様サイズ 64KiB、層サイズ 1GiB、展開後合計 4GiB、ファイル数 100,000、パス長 256B、階層深さ 16、ログ 100MiB、非 root UID/GID 65532 等）
- `container/error.sigil`: コンテナ核のエラー型（`ContainerError`: `SpecValidation`, `LayerValidation`, `LimitExceeded`, `Corrupt`, `StateError`）と境界告知文
- `container/spec.sigil`: 純 Sigil・既定拒否のコンテナ仕様型（`ContainerSpec`）および厳格な検証関数（digest固定、非root、特権禁止、host共有禁止、rootfs読み取り専用、資源上限必須、危険なcap禁止等）
- `container/oci_spec.sigil`: 仕様から OCI runtime-spec (`config.json`) を決定的に生成する純粋関数
- `container/image_layout.sigil`: ADR 0035 の OCI Image Layout 読み取りと層パスの検査（パストラバーサル、上位参照 `..`、リンク、特殊ファイル拒否、展開爆弾防止）
- `container/state.sigil`: 配置の単位（Node, Workload, Instance）と状態の保存形式（望ましい状態 Desired State と観測した状態 Observed State の分離、P4 DB 行符号化・復号、整合トランザクション）
- `db/`: P4 組込みデータベース（`sigil-db`）の固定版

## テストの実行

```bash
./test.sh
```

テストスクリプトは以下の検証を順に行います：
1. `sigil fmt --check`: フォーマット検証
2. `sigil check --root .`: 静的型・所有権・効果検証
3. `sigil run --root .`: SIR 評価器でのテスト実行
4. `sigil build --root .`: ネイティブ実行バイナリのビルドと実行（評価器とネイティブの一致確認）
