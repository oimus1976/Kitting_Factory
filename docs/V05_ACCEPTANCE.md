# v0.5 DeviceContext起動診断 — 2026-10-26

電源投入→USB接続→極力無人で完了するための、PPKG→ブリッジ経路の受入候補。
**ローカル生成・内容検査済み。DeviceContext自動起動の合格はまだ出していない。**

## 実物の調査結果

- 開始時点の作業ツリーはclean、branch `main`、HEAD `4871057`。remoteは `https://github.com/oimus1976/Kitting_Factory.git`。接続済みGitHubのmetadataでpublicを確認。commit/push/merge/PR作成なし。
- 既存repoは旧MockServer/テスト環境構築が中心。既存Stageを移植し直さず、Downloadsのv0.4 ZIPを入力にした。
- v0.4 ZIPは9エントリー、相対パスの直下ファイルのみ。4本のPS1、CMD、markerと説明書。ベンダー配布物や資格情報は同梱されていない。CMD先頭は `EF BB BF 40 65`。bare EXITなし。
- 原本ZIP SHA256: `FE4B6E8978764A72B0123A472E5F04493EBBE0E9AC5B098A60CD4E33587E425A`。生成後も一致。
- 診断キットは新規領域の作成・ZIP展開・ファイルコピー・BOM除去・manifest生成のみ。VM操作・PPKG適用・ベンダー実行なし。元の検査はcoreの原本一致・wrapper変更・PS構文を十分検査しないため強化した。
- 既存WCDのCommandLineは `cmd /c OOBE-Bridge.cmd VMEVAL`。元設定にはCMDとPS1の同じ `Name=OOBE-Bridge` があった。v0.5では拡張子込みの一意のNameとした。これを元失敗の原因とは断定しない。
- 元WCDプロジェクト名はv03-Desktop、customizations.xmlのPackageNameはv04、直近v04 PPKGのversionは1.1、現行XMLは1.2。元プロジェクトが既存PPKGと完全に同じ版とは扱わない。
- Hyper-V読み取り確認: Test-PC Running、Generation 2、4GB固定、SCSI 0:2に既存検証媒体。`OOBE-Before-PPKG-20261019`（15:00:42）と自動チェックポイントが存在。ゲストの現時点のstateは今回再取得していない。

## 副作用・依存関係

| 対象 | 実行すると起きること／条件 |
| --- | --- |
| Build-V05Overlay.ps1 | 指定した新規出力先だけに生成。既存出力は拒否。レビューしたZIPのSHA256に固定。ホストで実行済み。 |
| v0.5 wrapper | 診断ログへ追記し、5依存ファイルを確認してcoreを呼ぶ。引数は空またはVMEVALだけ。AUTOUPDATE等は93で停止。 |
| 元core / OOBE-Bridge.ps1 | SYSTEM・Hyper-V条件等を検査。ProgramDataのKittingBridge作成、ACL保護、3本コピー、設定書込、SYSTEM初回ログオンタスク登録。既存状態は拒否。ホストでは実行していない。 |
| After-First-Logon.ps1 | 未参加端末でmarkerとClientSoftが一意の媒体を探しStage。成功後タスク削除、失敗後タスク無効化。VMEVALでは更新を自動開始しない。 |
| Start-Kitting.ps1 / Stage | OS/新規端末条件を確認し、作業領域ACL設定、ClientSoftコピー、主要ファイルSHA256、state=WAIT_INETを保存。実際のベンダーBAT呼出はRunVendorの別ゲート。 |
| Update-Worker.ps1 | 起動するとWUA更新・EULA受諾・強制再起動・タスク解除がある。今回は同梱だけで起動しない。 |

初回ログオン後の依存は既存媒体直下の `KITTING_FACTORY_USB_V03.TAG` と完全なClientSoft。Stageを作り直していない。原本内の `-ExecutionPolicy Bypass` 指定も互換維持でバイト単位保存し、今回ホストでは実行していない。組織ポリシーとの適合は対象ゲスト側でも確認する。

## 実行ポリシー

PowerShell 7.6.9はLocalMachine=RemoteSigned、Windows PowerShell 5.1.26100.9711は全スコープUndefinedで実効Restricted。両方ともMachinePolicy/UserPolicyはUndefined。キット4ファイルにZone.Identifierなし、ビルダーは未署名。

