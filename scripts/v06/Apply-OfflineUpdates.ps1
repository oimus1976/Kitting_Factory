#Requires -Version 5.1
<#
Kitting Factory v0.6 - Stage後（WAIT_INET）の更新を、1回の実行につき1段階だけ進める。
  1. USBの累積更新（LCU）をDISMで適用
  2. 対象バージョン固定の設定を入れ、設定の「Windows Update」を開いて操作者に適用してもらう
     （APIからの機能更新の適用はPro実機で 0x80070005 により失敗し、設定画面からは成功したため）
  3. 対象バージョン・ビルドに達していれば DONE
再起動は行わない。操作者が再起動して再実行する。state.json は変更しない。
終了コード: 0=DONE、10=再起動して再実行、12=設定画面で更新して再起動後に再実行、1=STOP
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$UsbRoot      = $PSScriptRoot
$ManifestPath = Join-Path $UsbRoot 'Updates\updates-manifest.json'
$LcuDir       = Join-Path $UsbRoot 'Updates\LCU'
$StatePath    = Join-Path $env:ProgramData 'KittingFactory\state.json'
$PolicyKey    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$TargetBuilds = @{ '26H2' = 26300 }
$MinBuild     = 26100
$MinFreeGB    = 20
$script:LogPath = $null

function Log([string]$Message) {
    $line = ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message)
    Write-Host $line
    if ($script:LogPath) { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 }
}

function Read-UpdateManifest([string]$Path, [string]$Dir, [switch]$VerifyHashes) {
    $m = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($m.Schema -ne 1) { throw '更新一覧の形式が未対応です。' }
    $files = $m.Files
    $files = @($files)
    $targets = @($files | Where-Object Kind -eq 'Target')
    if ($targets.Count -ne 1) { throw '更新一覧のTargetは1件だけにしてください。' }
    if ([int]$targets[0].ExpectedBuild -le 0) { throw '更新一覧に期待ビルドがありません。' }
    $others = @(Get-ChildItem -LiteralPath $Dir -Force | Where-Object { $_.Name -notlike '*.msu' })
    if ($others.Count) { throw ('LCUフォルダーに.msu以外のファイルがあります: ' + (($others | ForEach-Object Name) -join ', ')) }
    foreach ($e in $files) {
        if ([IO.Path]::GetFileName($e.File) -cne $e.File) { throw ('更新一覧のファイル名が不正です: ' + $e.File) }
        $p = Join-Path $Dir $e.File
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('更新ファイルがありません: ' + $e.File) }
        if ((Get-Item -LiteralPath $p).Length -ne $e.Length) { throw ('更新ファイルの長さが一致しません: ' + $e.File) }
        if ($VerifyHashes -and (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $e.SHA256) { throw ('更新ファイルのハッシュが一致しません: ' + $e.File) }
    }
    return [pscustomobject]@{ TargetVersion = [string]$m.TargetVersion; TargetFile = (Join-Path $Dir $targets[0].File); ExpectedUbr = [int]$targets[0].ExpectedBuild }
}

function Get-NextAction([int]$Build, [int]$Ubr, [int]$ExpectedUbr, [int]$TargetBuild) {
    if ($Build -lt $MinBuild -or $Build -gt $TargetBuild) { return 'UNSUPPORTED' }
    if ($Ubr -lt $ExpectedUbr) { return 'APPLY_LCU' }
    if ($Build -lt $TargetBuild) { return 'APPLY_FEATURE' }
    return 'DONE'
}

