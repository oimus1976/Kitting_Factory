---
title: CHANGELOG
doc_type: changelog
version: v0.1
status: active
created: 2026-01-21
scope:
  - reboot
---

# CHANGELOG

## [v0.1] - 2026-01-21（リブート版）

### Added
- PROJECT_STATUS.md を新規作成
- CHANGELOG.md を新規作成
- リブート状況整理ドキュメントを追加
  - `docs/reboot/REBOOT_STATUS_v0.1.md`
- Source フォルダの正本定義ドキュメントを追加
  - `docs/reboot/source_inventory.md`

### Changed
- docs/reboot/ フォルダ構成を採用
- Build-TestEnvironment.ps1 の正本候補を再定義
- Align Build-TestEnvironment ISO names and Server ImageName with source inventory
- Separate user-facing scripts into scripts/ and move Source directory to repo root
- Remove remaining FactoryPath references and align internal paths after scripts/src separation


### Notes
- 本 CHANGELOG は 2026-01 のリブートを起点とする
- それ以前の変更履歴は遡及記載しない