5.1のRestrictedは以前のブロックを説明できるが、以前のセッション状態そのものを再現したわけではない。今回のビルド・検査は `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File ...` で子プロセスだけ指定。恒久設定変更・Unblock-File・組織ポリシー回避は行っていない。対象端末で組織ポリシーが定義されている場合は、署名等の承認された方式を使う。

## 生成物（すべてホスト側、新規）

- CommandFiles: `C:\Users\oimus\Kitting_Factory\local-v05\release\WCD-CommandFiles-v05`
- 原本・出力ハッシュ: `C:\Users\oimus\Kitting_Factory\local-v05\release\v05-build-manifest.json`
- 複製WCD: `C:\Users\oimus\Kitting_Factory\local-v05\WCD-Project-v05\KittingFactory-OOBE-VMTest-v05.icdproj.xml`
- PPKG: `C:\Users\oimus\Kitting_Factory\local-v05\WCD-Project-v05\KittingFactory-OOBE-VMTest-v05.ppkg`
- 展開監査: `C:\Users\oimus\Kitting_Factory\local-v05\PPKG-audit-7zip-v05`

PPKGは31,488 bytes、PackageID `{682fc7d9-4a8b-4133-aef2-5c3d230180f6}`、Version=1.0。
SHA256: `3C585A7823ABEF37F108960ACB976B64DBD4A78FF04B3C5D12E8FBCB0DF21BA2`。

local-v05全体は.gitignore対象。原本由来PS1・WCD・PPKG・診断証跡を公開Gitの追跡対象へ入れない。初期組立の `local-v05\build` は途中版であり使用しない。受入対象はreleaseを参照する上記PPKG。

## テスト結果

| 検査 | 結果 |
| --- | --- |
| Windows PowerShell 5.1でoverlay生成 | PASS |
| 同梱6ファイルと出力SHA256 | PASS |
| Stage系PS1 4/4の原本ZIPとのバイト一致・5.1構文解析 | PASS |
| coreは原本から先頭BOM3 bytesだけ除去 | PASS |
| wrapper ASCII/BOMなし、開発PS1 4本の5.1構文解析 | PASS |
| 入口の不足91・AUTOUPDATE拒否93・core戻り値7の伝播・代替ログ・両ログ不可90 | 5/5 PASS、全ケース無出力。実coreやStageを実行しない小さな隔離検査。空白と&を含むパスを使用。 |
| 既存WCD 2025.416.0.0によるCLIビルド | PASS、ICD exit 0 |
| PPKG内の6実ファイルSHA256と6 runtime mapping・CommandLine | PASS（既存7-Zipで展開して確認） |
| Windows Export-ProvisioningPackage | FAIL: mount error 522。実行トークンは非管理者。権限との因果は未確定。 |
| 7-ZipのWIM検査 | 展開・内容照合成功、reference count警告あり。v0.4 PPKGにも同じ警告あり。Windowsの適用互換性を保証しない。 |
| DeviceContext自動起動・OOBE・Stage回帰 | 未実施 |

CLI版WIMのNOTESはSource=CLI / TargetSkus=Invalid、既存GUI版v0.4はSource=Classic / TargetSkus=Desktop。Desktop store指定で生成したが、このメタデータ差の影響は未検証。Windowsでの内容確認とVM受入を満たすまで候補扱い。

再検査（ホスト、既存成果物への読取。ダウンロード・展開は不要）:

```powershell
Set-Location 'C:\Users\oimus\Kitting_Factory'
$ps51 = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File .\scripts\v05\Test-V05Overlay.ps1
& $ps51 -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File .\scripts\v05\Test-V05Package.ps1
```

両方PASSが期待結果。再buildは既存releaseを拒否するので、必要なときは新しい `-OutputRoot` を使い、WCDの全6参照も追随させる。

## WCDへの反映

元のOneDrive上プロジェクトを保持し、上記の**新規複製プロジェクト**へ反映済み。PackageName/IDを分離、CommandLineは `cmd /c OOBE-Bridge.cmd VMEVAL`、CommandFilesは次の6個に置換済み:

`OOBE-Bridge.cmd`, `OOBE-Bridge-Core-v04.cmd`, `OOBE-Bridge.ps1`, `After-First-Logon.ps1`, `Start-Kitting.ps1`, `Update-Worker.ps1`。

