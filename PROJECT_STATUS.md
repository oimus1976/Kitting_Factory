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
