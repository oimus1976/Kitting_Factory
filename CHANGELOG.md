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

## [v0.6 manual start] - 2026-10-30

- v0.5のPPKG DeviceContext（OOBE中SYSTEM起動）方式を凍結。r1失敗は実行経路が非SYSTEMだったため（回収ログでSYSTEMガード行からの例外を確認）。
- デスクトップで管理者1回実行する入口 scripts/v06/Kitting-Start.cmd を追加。既存Start-Kitting.ps1 -Action Stageを無改変で呼ぶ（Stageは管理者権限で足り、SYSTEM不要）。
- Hyper-V評価VMで1回検証しPASS：約13秒でWAIT_INET、必須6ファイルのハッシュ一致。Windows 11 Pro実機は未確認。詳細はdocs/V06_PLAN.md。

## [v0.5 evidence verification fix] - 2026-10-28

- Windows PowerShell 5.1のJSON配列を二重に包んでmanifest件数を誤判定する不具合を修正し、複数要素の読戻し回帰テストを追加。
- ゲスト再接続なしで既存証跡を検証し、別の新規ACL制限付きフォルダーへreceiptを保存するTest-SavedGuestEvidence.ps1を追加。
- 本人実行済みの保全物は12件のmanifest照合等でPASS。採取時WAIT_INET、初回ログオンタスクの正常自動削除の根拠を確認。証跡本文はGit/Driveへ入れず、既存保全物を保持。

## [v0.5 evidence collector] - 2026-10-28

- 本人の対話資格情報をメモリだけで使うPowerShell Direct収集スクリプトを追加。ゲストへの書込は行わず、FromSessionで公開Git外の新規・ACL制限付きローカルフォルダーへ保全する。
- コピー前後のSHA256/SDDL、資産ハッシュ・タスク状態の安定性、ホストACL・manifest・読戻しを検査する。
- タスク不在の正常削除判定を原本worker一致・WAIT_INET・成功ログの順序で裏付ける。根拠不足は未判定。
- 5.1での合成データ検査はPASS。本人認証による実採取は未実施。手順はdocs/V05_GUEST_EVIDENCE.md。

## [v0.5 diagnostic candidate] - 2026-10-26

- v0.4 ZIPを入力にStage系4本をバイト保存し、BOM除去coreとASCII入口ラッパーを新規生成するscripts/v05を追加。
- 入口の依存確認・日時/実行ID/CWD/終了コード・代替ログを追加。VMEVAL/Stageのみ許可。
- 5.1の構文・原本/出力ハッシュ・入口5ケース・PPKG内部runtime mappingの検査を追加。
- 既存WCDから別IDのプロジェクトを複製し、既存WCDで候補PPKGを生成。原本由来生成物はlocal-v05以下でGit対象外。
- docs/V05_ACCEPTANCE.mdに副作用解析、ポリシー差、検査の限界、受入条件を記録。自動起動の実機PASSは未判定。

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

### Verified
- Build-TestEnvironment.ps1 completes successfully after repository structure refactor
