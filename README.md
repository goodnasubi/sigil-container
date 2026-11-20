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
| P5-1 | コンテナ仕様と状態の核（仕様の型と検証、OCI runtime-spec の bundle 生成、OCI Image Layout 検査、状態の保存形式） | 完了（PR #2） |
| P5-2 | ランタイム接続（rootfs の展開、OCI ランタイムの起動・停止・削除・状態・ログ） | 完了（PR #5） |
| P5-3 | 調整ループ（望ましい状態への収束、再起動の方針、ヘルスチェック、変更の通知と周期的な再調整） | 完了（PR #9） |
| P5-4 | ネットワークと公開（既定は接続なし、宣言したポートの公開、ノード内の名前解決） | 本 PR で実装（Issue #10） |
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
- `container/oci_spec.sigil`: 仕様から OCI runtime-spec (`config.json`) を決定的に生成する純粋関数（user namespace および uid/gid マッピング対応）
- `container/image_layout.sigil`: ADR 0035 の OCI Image Layout 読み取りと層パスの検査（パストラバーサル、上位参照 `..`、リンク、特殊ファイル拒否、展開爆弾防止）
- `container/rootfs.sigil`: ADR 0035 のイメージ層の展開と検証（単一層、静的 ELF `/app`、User `65532:65532`、上限検査、RootfsRecord への変換）
- `container/runtime.sigil`: OCI ランタイム抽象（runc/crun のライフサイクルコマンド生成、OCI state JSON パース、100MiB ログバッファ管理、強制終了後の後始末計画と評価、差分照合）
- `container/state.sigil`: 配置の単位（Node, Workload, Instance, Rootfs, RuntimeState）と状態の保存形式（望ましい状態 Desired State と観測した状態 Observed State の分離、P4 DB 行符号化・復号、整合トランザクション）
- `container/reconcile_state.sigil`: 調整ループの状態の保存形式（宣言ポリシー `PolicyRecord`、ヘルスチェック宣言、再起動の経過 `RestartStateRecord`、操作の記録 `OperationRecord`）と上限の検証
- `container/reconciler.sigil`: 調整の純粋な核（宣言と観測の差から冪等な計画を作る `plan_tick`、再起動の方針と待ち時間（倍々・上限あり）、ヘルスチェックの判定（判定不能は失敗として数える）、通知＋周期で調整するかの判定 `should_reconcile`）
- `container/reconcile_loop.sigil`: 調整 1 回分の手順 `reconcile_tick`（読み出し→観測→計画→先行記録→実行→結果の記録）と、状態の保存先・実行環境のポート（契約と試験用モデル）
- `container/network.sigil`: ADR 0053 決定 4・6（P5-4）ネットワークと公開の核（コンテナごとの network namespace とブリッジ接続、既定拒否の分離、外向き通信の許可規則、宣言したポートの公開、ノード内の名前解決、パケット評価、P4 DB 保存形式）
  - **識別子制約**: `instance_id` および `workload_id` は Linux IFNAMSIZ（15 文字、接頭辞 `veth-h-` 7 文字）制限に合わせて英小文字・数字・ハイフンの 1〜8 文字に制限され、二重接続や名前解決名前空間の衝突は拒否されます。
  - **公開アドレス許可リスト**: `host_ip` はループバック（`127.0.0.0/8`）または RFC 1918 プライベート内部アドレスに限定され、`0.0.0.0` や先頭ゼロ、特権ポート（1024 未満）は拒否されます。
  - **外向き規則の安全性**: 空プレフィックス長、`/0`（`0.0.0.0/0` 含む）、ゲートウェイ `10.244.0.1`、ブリッジサブネット `10.244.0.0/24`、リンクローカル `169.254.0.0/16` を含む危険な宛先規則は拒否されます。
  - **MAC アドレスと IP 再利用**: MAC は 2 桁 16 進表記（`02:42:0a:f4:00:xx`）で決定的に生成され、detach されたホスト IP は自動的に再利用されます（最大収容数 253 個）。
  - **状態永続化の契約**: P4 DB（`NetworkEndpointRecord`）にはエンドポイントの基本情報と規則件数のみが永続化され、再起動後はコンテナ仕様から決定論的に詳細規則を再導出する前提です。
  - **実配線・後続課題**: Linux network namespace の実作成、veth ペア設定、nftables 規則設定、ポート転送、OCI バンドルの network namespace 配線は純粋評価モデル確立後の後続作業となります。
  - **IPv6 の扱い**: 現行は IPv6 未対応（fail-closed）であり、実配線時は netns 内で IPv6 を無効化（`disable_ipv6 = 1`）する必要があります。
  - **ピア接続**: ADR 0053 決定 4 に準拠し、クライアント側の外向き通信許可宣言（Egress ポリシー）として評価されます。
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
5. `tests/test_runtime_e2e.sh`: 実 OCI ランタイム（crun / runc）によるライフサイクル統合試験、否定試験（rootfs 読取専用書込禁止、既定拒否ネットワーク隔離）、強制終了後の後始末検証、runc / crun 出力差分照合記録

## 調整ループ（P5-3）の設計メモ

- **冪等性と再開**: 操作 ID は `(インスタンス, 種別, 世代)` から決定的に決まり、操作は「その状態にする」形で冪等。実行前に Pending の操作記録と再起動の経過を 1 トランザクションで保存し、実行後に結果を記録する。途中で強制終了しても、次の tick は Pending の操作を停止→削除→作成→起動の順で再開し、観測で既に満たされていれば Done にする。
- **観測を信じない**: 実行環境の状態は毎回取り直す。保存した状態は望ましい状態と再起動の経過・操作の記録だけで、実行環境の観測の代わりにはしない。
- **失敗を黙って成功にしない**: 保存の失敗では実行環境に触れずにエラーを返す。操作の失敗は `OperationRecord` に理由と試行回数を残し（上限 5 回で `Failed`）、周期的な再調整で再試行し続ける。観測の失敗・判定不能のヘルスチェックも失敗として扱う。
- **上限**: 再起動回数 1〜10（`always` を含む）、再起動の待ち時間 1 秒〜1 時間（倍々で増え上限で止まる）、ヘルスチェックの間隔 1 秒〜1 時間・連続失敗 1〜10、再調整の間隔 1 秒〜1 時間、ワークロード 1,024、レプリカ 64。超過は黙って切り捨てず `LimitExceeded` で失敗する。
- **範囲の線引き**: 本層は純 Sigil（`effects none`）で、状態の保存先と実行環境は契約つきのポート（試験用の実装は `StateStore` / `ModelRuntime`）。P5-2 のコマンド生成・P4 のデータベースへの実配線と、実 OCI ランタイム上の統合試験は後続の段で扱う。
