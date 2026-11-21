# P5-5: 管理 API と検証 セキュリティ監査および公開関門 G2・G3 準備報告書

- **対象 Issue**: goodnasubi/sigil-container Issue #13「P5-5: 管理 API と検証（ADR 0053）」
- **仕様根拠**: [ADR 0053「P5 コンテナ管理」](https://github.com/goodnasubi/sigil/blob/main/docs/decisions/0053-p5-container-management.md) 決定 3・5・6 および「脅威と対策（公開関門 G1）」、[ADR 0037「HMAC ベアラートークンによる認証」](https://github.com/goodnasubi/sigil/blob/main/docs/decisions/0037-p1-authentication.md)
- **日付**: 2026-11-21
- **作成担当**: agy（Gemini 系統）
- **状態**: G2 監査完了・G3 レビュー準備完了（所有者による公開可否判断待ち。本 PR の作成・マージは外部公開の許可を意味しない）

---

## 隔離境界についての重要告知

> [!WARNING]
> **コンテナはカーネルを共有する。信頼できないコードの実行に対する完全な境界とは扱わず、その用途はマイクロ VM のバックエンド（後続）を前提にする。**
> 利用者向けのエラーメッセージおよび境界告知文（`isolation_boundary_notice()`）において、この前提を常に明示する。

---

## 1. 公開関門 G2 の確認（各段の完了検証）

P5（コンテナ管理）の全 5 段（P5-1〜P5-5）について、完了条件と検証状況を監査した。

| 段 | 成果物 | 完了検証内容 | 状態 |
|---|---|---|---|
| P5-1 | コンテナ仕様と状態の核 | 仕様の型と検証、既定拒否の規則、決定的な OCI runtime-spec の bundle 生成、OCI Image Layout 読み取りと層パス検査、P4 DB 保存形式 | 完了（PR #2） |
| P5-2 | ランタイム接続 | rootfs 展開、OCI ランタイム起動、作成・起動・停止・削除・状態・ログ、非 root 実行 | 完了（PR #5） |
| P5-3 | 調整ループ | 望ましい状態への収束、再起動方針、ヘルスチェック、変更通知購読、周期的な再調整 | 完了（PR #9） |
| P5-4 | ネットワークと公開 | 決定 4 の接続、ポート公開、ノード内名前解決、外向きフィルタリング、コンテナ間分離 | 完了（PR #11） |
| P5-5 | 管理 API と検証 | 管理 HTTP API、ADR 0037 HMAC 認証・認可、宣言の版管理連携、整合バックアップと復元後の収束 | 本 PR で実装（Issue #13） |

### 監査項目 1: 秘密（Secrets）の取り扱い
- **環境変数での受け渡し禁止**: 秘密（HMAC 認証鍵、コンテナ秘密値）は環境変数ではなく、ファイル（メモリ上の `Secret` 型）で渡す仕様を遵守。
- **平文露出の完全排除**: 仕様（`ContainerSpec`）、状態（`StateStore` / `AclStore`）、ログ（`LogEntry`）、エラーメッセージ（`ContainerError` / `AdminResponse.body`）に鍵やトークンなどの秘密情報を一切出力しないことを確認。
- **バックアップの秘密性**: バックアップアーカイブ（`BackupArchive`）は原本データと同一の機密レベルとして扱い、テストにおいては公開された固定の使い捨て鍵・データのみを使用。

### 監査項目 2: 上限（Resource Limits）の徹底
- **読み込み前適用**: すべての上限は意味解釈・デコード前に適用され、超過時に自動分割や黙った切り捨てを行わず、明示的なエラー型（`LimitExceeded` / HTTP 413）で即時拒否。
  - 仕様サイズ上限: 64 KiB (`max_spec_size`)
  - 管理 API トークン長上限: 1,024 byte (`max_admin_token_size`)
  - 管理 API ペイロード長上限: 404 byte (`max_admin_payload_size`)
  - 同時操作数上限: 16 (`max_concurrent_operations`)
  - ログバッファ上限: 100 MiB (`max_log_size`)
  - ワークロード数上限: 1,024 (`max_workload_count`)
  - レプリカ数上限: 64 (`max_replicas`)
  - 宣言コミット履歴保持上限: 256 (`max_declaration_commits`)

### 監査項目 3: 信頼基盤（TCB）の最小化
- 純 Sigil（`targets server` / `trust none` / `effects none`）で実装され、アプリケーション側に `raw.*` や `unchecked` などの未検証脱出ハッチを追加していない。
- 外部クレートや未知のネイティブ C ライブラリへの依存なし。
- 依存する `sigil` コンパイラは完全なコミット SHA（`a283bf54607d96e4c1aa27755a2cf2c9ea7a8ce8`、現行 main）で固定。

---

## 2. P5-5 完了条件の検証結果

### (1) 認証・認可の否定試験
- **認証否定**: トークン欠落、不正スキーム、不正署名、有効期限切れ（`now >= exp`）、未来発行（`now < iat`）、audience 不一致、トークン長超過がいずれも固定 401（本文 `unauthorized`、`WWW-Authenticate: Bearer`、`Cache-Control: no-store`）で拒否されることを確認（`tests/test_admin_api.sigil`）。
- **認可否定と存在秘匿**: 権限のない主体からのアクセス要求に対し、リソースが存在する場合であっても 403 ではなく **404 Not Found**（`not found`）を返し、読めない対象の存在を外部に漏洩させないことを検証。
- **権限変更の即時反映**: `grant_permission` および `revoke_permission` による権限変更が、次のリクエストから直ちに評価結果に反映されることを検証。

### (2) 宣言の差分と原子的検証・適用
- 望ましい状態の宣言を `DeclarationRepository` で版管理し、バージョン間の差分（追加・削除・変更）を決定論的に抽出（`compute_declaration_diff`）。
- 適用前にすべてのコンテナ仕様（特権禁止、資源上限必須、digest 固定、ホストマウント禁止）およびネットワーク仕様、レプリカ上限を厳格検証。
- 不正な仕様が含まれる場合、エラー型（`ContainerError`）で即座に拒否し、リポジトリの状態（コミット履歴および HEAD）を一切更新しない（一部だけ適用しない原子性を確認、`tests/test_declaration_versioning.sigil`）。

### (3) バックアップと復元後の収束
- 整合した時点の状態ストアからエントリを取り出し、決定論的 SHA-256 チェックサムを付与したマニフェストを持つ `BackupArchive` を生成（`container/backup.sigil`）。
- 改ざん・破損・未知バージョンのバックアップに対する復元を即座に拒否。
- 復元された状態ストアから調整ループ（`reconcile_tick`）を実行し、実行環境（`ModelRuntime`）上で必要なコンテナインスタンスの作成・起動が行われ、宣言された目標レプリカ数と健全性へと確実に収束することを検証（`tests/test_backup_restore.sigil`）。

### (4) 評価器（SIR）とネイティブ（sigil build）の一致
- `test.sh` を通じ、SIR 評価器（`sigil run`）およびネイティブバイナリ（`sigil build`）の双方で同一のテストスイート（全 11 スイート）を実行し、同一の操作列・戻り値（0 = 全合格）・エラー動作が得られることを確認。

### (5) 特権・環境依存テストの扱い
- 実 OCI ランタイム（runc / crun）や cgroup v2、user namespace を要する結合試験（`test_runtime_e2e.sh`）は、実行環境にランタイムが存在しない場合に黙って成功とせず、スキップされた旨を明示的に出力して記録する（CI では Ubuntu ランナー上で runc/crun を利用可能）。

---

## 3. 公開関門 G3 報告の準備

- **目的**: 所有者が外部公開可否を判断するための独立レビュー用材料の提示。
- **公開前レビューの分担**:
  - 実装者（agy / Gemini 系統）と別系統のモデルである Claude（Anthropic 系統）による独立したセキュリティレビューを実施予定。
  - レビュー依頼先: Claude Code モード（セッション: `https://claude.ai/code/session_01J7YMSEJSmZnTKALNrGTW4R`）。
- **残る未対応事項（ADR 0053 決定 7）の再確認**:
  - nspawn バックエンド、マイクロ VM バックエンドは初版対象外（後続）。
  - 複数ノード（スケジューラ、クラスタ、サービス負荷分散、TLS 終端）は初版対象外。
  - レジストリとの送受信、イメージのビルドは初版対象外。
  - 秘密の保管庫（鍵管理サービス連携）は未対応（メモリ上ファイル渡しまで）。
  - 共有カーネルの限界（信頼できないコードの完全な境界ではない）の受容。
- **判定**: 所有者の明示的な公開判断があるまで「いまは外部公開しない」方針を維持する。
