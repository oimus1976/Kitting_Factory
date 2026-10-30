# PowerShell Directによるゲスト証跡保全（2026-10-28）

同日追記: 本人の実収集はVERIFY_LOCALで停止した。原因はWindows PowerShell 5.1のConvertFrom-JsonがJSON配列を1個のpipeline objectとして返し、外側の@(...)が二重配列になったための件数誤判定。配列を変数へ代入してから正規化する修正と回帰テストを追加した。

実採取済みの証跡は上書きせず、Test-SavedGuestEvidence.ps1で読取検証した。manifestの12件、コピー元/コピー先ハッシュ、前後スナップショット、必要資産ハッシュ、ACLを照合してPASS。採取時Stage=WAIT_INET、タスク不在は原本worker一致と成功→正常削除ログで裏付けられた。新規のリポジトリ外フォルダーに検証receiptとチェックサムを保全した。ゲスト再接続・再収集・復元は行っていない。以下の「実採取未実施」は最初の準備段階の履歴であり、現在の保全判定はこの追記を参照する。

利用者は管理者PowerShellからTest-PCへの `Invoke-Command -VMName -Credential` 成功、state.jsonとKittingBridgeの存在、初回ログオンタスクの現在不在を報告した。これはNew-PSSessionを使った今回の保全完了とは別の確認である。

Codexは本人の対話資格情報を扱わず、本人のホストコンソールから一度実行する収集スクリプトを用意した。ゲストに一時ファイルを作らず、必要な既存ファイルを `Copy-Item -FromSession` でホストへ直接コピーする。

## 実行

**Hyper-Vホストの「管理者として実行」したWindows PowerShellで**、次を貼り付ける。ダウンロード・展開は不要。資格情報は表示される入力欄だけに入力し、チャットやファイルへ保存しない。

```powershell
Set-Location 'C:\Users\oimus\Kitting_Factory'
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File 'C:\Users\oimus\Kitting_Factory\scripts\v05\Collect-GuestEvidence.ps1'
```

実行ポリシー指定はこの子プロセスだけで、恒久変更はしない。組織ポリシーを回避する処理はない。

新設先は `C:\Users\oimus\KittingEvidence-<実行日時>-<識別子>`。公開リポジトリ外の新規フォルダーで、既存フォルダーを拒否する。利用者自身・SYSTEM・Administratorsだけにアクセスを許可する。保全先のGit配下、既知クラウド同期先、UNC、reparse pointを拒否し、既定ではローカル固定ドライブのユーザープロファイル直下へ作成する。成功・失敗時とも `LOCAL_OUTPUT` に実際の保存先を表示する。

## 読み取る範囲

- state.json、oobe.log、first-logon.log、実際に配置されたAfter-First-Logon.ps1（実行せず.txtとして保全）。これらは成功証跡の必須対象。
- 存在するcontroller.log、stage-payload.robocopy.log、既存v0.4診断run.logだけを追加。フォルダー全体やベンダー原本はコピーしない。1ファイル32MB超は停止。
- state.jsonのBaselineHashesで参照される必要な資産だけをゲスト内でSHA-256計算し、記録値と照合する。資産本体をホストへ転送しない。
- 初回ログオン・既存診断・Windows Updateの3タスクだけを対象に現在の登録XMLと実行情報を取得。存在しない場合は「列挙成功後に不在」と記録し、過去のXMLや実行結果を復元できたとは扱わない。
- 対象ファイルの存在・サイズ・読取可否・SDDL、ホストからVMと既存チェックポイントの名前・ID・状態を記録。

ゲスト側管理者トークンを確認する。読取失敗を「不在」と扱わず、権限不足・接続失敗・不正な状態ファイル・reparse point・途中変更を検出した場合はFAILで停止する。

## 検証と判定

1. コピー前のゲストSHA-256とホストコピーSHA-256・長さを照合。
2. コピー後に再読取し、対象ファイルの存在・SHA-256・長さ・SDDL、Stage、資産ハッシュ、対象タスクが採取中に変わっていないか照合。
3. ホスト保全物のACLを全件確認し、SHA256-manifest.jsonを書いて実ファイルを読戻し検証。verification-receipt.jsonにはmanifestのSHA-256を記録し、receipt自身も別チェックサムと読戻しで確認。
4. ゲストに配置された初回ログオンworkerのSHA-256がレビュー済みv0.4原本と一致し、現在のStage=WAIT_INET、実際のログに「Stage passed」→「First-logon task unregistered after successful Stage.」が順序どおり存在し、その後のSTOPがない場合に限り、タスク不在を `NORMAL_SELF_REMOVAL_SUPPORTED` とする。

原本v0.4ではStageの子プロセス終了コード0を確認した後に `Unregister-ScheduledTask` を呼び、正常に戻った後に削除成功ログを書く。失敗経路はタスクの無効化を試みる。したがって「現在不在」だけでは正常削除とも登録失敗とも断定できない。根拠不足・worker差分・矛盾があれば `UNDETERMINED`。登録失敗は今回の収集だけで根拠が得られなければ未判定とする。

期待するコンソール表示（実測結果ではない）:

```text
EVIDENCE=PASS
STAGE=WAIT_INET
FIRST_LOGON_TASK=NORMAL_SELF_REMOVAL_SUPPORTED
RESTORE_APPROVAL_READY=True
LOCAL_OUTPUT=（実際に新設したホスト側フォルダー）
```

PASSは指定した証跡の採取と保全の検証を示す。RESTORE_APPROVAL_READYは成功状態とタスク削除の裏付けがそろった場合の「承認判断へ進める」という情報で、復元の実行承認ではない。PPKG適用やDeviceContext自動起動の合格も意味しない。

FAIL時は部分保存物を保持し、FAILED_PHASEとcollection-failed.jsonに非機微の段階名だけを残す。資格情報を含みうるErrorRecordやInvocationInfoは保存しない。診断のための自動再試行、ゲスト設定変更、ログオンし直し等は行わない。

コンソールは状態コードと保存先だけを出力する。保全したログ・state・タスクXML・資産パス等をチャット、GitHub、Driveへ貼り付けない。本人が結果を伝える場合も上記状態コードだけでよい。

## 実施済みのローカル検査と限界

Windows PowerShell 5.1で構文解析、合成ログ7ケースの保守的なタスク不在判定、ACLの作成・設定・読戻し、ファイル/既存フォルダー上書き拒否、Git配下の保存先拒否、ゲスト読取ブロックのコマンド一覧を検査してPASS。

**本人の資格情報を使うNew-PSSession、Copy-Item転送、実データ採取は未実施。現段階で保全PASSや実際のStage・削除理由を確定しない。**

方式は[MicrosoftのPowerShell Direct説明](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct)の永続セッション・FromSessionコピーに従う。WinRM設定やネットワーク設定の変更を前提にしない。
