# v0.6 方針と次の1回の検証手順（2026-10-29）

## 決定事項

- OOBE中にPPKGのスクリプトをSYSTEMで動かす方式（v0.5r1）は凍結する。Hyper-VのSCSI VHDXはOOBEでUSBとして検出されず、このVMでは本来の経路を検証できないため。
- デスクトップ到達後、USBの `Kitting-Start.cmd` を「管理者として実行」1回で、既存 `Start-Kitting.ps1 -Action Stage` を直接呼ぶ（案D）。
  - Stageの条件は管理者権限（`Start-Kitting.ps1` の `Require-Admin`）であり、SYSTEMではない。
  - Stage用PS1 4本、SYSTEMガードは変更しない。ブリッジ（`OOBE-Bridge.ps1` / `After-First-Logon.ps1`）は使わない。
- OOBEのMicrosoftアカウント回避は当面、組織の既存手順（BYPASSNRO）を手順書に残して継続する。
  - 将来の置換候補：スクリプトを含まない「設定だけのPPKG」（ローカル管理者作成・PC名・OOBE省略）。Windows 11 Pro実機と物理USBで1回だけ検証する。
- 理由：Stageは約10秒で終わる（v0.4成功証跡）。入口を完全無人化しても年30台で約15分しか縮まない。時間短縮の本体はStage以降（Windows Update、RunVendor、IEモード設定、66手順）の自動化にある。

## 現場の流れ（MVP）

1. 電源投入 → OOBE。BYPASSNROでローカルアカウントを作成（現行手順どおり）。
2. 初回サインイン後、USBを挿す。
3. USBルートの `Kitting-Start.cmd` を右クリック →「管理者として実行」→ UACで「はい」。
4. 画面に PASS / STOP が表示される。PASSなら `state.json` が `WAIT_INET`。

## Kitting-Start.cmd の仕様

実装：[scripts/v06/Kitting-Start.cmd](../scripts/v06/Kitting-Start.cmd)（CP932・BOMなし・CRLF。日本語版Windowsのコンソール既定コードページに合わせる）

**ホストや開発用PCでは絶対に実行しない。** Windows 11 Pro上で管理者実行すると、本当にStageが走り `C:\ProgramData\KittingFactory` を作成する（`-NewUnassignedPC` 以外にこれを防ぐ仕組みはない）。

