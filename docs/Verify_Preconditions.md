---
title: Verify_Preconditions
version: 0.1
status: draft
purpose: >
  Verify-TestEnvironment.ps1 が正常に完走するために必要な
  前提条件と、Verify が保証しない事項を明確化する。
scope: verification
related_scripts:
  - scripts/Verify-TestEnvironment.ps1
  - scripts/Build-TestEnvironment.ps1
last_updated: 2026-01-22
---

# Verify_Preconditions.md

## 1. このドキュメントについて

本ドキュメントは、`Verify-TestEnvironment.ps1` が  
**「どこまでを確認し、どこからを前提条件として扱うか」**  
を明確にするためのものです。

Verify スクリプトは *万能な診断ツール* ではなく、  
あらかじめ満たされているべき前提条件の上で動作します。

その前提を明文化し、  
- Verify の失敗理由が「環境不備」なのか
- スクリプトや構成の問題なのか  

を切り分けやすくすることを目的としています。

---

## 2. Verify が保証すること

Verify-TestEnvironment.ps1 は、以下を **スクリプトの責務として保証** します。

### 2.1 Hyper-V ホスト側

- 仮想スイッチの存在確認
  - vSwitch-Internet
  - vSwitch-LGWAN
- 仮想スイッチの種類チェック
  - External / Private の妥当性
- 仮想マシンの存在確認
  - MockServer
  - Test-PC

### 2.2 Test-PC 構成

- 第2世代 VM であること
- 仮想プロセッサ数（2 コア以上）
- 仮想 TPM の有効化
- Secure Boot の有効化

### 2.3 MockServer（到達後）

- WinRM 接続が成立した場合に限り：
  - ネットワークアダプター数
  - 内部構成の検証（将来拡張予定）

---

## 3. Verify が保証しないこと（重要）

Verify は以下を **保証しません**。

- ホスト PC の IP アドレスが固定であること
- 外部ネットワークの種類
  - テザリング
  - 家庭 LAN
  - 職場ネットワーク
- ルーティングや NAT の存在
- 外部ネットワーク越しの WinRM 到達性

👉  
これらは **Verify の前提条件** として扱われます。

---

## 4. 必須前提条件（Verify 実行前に満たすべきこと）

### 4.1 管理用ネットワークの分離

- ホストと MockServer は  
  **管理専用の Internal 仮想スイッチ（例: vSwitch-HostMgmt）**  
  に接続されていること
- 外部ネットワーク（vSwitch-Internet）は管理通信に使用しない

### 4.2 IP 到達性

- ホストと MockServer は **同一 IPv4 セグメント**
- Ping が通ること
- WinRM (TCP/5985) が疎通可能であること

### 4.3 認証前提

- 使用するアカウントとパスワードが正しいこと
- 必要に応じて TrustedHosts が設定されていること

---

## 5. よくある誤解と補足

### 「IP が 172.20.10.0 なのはおかしい？」

問題ありません。

- テザリング等により、ホスト IP は動的に変化します
- Verify は **IP アドレス自体に意味を持たせません**
- 意味を持つのは「管理ネットワークとして分離されているか」です

---

## 6. 設計思想（Verify の立ち位置）

Verify-TestEnvironment.ps1 は、

> **「前提が満たされているかを喋るスクリプト」**

であり、

> **「前提を無理やり成立させるスクリプト」**

ではありません。

環境依存の問題をスクリプトで隠蔽しないことで、  
再現性とトラブルシュート性を優先します。

---

## 7. 今後の拡張予定

- vSwitch-HostMgmt を前提とした自動検出
- MockServer 側自己診断（自己報告）
- Verify 結果の段階的ステータス化（PRECONDITION / VERIFIED）

