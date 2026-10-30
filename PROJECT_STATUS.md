---
title: PROJECT_STATUS
doc_type: project_status
version: v0.1
status: active
created: 2026-01-21
scope:
  - reboot
  - test_environment
assumptions:
  - 本ファイルはリブート時点を起点として作成されている
  - 過去の履歴は CHANGELOG.md に遡及記載しない
---

# PROJECT_STATUS（v0.1 / リブート版）

## 2026-10-26: v0.5開発再開（現行）

2026-10-28追記: 本人からPowerShell Direct接続成功の報告あり。公開Git外への最小証跡保全スクリプトと本人実行手順を作成した。5.1のローカル合成検査はPASS、実採取は本人の対話認証待ち。[実行手順](docs/V05_GUEST_EVIDENCE.md)。タスク不在の理由と現在のStageは実採取まで未判定。

同日更新: 本人実行後、5.1のmanifest配列件数の誤判定を修正。元の証跡を保持した再検証はPASS。採取時WAIT_INETとタスクの正常削除を確認した。復元の承認判断へ進めるが、復元・PPKG適用は未実施。上の「認証待ち」は準備段階の履歴。

現在の目的はPPKG DeviceContext自動起動の診断・修正。旧MockServer構築は今回のスコープ外。
v0.4原本と診断キットを直接解析し、Stage系4本のバイト一致を保ったv0.5候補とPPKGを新規領域へ生成した。
5.1で静的検査、入口5ケース、PPKG内部6ファイル・runtime mappingのハッシュ照合はPASS。
WindowsのPPKG exportはerror 522。既存7-Zipで内容監査成功だが警告があり、適用互換性・DeviceContext自動起動・Stage回帰はVM受入待ち。
Test-PCやチェックポイント・既存媒体は変更していない。次はゲストの成功証跡保全後、本人の復元承認を得て既存OOBEチェックポイントから一度受入試験。
詳細: [v0.5受入記録](docs/V05_ACCEPTANCE.md)。以下のv0.1計画は過去の記録として保持。

## 1. プロジェクト概要

- プロジェクト名：Kitting_Factory
- 目的：
  - 業務用 Windows 端末のキッティング作業を
    **再現可能・自動化可能**な形で実行できるようにする
- 本ステータスは **2026-01 のリブートを起点**とする

---

## 2. 現在地（結論）

**検証用キッティング環境（MockServer / Test-PC）の再構築フェーズ**

- Source フォルダ内容：確定済み
- 設計整理・ドキュメント再整備：進行中
- 実行フェーズ：未着手（設計優先）

---

## 3. できていること（Done）

### 設計・整理
- リブート状況整理ドキュメント作成
  - `docs/reboot/REBOOT_STATUS_v0.1.md`
- Source フォルダの正本定義
  - `docs/reboot/source_inventory.md`
- Build-TestEnvironment.ps1 の正本候補確定
  - 工程カバレッジ重視で採用

### 前提条件
- 使用する Windows ISO（Server / Client）の再現完了
- docs/reboot/ フォルダ構成の確定

---

## 4. 未着手・残課題（Todo）

### 直近（リブート完了条件に直結）
- Build-TestEnvironment.ps1 に
  - source_inventory.md の値（ISO 名 / ImageName）を反映
- REBOOT_STATUS_v0.1.md の最終整理
- 検証環境構築スクリプトの実行
- 実行ログの取得・保存

### 次フェーズ
- `config.ps1.template` の設計・作成
- 手動工程の洗い出しと文書化
- MasterKittingScript.ps1 の再評価

---

## 5. リブート完了の判定基準（要約）

以下を満たした時点で **リブート完了**とする。

- 検証環境（MockServer / Test-PC）が再現できる
- Build-TestEnvironment.ps1 がエラーなく完走
- 再構築手順がドキュメントで追える

---

## 6. 次の一手（最小）

1. Build-TestEnvironment.ps1 の値修正
2. 実行 → ログ取得
3. CHANGELOG.md へ反映

---

## 7. 本ファイルの運用ルール

- 状態が変わったら **必ず更新**
- バージョンは「区切りの良い状態」でのみ上げる
- 詳細経緯は CHANGELOG.md に書く