| 項目 | 内容 |
|---|---|
| 置き場所 | USBルート。同じ場所に `Start-Kitting.ps1`、`Update-Worker.ps1`（原本とバイト一致）、`KITTING_FACTORY_USB_V03.TAG`、`ClientSoft\` |
| 管理者確認 | 昇格していなければ何もせず終了し、「管理者として実行してください」と表示 |
| 呼出し | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Kitting.ps1" -Action Stage -SourceRoot "%~dp0." -NewUnassignedPC` |
| VM評価 | 引数 `VMEVAL` を明示した場合だけ `-AllowEnterpriseEvaluationVM` を付ける。自動判定はしない |
| パス | `%~dp0` 末尾の `\` が閉じ引用符をエスケープしないよう `"%~dp0."` を使う |
| ログ | 画面出力をUSBの `logs\<端末名>-<日時>-stage.log` にも残す（30台分の作業記録になる）。端末側は既存の `controller.log` |
| 終了 | Start-Kittingの終了コードをそのまま返し、PASS/STOPを表示して一時停止 |
| しないこと | 再試行、既存状態の削除・上書き、Windows Update、ベンダーBAT |
| 終了コード | 0=PASS、2=引数不正、3=非管理者、4=USBに必要ファイルなし、5=ログ作成不可、それ以外=Start-Kittingの終了コード |

### ホストでの確認結果（2026-10-29、本物のStageは実行していない）

| 確認 | 結果 |
|---|---|
| 文字コード・改行 | CP932で往復一致、BOMなし、LFのみの行0 |
| 配布物そのもの：引数不正（`FOO`、`VMEVAL X`） | 終了コード2で停止 |
| 配布物そのもの：非管理者で実行 | 終了コード3で停止、日本語メッセージが正しく表示 |
| テスト専用コピー（管理者チェックだけ除去）＋スタブ、空白入りパス | 引数なし：`-Action Stage -NewUnassignedPC`、VMフラグなし、ClientSoftを解決、PASS／`VMEVAL`：VMフラグあり、PASS／スタブ終了コード7：そのまま7を返しSTOP。USBの `logs\` にログ3件 |

未確認：管理者権限での実行と本物のStage。次の検証の手順4で確認する。

## 次の1回の検証（案D）

各手順は実施前に個別承認を得る。自動再試行はしない。

| 手順 | 内容 | 承認 |
|---|---|---|
| 0 | r1の生ログ回収：現VM（OOBE状態、媒体E:）で `C:\ProgramData\KF-v05-Probe\*` をE:へコピー → VMシャットダウン → ホストで読取専用マウントしSHA-256を1回記録 → アンマウント | 媒体書込・VM停止 |
| 1 | 媒体へ `Kitting-Start.cmd`、`Start-Kitting.ps1`、`Update-Worker.ps1` をルートに追加（既存ファイルは変更しない） | 媒体書込 |
| 2 | `OOBE-Before-PPKG-20261019` へ1回復元。既存の再接続手順で媒体をSCSI 0:2へ1回接続 | 復元・再接続 |
| 3 | OOBEを手作業で完了（ローカル管理者）。PPKGは適用しない | ゲスト操作 |
| 4 | デスクトップで `Kitting-Start.cmd VMEVAL` を管理者として1回実行 | ゲスト操作 |

手順0の結果（2026-10-30実施）：PASS。ゲスト側コピー `GUEST_COPY=PASS FILES=1`、ホスト回収 `HOST_COPY=PASS FILES=1`（SHA-256照合一致）、媒体アンマウント済み、Test-PCはオフ。回収先はリポジトリ外 `C:\Users\oimus\KittingOobeRetry-20261029-87a1c5ac\r1-raw-probe\`。回収した `devicecontext.log` の18行目で、例外が `OOBE-Bridge.ps1` のSYSTEMガード行から出ていることを確認した（PowerShell起動前の失敗という可能性は消えた）。

手順1の結果（2026-10-30実施）：PASS。媒体ルートへ `Kitting-Start.cmd`、`Start-Kitting.ps1`、`Update-Worker.ps1`（v0.4原本とハッシュ一致）を追加。既存のマーカーとClientSoft必須6ファイルはハッシュ不変、媒体アンマウント済み、Test-PCはオフ。結果は `C:\Users\oimus\KittingV06-20261030\step1-result.json`。

手順2の結果（2026-10-30実施）：PASS。復元1回、保存状態からの再開1回、媒体のSCSI 0:2への接続1回。最初のスクリプトは復元直後の状態読取が早すぎ（遷移中で「Off」と表示）、再開前に安全側で停止したため、復元をやり直さずに再開と接続だけを別スクリプト（STEP2b）で行った。ゲスト画面はOOBEの「国または地域」（日本が選択済み）。記録は `C:\Users\oimus\KittingV06-20261030\step2-result.json`（FAIL/RESUME段階の記録）と `step2b-result.json`（PASS）。

手順3の結果（2026-10-30実施、Codexのコンピュータユース）：PASS。「サインイン オプション」→「代わりにドメインに参加する」でローカル管理者 `kftest` を作成（Enterprise評価版。BYPASSNRO等の回避策は不使用）。プライバシー項目はすべて「いいえ」、診断データは必須のみ。OOBE中の更新は97%で「後で更新」を選択。デスクトップ到達後は操作していない。PPKG関連の画面は出なかった。

手順4の結果（2026-10-30実施、Codexのコンピュータユースで管理者コマンドプロンプトから `E:\Kitting-Start.cmd VMEVAL` を1回実行）：**PASS**。

- 画面：`EXIT_CODE=0`、`PASS: Stageが完了しました。状態は WAIT_INET です。` STOP・エラー表示なし。開始15:14:36 → WAIT_INET 15:14:49（約13秒）。
- ホストからPowerShell Direct（テスト用アカウント、読取のみ）で照合：`state.json` Stage=`WAIT_INET`、VmTrialMode=true、端末名一致、`controller.log` あり、BaselineHashes 6件が端末側payload・媒体側ClientSoftの両方と一致、payloadと媒体のファイル数とも124、`C:\ClientSoft` なし、`KittingBridge` なし、Windows Updateタスクなし。USBの `logs\` に実行ログ1件。
- 予定外：VM接続でのキー入力時にホストとゲストのキー配列差で記号が化けた。Enter前に消去し、確認済み文字列の貼り付けに切り替えた（再実行なし）。実機で操作者が直接入力する場合は発生しない。
- 結論：PPKG・ブリッジ・SYSTEMタスクを使わず、管理者1回の操作で既存Stage（PS1無改変）が `WAIT_INET` まで到達することを確認した。ただし評価VM（Enterprise評価版）での結果であり、Windows 11 Pro実機は未確認。

合格条件：

- 終了コード0、画面にPASS
- `C:\ProgramData\KittingFactory\state.json` の Stage が `WAIT_INET`
- `C:\ProgramData\KittingFactory\logs\controller.log` が存在
- `state.json` の BaselineHashes 6件が媒体側 `ClientSoft` と一致
- USBの `logs\` に実行ログが残る

停止条件：STOP表示または終了コード非0。ログを取って停止し、Windows Update・ベンダーBATへ広げない。

検証の限界：評価VMはEnterprise評価版のため、Pro実機でのOOBE（Microsoftアカウント要求）とは挙動が異なる。手順3の結果はPro実機の証拠にしない。

## やらないこと

- このVMでのPPKG適用（ダブルクリック／PowerShell／Windowsキー5回）の再試行
- 診断基盤（ETW、リフレクション、プロセス監査等）や保全手順の追加
- SYSTEMガードの削除・弱体化、Stage用PS1 4本の変更
- 新ISO・新VM・MockServerの先行作成

## 次に必要な情報

- 現行の手作業の、1台あたり・工程ごとのおおよその所要時間（Stage以降の自動化の優先順位を決めるため）
