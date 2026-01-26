---
title: Build-TestEnvironment 仕様書
version: v0.1
status: reboot-draft
created: 2026-01-22
scope: build
related_scripts:
  - scripts/Build-TestEnvironment.ps1
  - scripts/Verify-TestEnvironment.ps1
notes:
  - 本書は実装から逆算して設計を言語化するための仕様書である
  - 実装詳細はスクリプトを一次情報とする
---

# Build-TestEnvironment 仕様書（v0.1 / たたき）

## 0. 本書の位置づけとスコープ

本書は、`Build-TestEnvironment.ps1` を一次情報として、  
ゼロタッチ検証環境の構築方針・設計判断・前提条件を言語化することを目的とする。

- 実装の正本はスクリプトである
- 本書は **設計意図と境界条件を残すための文書**である

### 本書が扱わない内容
- Setup-MockServer.ps1 内部の詳細実装
- 個別OS設定の網羅的説明
- 本番運用を前提としたセキュリティ設計

---

## 1. 全体像（ゴールと非ゴール）

### 1.1 ゴール

- 検証用PCキッティング環境を **再現可能に構築**できること
- Build → Verify → Test の流れが明確であること
- 実行環境（ネットワーク）に依存しない構造であること

### 1.2 非ゴール

- 本番Active Directory環境の構築
- ネットワーク構成そのものの最適化
- セキュリティ要件の網羅的担保

---

## 2. 前提条件・制約

### 2.1 実行環境前提

- Windows ホスト
- Hyper-V 有効
- 管理者権限での実行
- PowerShell 5.1 以上

### 2.2 ネットワークに関する前提

- 外部ネットワーク（Wi-Fi / テザリング / 社内LAN）は **不定**
- ホストのIPアドレスは固定されない
- IPアドレスそのものに意味を持たせない設計とする

本プロジェクトでは、  
**ホストと検証環境間の管理通信を外部ネットワークから分離する**ことを前提とする。

---

## 3. ディレクトリ・ファイル構成仕様

### 3.1 リポジトリ構成（概要）

- `scripts/`
- `src/`
- `Source/`
- `docs/`

### 3.2 各ディレクトリの責務

| ディレクトリ | 役割 |
|------------|------|
| scripts/ | 利用者が直接実行するスクリプト |
| src/ | 仮想マシン内部で使用される構成ファイル・補助スクリプト |
| Source/ | ISO 等の外部資材 |
| docs/ | 設計・前提・判断ログ |

---

## 4. ネットワーク設計

### 4.1 仮想スイッチ構成（確定）

| vSwitch名 | 種別 | 目的 | ホスト接続 |
|----------|------|------|------------|
| vSwitch-Internet | External | 外部通信 | あり |
| vSwitch-LGWAN | Private | LGWAN 模擬 | なし |
| vSwitch-HostMgmt | Internal | 管理・検証 | あり |

### 4.2 vSwitch-HostMgmt 設計方針（確定）

- 種別: Internal
- 目的:
  - WinRM による管理通信
  - Verify-TestEnvironment の実行基盤
- 外部ネットワークから独立した管理経路を提供する

IP アドレス帯は固定しないが、  
**ホストと MockServer が同一セグメントで疎通可能であること**を前提とする。

---

## 5. 仮想マシン設計

### 5.1 MockServer

- 世代: Generation 2
- 接続 NIC:
  - vSwitch-HostMgmt
  - vSwitch-Internet
  - vSwitch-LGWAN
- OS: Windows Server 2019 Evaluation
- 役割:
  - Active Directory
  - 共有サーバー
  - キッティング用基盤

### 5.2 Test-PC

- 世代: Generation 2
- TPM / SecureBoot: 有効
- OS: Windows 11 (手動インストール前提)
- 役割:
  - キッティング対象端末の検証用

---

## 6. Build-TestEnvironment.ps1 の責務

### 6.1 実施内容

- 仮想スイッチの存在確認・作成
- 仮想マシンの作成
- VHD 初期化とOS展開
- 必要ファイルの配置

### 6.2 実施しない内容

- AD の詳細構成
- ネットワーク内部設定
- 検証結果の合否判断

---

## 7. Setup-MockServer.ps1 との役割分担

- Build-TestEnvironment.ps1  
  → 環境を「作る」
- Setup-MockServer.ps1  
  → サーバー内部を「整える」

設定値は `config.ps1` に委譲する。

---

## 8. Verify-TestEnvironment との関係

Verify は以下を目的とする。

- 前提条件の可視化
- 設計逸脱の検出
- 「なぜ失敗しているか」を利用者に伝えること

Verify は **Build の成功を保証するものではない**。

---

## 9. 設計判断ログ（抜粋）

- IP固定前提は外部ネットワーク依存により破綻した
- vSwitch-Internet 依存の管理通信は採用しない
- HostMgmt を設けることで Verify の前提を明示できる

---

## 10. 今後の拡張余地

- Verify の exit code 設計
- Test-PC 完全自動化
- Snapshot / Checkpoint 戦略