既存WCDのICD.exeでDesktop storeを指定し、新規PPKGへ出力済み。再出力が必要なら複製プロジェクトをWCDで開き、上記6参照とVMEVALを確認して「エクスポート→プロビジョニングパッケージ」。既存v0.4を上書きしない。資格情報・アカウント・Update設定の追加は不要。

## 既存VMでの最短受入

1. 現在の成功済みゲストから `KittingBridge` のログ・設定、KittingFactoryのstate.jsonとログ、主要資産のハッシュ、既存診断タスクの結果を、承認済みのローカル保管先へ保全する。ベンダー原本をDrive/Gitへ転送しない。今回ゲスト保全は未実施。
2. **ここで本人の明示承認が必要**。保全後に `OOBE-Before-PPKG-20261019` を復元する。復元とPPKG適用は今回未実施。実行前に4GB固定、SCSI媒体接続、復元によって媒体内容が巻き戻る可能性を確認する。実行中媒体をホストで同時マウントしない。
3. 承認された媒体転送方式で候補PPKGだけを媒体へ新規配置する。v0.4 PPKG/marker/ClientSoftは保持。複数PPKGがあればv0.5を明示選択する。適用前にPPKGのSHA256一致を確認する。
4. ゲストの管理者PowerShellで `Export-ProvisioningPackage -PackagePath E:\KittingFactory-OOBE-VMTest-v05.ppkg -OutputFolder C:\KF-v05-audit` を**新規フォルダーへ**実行し、同梱6ファイルとCommandLineを確認する。E:は過去の実測値なので、今回もmarkerとClientSoftを確認してから使用。Windows展開も失敗する場合は適用せず、複製WCDのGUIで別ファイル名へ再出力して比較する。
5. OOBEの標準プロビジョニング画面でv0.5を一度適用。BATの手動呼出・SYSTEM診断タスクでの代替実行は行わない。180秒経過だけで再適用せず、Windows側イベント・PPKG状態・入口ログを確認する。MicrosoftのOOBE provisioning全体の制限30分と、以前のPowerShell呼出180秒を混同しない。
6. 初回ログオン**前**に入口ログの `IDENTITY=nt authority\system` 相当、`COMMAND_FILES_PRESENT=5`、`EXIT_CODE=0`、ENDと、KittingBridge生成・初回ログオンタスク自動登録を確認。これを起動経路PASSとする。
7. 既存媒体を接続したまま初回ログオン。state=WAIT_INET、VMTrialMode=true、資産SHA256一致、初回ログオンタスク自動解除、UpdatePass/Boots/Skipped=0を確認。これをStage回帰PASSとする。Windows 11 Pro実機合格は別。

入口ログ: `%ProgramData%\KF-v05-Probe\devicecontext.log`。代替: `%SystemDrive%\KF-v05-entry-fallback.log`。

| 観測 | 次の切分け |
| --- | --- |
| ログなし | 未呼出し／CMD開始前失敗／両ログ不可。PPKG登録とProvisioning-Diagnostics-Provider/Adminを時刻・PackageIDで照合。未実行と断定しない。 |
| 91 / MISSING_FILE | 同梱・展開ファイル名の不一致。 |
| 93 | 空またはVMEVAL以外の起動指定。 |
| 非ゼロ、PREEXISTING_*あり | 元bridgeの再実行防止条件。成功済み状態を削除して続行しない。 |
| 非ゼロ、既存oobe.logなし | SYSTEM/VMガード、PowerShell開始前、実行ポリシー等。入口の実行ID・ファイル所在とWindowsイベントで調査。 |
| STARTのみ | core中断・プロセス終了等。タイムアウト原因と断定しない。 |

ローカルアカウント作成を含むOOBE全体の無人化は今回未実装。現段階の目的は自動ブリッジと既存Stageの接続を受け入れること。

一次資料（2026-10-26確認）:

- [Microsoft: ProvisioningスクリプトのSYSTEM実行・無出力・同梱・CWD・タイミング・制限](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-script-to-install-app)
- [Microsoft: 実行ポリシーと組織ポリシー優先順位](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- [Microsoft: WCD CLIの生成オプション](https://learn.microsoft.com/en-us/windows/configuration/provisioning-packages/provisioning-command-line)