function Test-RebootPending {
    return (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
           (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

function Set-TargetReleasePolicy([string]$Key, [string]$Version) {
    # 既に別の値が入っている場合は上書きしない（組織のポリシーを壊さないため）
    if (Test-Path -LiteralPath $Key) {
        $cur = Get-ItemProperty -LiteralPath $Key
        foreach ($pair in @(@('ProductVersion', 'Windows 11'), @('TargetReleaseVersionInfo', $Version), @('TargetReleaseVersion', 1))) {
            $prop = $cur.PSObject.Properties[$pair[0]]
            if ($null -ne $prop -and [string]$prop.Value -cne [string]$pair[1]) { throw ('既存の更新ポリシーが異なります: ' + $pair[0]) }
        }
    } else {
        [void](New-Item -Path $Key -Force)
    }
    Set-ItemProperty -LiteralPath $Key -Name ProductVersion -Value 'Windows 11' -Type String
    Set-ItemProperty -LiteralPath $Key -Name TargetReleaseVersionInfo -Value $Version -Type String
    Set-ItemProperty -LiteralPath $Key -Name TargetReleaseVersion -Value 1 -Type DWord
}

function Stop-ForReboot([string]$Message) {
    Log ('NEXT: ' + $Message)
    Log 'NEXT: 再起動してから、もう一度 Kitting-Update.cmd を管理者として実行してください。'
    exit 10
}

try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '管理者として実行されていません。右クリック →「管理者として実行」で起動してください。'
    }
    $logDir = Join-Path $UsbRoot 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) { [void](New-Item -ItemType Directory -Path $logDir) }
    $script:LogPath = Join-Path $logDir ('{0}-{1:yyyyMMdd-HHmmss}-update.log' -f $env:COMPUTERNAME, (Get-Date))

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { throw '状態ファイルがありません。先に Kitting-Start.cmd でStageを実行してください。' }
    $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Schema -ne 1 -or $state.ComputerName -cne $env:COMPUTERNAME) { throw '状態ファイルがこの端末のものではありません。' }
    if ($state.Stage -cne 'WAIT_INET') { throw ('Stageが WAIT_INET ではありません: ' + $state.Stage) }

    $m = Read-UpdateManifest $ManifestPath $LcuDir
    if (-not $TargetBuilds.ContainsKey($m.TargetVersion)) { throw ('未対応の対象バージョンです: ' + $m.TargetVersion) }
    $targetBuild = $TargetBuilds[$m.TargetVersion]

    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $ubr = [int]$cv.UBR
    Log ('現在 {0} ビルド {1}.{2} / 目標 {3} ビルド {4}.{5}以降' -f $cv.DisplayVersion, $build, $ubr, $m.TargetVersion, $targetBuild, $m.ExpectedUbr)

    if (Test-RebootPending) { Stop-ForReboot '再起動待ちの更新があります。' }

    switch (Get-NextAction $build $ubr $m.ExpectedUbr $targetBuild) {
        'UNSUPPORTED' { throw ('このビルドには対応していません: ' + $build) }
        'APPLY_LCU' {
            $freeGB = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(':')).Free / 1GB
            if ($freeGB -lt $MinFreeGB) { throw ('Cドライブの空きが不足しています（{0:N1}GB、必要{1}GB）' -f $freeGB, $MinFreeGB) }
            Log '更新ファイルを照合しています。'
            $m = Read-UpdateManifest $ManifestPath $LcuDir -VerifyHashes
            Log '累積更新を適用しています（数十分かかることがあります。電源を切らないでください）。'
            # 進捗バーと空行はログに残さない
            & "$env:SystemRoot\System32\dism.exe" /Online /Add-Package "/PackagePath:$($m.TargetFile)" /NoRestart |
                Where-Object { $_ -and $_.Trim() -and $_ -notmatch '^\s*\[[= ]*[0-9.]+%[= ]*\]\s*$' } | ForEach-Object { Log $_ }
            $rc = $LASTEXITCODE
            Log ('DISM終了コード=' + $rc)
            if ($rc -ne 0 -and $rc -ne 3010) { throw ('累積更新の適用に失敗しました。C:\Windows\Logs\DISM\dism.log を確認してください（終了コード {0}）' -f $rc) }
            Stop-ForReboot '累積更新を適用しました。'
        }
        'APPLY_FEATURE' {
            Set-TargetReleasePolicy $PolicyKey $m.TargetVersion
            Log ('対象バージョンを {0} に固定しました。' -f $m.TargetVersion)
            Log ('NEXT: 設定の「Windows Update」を開きます。「更新プログラムのチェック」を押し、{0} を含む更新を「すべてインストール」してください。' -f $m.TargetVersion)
            Log 'NEXT: ドライバーなど多数の更新が同時に入ります。終わったら「今すぐ再起動」で再起動し、もう一度 Kitting-Update.cmd を管理者として実行してください。'
            Log ('NEXT: {0} が表示されない場合は、記録して止めてください（自動では再試行しません）。' -f $m.TargetVersion)
            try { Start-Process 'ms-settings:windowsupdate' } catch { Log '設定画面を自動で開けませんでした。スタート →「設定」→「Windows Update」を開いてください。' }
            exit 12
        }
        'DONE' {
            Set-TargetReleasePolicy $PolicyKey $m.TargetVersion
            Log ('DONE: {0}（ビルド {1}.{2}）に到達しました。' -f $m.TargetVersion, $build, $ubr)
            exit 0
        }
    }
} catch {
    $msg = 'STOP: ' + $_.Exception.Message
    if ($script:LogPath) { try { Log $msg } catch { Write-Host $msg } } else { Write-Host $msg }
    Write-Host '自動で再実行しないでください。'
    exit 1
}
