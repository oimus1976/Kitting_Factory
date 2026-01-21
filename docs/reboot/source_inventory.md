---
title: Source Inventory（検証環境用資材一覧）
doc_type: source_inventory
status: fixed
scope:
  - test_environment
  - reboot
assumptions:
  - Source フォルダは git 管理対象外
  - 本書に記載された内容が再現可能性の基準となる
---

# Source Inventory（検証環境用資材一覧）

## 1. このドキュメントの目的

本ドキュメントは、  
**Kitting_Factory における検証環境（MockServer / Test-PC）構築に使用する  
Source フォルダ内資材を固定・明文化**することを目的とする。

- 作業PCクラッシュ
- 引継ぎ
- 数か月〜数年後の再構築

といった状況でも、  
**「どの資材を用意すれば Build-TestEnvironment.ps1 が動くか」**を  
一次情報として保証する。

---

## 2. Source フォルダの位置づけ

- `Source/` フォルダは **git 管理対象外**
- 大容量ファイル（ISO）を含むため、各環境で手動配置する
- スクリプトは **ファイル名完全一致**を前提としている

```text
Kitting_Factory/
├─ src/
├─ docs/
└─ Source/   ← 本ドキュメントで定義
````

---

## 3. 検証環境で使用する ISO 一覧（FIX）

### 3.1 Windows Server（MockServer 用）

| 項目    | 内容                                                                            |
| ----- | ----------------------------------------------------------------------------- |
| 用途    | MockServer 仮想マシン OS                                                           |
| ファイル名 | `17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso` |
| 種別    | Windows Server Evaluation                                                     |
| 世代    | Windows Server 2019 系                                                         |
| 言語    | ja-jp                                                                         |

#### スクリプト内での使用箇所

* `Build-TestEnvironment.ps1`

  * `$ServerIsoName`
  * `Mount-DiskImage`
  * `Expand-WindowsImage`

#### install.wim 内 ImageName（確認済み）

```
Windows Server 2019 Datacenter (Desktop Experience)
```

---

### 3.2 Windows Client（Test-PC 用）

| 項目    | 内容                                                                                           |
| ----- | -------------------------------------------------------------------------------------------- |
| 用途    | Test-PC 仮想マシン OS                                                                             |
| ファイル名 | `26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso` |
| 種別    | Windows Client Enterprise Evaluation                                                         |
| 世代    | Windows 11                                                                                   |
| 言語    | ja-jp                                                                                        |

#### スクリプト内での使用箇所

* `Build-TestEnvironment.ps1`

  * `$ClientIsoName`
  * `Add-VMDvdDrive`

---

## 4. Source フォルダ構成（確定形）

```text
Source/
├─ 17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso
└─ 26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso
```

※ 上記 **2 ファイルのみ**を前提とする
※ サブフォルダ構成は使用しない

---

## 5. 運用上の注意事項

* ファイル名を変更した場合、
  `Build-TestEnvironment.ps1` の該当変数も **必ず同時に変更**する
* ISO の差し替え（別ビルド・別世代）を行う場合は：

  1. 本ドキュメントを先に更新
  2. install.wim の ImageName を再確認
  3. スクリプトを更新
     の順で行う

---

## 6. 非対象（本フォルダに置かないもの）

以下は `Source/` には配置しない。

* PowerShell スクリプト（src/ 管理）
* 無人応答ファイル（autounattend.xml）
* 設定ファイル（config.ps1）
* ログ・バックアップ・検証用ファイル

---

## 7. 本ドキュメントの位置づけ

* 本書は **Source フォルダの正本定義**
* REBOOT_STATUS.md と併せて読むことを前提とする
* 検証環境が再現できない場合は、
  **最初に本書と Source の実体を突合**する
