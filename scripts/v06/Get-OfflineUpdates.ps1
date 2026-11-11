#Requires -Version 5.1
<#
Kitting Factory v0.6 - 当月の累積更新（.msu）をMicrosoft Updateカタログから取得し、照合して一覧を作る。
管理者権限は不要。インターネットに出られる任意のWindows PCで実行できる（本庁など）。

  取得して照合:    powershell -NoProfile -ExecutionPolicy Bypass -File Get-OfflineUpdates.ps1 -Destination E:\Updates\LCU
  照合だけ:        ... -Destination E:\Updates\LCU -VerifyOnly   （ブラウザーで手動ダウンロードした場合）

保存先はNTFSまたはexFATにすること（KB5134133は4GBを超えるためFAT32には保存できない）。
保存先フォルダーには.msu以外を置かない（DISMが同じフォルダーのチェックポイント更新を自動で探すため）。
毎月の更新時は $Files を新しいKBのURLに差し替える（カタログの「ダウンロード」で表示されるURL）。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [switch]$VerifyOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 2026-11 累積更新 KB5132061（2026-11-10、24H2/25H2/26H2共通、x64、UBR 9974）と前提のチェックポイント KB5043080
# 旧：2026-10 KB5134133（UBR 9725）。URLはカタログのダウンロード画面で表示されるもの（24H2と26H2の項目で同じファイル）。
$Files = @(
    @{ KB = 'KB5043080'; Kind = 'Checkpoint'; Url = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/d8b7f92b-bd35-4b4c-96e5-46ce984b31e0/public/windows11.0-kb5043080-x64_953449672073f8fb99badb4cc6d5d7849b9c83e8.msu' }
    @{ KB = 'KB5132061'; Kind = 'Target'; ExpectedBuild = 9974; Url = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/5775e69a-9a06-44b1-9b51-4bb89c81f212/public/windows11.0-kb5132061-x64_aedc878e9e078df2ec7e2cfb98dd5b21831cdbcc.msu' }
)

function Get-NameSha1([string]$name) {
    # カタログの.msuはファイル名末尾の16進40文字がファイルのSHA-1
    $m = [regex]::Match($name, '_([0-9a-f]{40})\.msu$')
    if (-not $m.Success) { throw ('ファイル名からSHA-1を読めません: ' + $name) }
    return $m.Groups[1].Value.ToUpperInvariant()
}

if (-not (Test-Path -LiteralPath $Destination)) {
    if ($VerifyOnly) { throw ('保存先がありません: ' + $Destination) }
    [void](New-Item -ItemType Directory -Path $Destination)
}
$fs = (Get-Item -LiteralPath $Destination).PSDrive
$vol = Get-Volume -DriveLetter $fs.Name -ErrorAction SilentlyContinue
if ($vol -and $vol.FileSystem -eq 'FAT32') { throw 'STOP: 保存先がFAT32です。4GBを超えるファイルを保存できません。NTFSかexFATを使ってください。' }
$others = @(Get-ChildItem -LiteralPath $Destination -Force | Where-Object { $_.Name -notlike '*.msu' })
if ($others.Count) { throw ('STOP: 保存先に.msu以外のファイルがあります: ' + (($others | ForEach-Object Name) -join ', ')) }

$entries = foreach ($f in $Files) {
    $name = [IO.Path]::GetFileName(([uri]$f.Url).AbsolutePath)
    $path = Join-Path $Destination $name
    $sha1 = Get-NameSha1 $name
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash -eq $sha1)
    if (-not $ok) {
        if ($VerifyOnly) { throw ('STOP: ファイルがないか、壊れています: ' + $name) }
        if (Test-Path -LiteralPath $path) { throw ('STOP: 既存ファイルのハッシュが一致しません。削除してから再実行してください: ' + $name) }
        Write-Host ('ダウンロード中: {0}（数分〜数十分かかることがあります）' -f $name)
        Start-BitsTransfer -Source $f.Url -Destination $path -DisplayName ('KittingFactory ' + $f.KB)
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash -ne $sha1) { throw ('STOP: ダウンロードしたファイルのSHA-1が一致しません: ' + $name) }
    }
    Write-Host ('OK: {0}' -f $name)
    [ordered]@{
        KB = $f.KB; Kind = $f.Kind; File = $name; Length = (Get-Item -LiteralPath $path).Length
        SHA1 = $sha1; SHA256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        ExpectedBuild = $(if ($f.ContainsKey('ExpectedBuild')) { $f.ExpectedBuild } else { $null })
    }
}
$manifest = [ordered]@{ Schema = 1; TargetVersion = '26H2'; CreatedUtc = [DateTime]::UtcNow.ToString('o'); Files = @($entries) }
# 一覧は.msuのフォルダーではなく1つ上に置く（.msuのフォルダーには他のファイルを置かない）
$manifestPath = Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Destination).ProviderPath) 'updates-manifest.json'
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Write-Host ('PASS: {0}ファイルを照合し、{1} を作成しました。' -f @($entries).Count, $manifestPath)
