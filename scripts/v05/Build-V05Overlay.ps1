#Requires -Version 5.1
<#
.SYNOPSIS
 Creates an isolated v0.5 DeviceContext CommandFiles overlay from the original v0.4 ZIP.
.DESCRIPTION
 Never modifies the v0.4 source ZIP, existing WCD project, VM, checkpoints or media.
 Keeps v0.4 .ps1 bytes unchanged. Copies v0.4 OOBE-Bridge.cmd as
 OOBE-Bridge-Core-v04.cmd after removing ONLY an optional UTF-8 BOM.
 Requires exactly one copy of each of the five recorded v0.4 scripts.
#>
[CmdletBinding()]
param(
  [string] $SourceZip = (Join-Path $env:USERPROFILE 'Downloads\KittingController_OOBE_Bridge_v0.4_20261012.zip'),
  [string] $OutputRoot
)
$ErrorActionPreference = 'Stop'
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot '..\..\local-v05\release' }
$SourceZip = [IO.Path]::GetFullPath($SourceZip)
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$Wrapper = Join-Path $PSScriptRoot 'OOBE-Bridge.cmd'
if (-not (Test-Path -LiteralPath $SourceZip -PathType Leaf)) { throw "v0.4 source ZIP not found: $SourceZip" }
if (-not (Test-Path -LiteralPath $Wrapper -PathType Leaf)) { throw "Kit wrapper missing: $Wrapper" }
if (Test-Path -LiteralPath $OutputRoot) { throw "OutputRoot already exists; refusing to overwrite: $OutputRoot" }
$zipHashBefore = (Get-FileHash -LiteralPath $SourceZip -Algorithm SHA256).Hash
if ($zipHashBefore -ne 'FE4B6E8978764A72B0123A472E5F04493EBBE0E9AC5B098A60CD4E33587E425A') {
  throw 'Source ZIP differs from the v0.4 archive reviewed on 2026-10-26. Review before building.'
}
if ($OutputRoot.StartsWith(($SourceZip + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
  throw 'OutputRoot must not be inside the source archive path'
}
$scriptNames = @(
  'OOBE-Bridge.cmd', 'OOBE-Bridge.ps1', 'After-First-Logon.ps1',
  'Start-Kitting.ps1', 'Update-Worker.ps1'
)
$extractDir = Join-Path $OutputRoot 'Source-v04-extracted-LOCAL-ONLY'
$assetsDir = Join-Path $OutputRoot 'WCD-CommandFiles-v05'
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
try {
  Expand-Archive -LiteralPath $SourceZip -DestinationPath $extractDir -ErrorAction Stop
  $found = @{}
  foreach ($name in $scriptNames) {
    $matches = @(Get-ChildItem -LiteralPath $extractDir -Recurse -File |
      Where-Object { $_.Name -ieq $name })
    if ($matches.Count -ne 1) {
      throw "Expected exactly one '$name' in source ZIP; found $($matches.Count). Stop for manual review."
    }
    $found[$name] = $matches[0]
  }
  # The five files must be colocated after WCD deployment, so copy into a flat dir.
  New-Item -ItemType Directory -Path $assetsDir | Out-Null
  $baseline = [ordered]@{}
  foreach ($name in $scriptNames) {
    $baseline[$name] = (Get-FileHash -LiteralPath $found[$name].FullName -Algorithm SHA256).Hash
  }
  foreach ($name in $scriptNames | Where-Object { $_ -like '*.ps1' }) {
    Copy-Item -LiteralPath $found[$name].FullName -Destination (Join-Path $assetsDir $name)
    $after = (Get-FileHash -LiteralPath (Join-Path $assetsDir $name) -Algorithm SHA256).Hash
    if ($after -ne $baseline[$name]) { throw "Hash mismatch for untouched Stage file: $name" }
  }
  [byte[]] $cmdBytes = [IO.File]::ReadAllBytes($found['OOBE-Bridge.cmd'].FullName)
  if ($cmdBytes.Length -lt 4) { throw 'Original bridge CMD is unexpectedly short.' }
  $hadBom = ($cmdBytes[0] -eq 0xEF -and $cmdBytes[1] -eq 0xBB -and $cmdBytes[2] -eq 0xBF)
  [byte[]] $coreBytes = $cmdBytes
  if ($hadBom) { $coreBytes = [byte[]] $cmdBytes[3..($cmdBytes.Length - 1)] }
  $corePath = Join-Path $assetsDir 'OOBE-Bridge-Core-v04.cmd'
  [IO.File]::WriteAllBytes($corePath, $coreBytes)
  Copy-Item -LiteralPath $Wrapper -Destination (Join-Path $assetsDir 'OOBE-Bridge.cmd')
  [byte[]] $newCmdBytes = [IO.File]::ReadAllBytes((Join-Path $assetsDir 'OOBE-Bridge.cmd'))
  if ($newCmdBytes.Length -lt 10 -or $newCmdBytes[0] -ne 0x40 -or $newCmdBytes[1] -ne 0x65) {
    throw 'New wrapper does not start with ASCII @e as required.'
  }
  if ($coreBytes.Length -ge 3 -and $coreBytes[0] -eq 0xEF -and $coreBytes[1] -eq 0xBB -and $coreBytes[2] -eq 0xBF) {
    throw 'Core still contains UTF-8 BOM.'
  }
  # A bare 'exit' kills cmd.exe rather than returning to the wrapper: warn, do not guess.
  $cmdText = [Text.Encoding]::UTF8.GetString($coreBytes)
  $bareExit = [regex]::IsMatch($cmdText, '(?im)^\s*@?exit\s*(?:&.*)?$')
  $manifest = [ordered]@{
    version = 'v0.5-diagnostic-overlay'; created_utc = [DateTime]::UtcNow.ToString('o')
    original_zip = $SourceZip
    original_zip_sha256 = (Get-FileHash -LiteralPath $SourceZip -Algorithm SHA256).Hash
    original_file_sha256 = $baseline
    bom_removed_from_v04_cmd = $hadBom
    possible_bare_exit_in_v04_cmd = $bareExit
    commandline = 'cmd /c OOBE-Bridge.cmd VMEVAL'
    new_commandfiles = @('OOBE-Bridge.cmd','OOBE-Bridge-Core-v04.cmd',
      'OOBE-Bridge.ps1','After-First-Logon.ps1','Start-Kitting.ps1','Update-Worker.ps1')
    output_file_sha256 = [ordered]@{}
  }
  if ($manifest.original_zip_sha256 -ne $zipHashBefore) { throw 'Source ZIP changed during assembly.' }
  foreach ($file in Get-ChildItem -LiteralPath $assetsDir -File) {
    $manifest.output_file_sha256[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
  }
  $manifestPath = Join-Path $OutputRoot 'v05-build-manifest.json'
  $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
  Write-Host 'BUILD_OVERLAY=PASS (static file assembly only; NOT a PPKG test)'
  Write-Host "WCD_ASSETS=$assetsDir"
  Write-Host "SOURCE_ZIP_SHA256=$($manifest.original_zip_sha256)"
  Write-Host "BOM_REMOVED=$hadBom"
  if ($bareExit) { Write-Warning "Original v0.4 CMD may contain bare EXIT; wrapper END/EXIT_CODE log cannot be guaranteed. Inspect locally before use." }
  Write-Host 'Stage .ps1 SHA256 unchanged: 4/4'
  Write-Host 'WCD package must be rebuilt manually from its existing project, with 6 CommandFiles.'
} catch {
  Write-Error "v0.5 overlay build failed safely: $_"
  throw
}
