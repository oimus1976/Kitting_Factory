---
title: Kitting_Factory リブート状況整理
doc_type: reboot_status
version: v0.1
status: draft
created: 2026-01
scope:
  - test_environment
  - reboot
  - recovery
audience:
  - project_owner
  - future_self
  - successor
assumptions:
  - Windows 11 Pro or Enterprise
  - Hyper-V available
  - GitHub repository is accessible
non_goals:
  - detailed script specification
  - production rollout procedure
---

# Kitting_Factory リブート状況整理ドキュメント v0.1

## 1. このドキュメントの目的

本ドキュメントは、  
**業務用端末キッティング自動化プロジェクト（Kitting_Factory）** において、

- 作業PCクラッシュ等により環境が失われた場合でも
- プロジェクトの現在地・前提・欠損点を短時間で把握し
- 検証環境を再構築できる状態に戻す

ことを目的として、**リブート時点の状況を整理・固定化**するものである。

本書は設計書ではなく、  
**「今どこまで出来ていて、次に何をすればよいか」を理解するための運用ドキュメント**である。

---

## 2. プロジェクトのゴール再定義（簡潔版）

### 最終ゴール
- 業務用Windows端末のキッティング作業を  
  **再現可能・自動化可能**な形で実行できること

### 当面のゴール（リブート後）
- **検証用キッティング環境（MockServer / Test-PC）を自動構築できる状態に戻す**
- 手動作業が発生する箇所を **明示的に把握**できていること

---

## 3. 現在地サマリ（2026-01 リブート時点）

### リポジトリ状況
- GitHub 上に `Kitting_Factory` リポジトリは存在
- 最終コミット：2025-08-27
- PowerShell スクリプト群は保持されている
- ただし以下は **意図的にリポジトリ外**：
  - `Source/` フォルダ（Windows ISO 等）
  - `config.ps1`（環境依存設定）

### 実装済みの主な機能
- Hyper-V 上に検証環境を構築するスクリプト群
- MockServer（オフライン展開用）構築
- Test-PC VM 作成
- 検証用の環境チェック（Verify スクリプト）
- キッティング工程をフェーズ単位で実行する Master スクリプト

---

## 4. リポジトリ構成（重要部分のみ）

```text
Kitting_Factory/
├─ README.md
├─ src/
│  ├─ Build-TestEnvironment.ps1
│  ├─ Build-TestEnvironment_v3.0.ps1
│  ├─ Verify-TestEnvironment.ps1
│  ├─ Setup-MockServer.ps1
│  ├─ Setup.ps1
│  ├─ MasterKittingScript.ps1
│  ├─ unattend.xml
│  └─ config.ps1（※リポジトリ非管理）
├─ .gitignore
└─ docs/
```

---

## 5. 前提環境（ホストPC）

### 必須要件
- Windows 11 Pro / Enterprise
- Hyper-V 有効化済み
- 管理者権限で PowerShell 実行可能

### ネットワーク前提
- Hyper-V 仮想スイッチ
  - `vSwitch-Internet`
  - `vSwitch-LGWAN`

※ スイッチ名は固定参照されているため、  
　差異は `config.ps1` 側で吸収する想定とする。

---

## 6. 検証環境の構成（論理）

```text
[Host PC]
└─ Hyper-V
├─ MockServer VM
│   └─ Windows Server (Eval)
│       └─ キッティング用資材・スクリプト配置
└─ Test-PC VM
└─ Windows Client (Eval)
```

---

## 7. リブート時に欠けているもの（要復旧）

### ① config.ps1
- 環境依存値（パス、スイッチ名、IP 等）を定義
- 現在：**存在しない**
- 方針：
  - `config.ps1.template` をリポジトリ管理
  - 実体は各環境でコピーして作成

### ② Source/ フォルダ
- Windows Server / Client ISO
- 応答ファイル用資材
- 現在：**未配置**

---

## 付録A: Sourceフォルダの確定内容（再現済）

本プロジェクトで使用する Source フォルダの内容は以下で確定している。
これらは当時の構成を再現済みであり、検証環境構築の前提条件とする。

- Windows Server (MockServer 用)
  - 17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso

- Windows Client (Test-PC 用)
  - 26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso

※ Source フォルダの詳細な資材一覧および正本定義は  
`docs/reboot/source_inventory.md` に委譲する。
本付録はリブート時点での要点確認用サマリとして位置づける。

---

## 8. リブート成功条件（判定基準）

以下をすべて満たした場合、  
**「Kitting_Factory リブート完了」**と判定する。

- [ ] `Build-TestEnvironment_v3.0.ps1` がエラーなく完走
- [ ] MockServer VM が起動し、ログイン可能
- [ ] Test-PC VM が作成される
- [ ] `Verify-TestEnvironment.ps1` の主要チェックが OK
- [ ] 手動対応が必要な箇所が文書化されている

---

## 9. 次フェーズ（想定）

1. `config.ps1.template` の作成
2. `Source/` に必要な資材一覧の明文化
3. 本ドキュメントの追記・補正
4. 実行ログ取得

---

## 10. 本ドキュメントの位置づけ

- 本書は **リブート・復旧用の一次ドキュメント**
- 設計・仕様詳細は別文書に委ねる
- クラッシュ・引継ぎ時は **最初に読むこと**
