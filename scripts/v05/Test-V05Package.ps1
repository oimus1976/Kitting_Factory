#Requires -Version 5.1
[CmdletBinding()]
param([string]$AuditRoot,[string]$WorkRoot)
$ErrorActionPreference='Stop'
if (-not $AuditRoot) { $AuditRoot=Join-Path $PSScriptRoot '..\..\local-v05\PPKG-audit-7zip-v05' }
if (-not $WorkRoot) { $WorkRoot=Join-Path $PSScriptRoot '..\..\local-v05\release' }
$m=Get-Content -LiteralPath (Join-Path $WorkRoot 'v05-build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$assets=@(Get-ChildItem -LiteralPath (Join-Path $AuditRoot 'DataAsset') -File -Recurse | Where-Object { $_.Extension -in @('.cmd','.ps1') })
if ($assets.Count -ne 6) { throw "Expected six embedded scripts; found $($assets.Count)" }
foreach ($name in $m.new_commandfiles) {
  $match=@($assets | Where-Object Name -eq $name)
  if ($match.Count -ne 1) { throw "Missing/duplicate embedded file: $name" }
  if ((Get-FileHash -LiteralPath $match[0].FullName -Algorithm SHA256).Hash -ne $m.output_file_sha256.$name) { throw "Embedded hash mismatch: $name" }
}
$runtime=Join-Path $AuditRoot 'Multivariant\0\Prov\RunTime'
$allParams=@(Get-ChildItem -LiteralPath $runtime -Filter '*.provxml' | ForEach-Object {
  [xml]$doc=Get-Content -LiteralPath $_.FullName -Raw
  $doc.SelectNodes('//parm')
})
$commands=@($allParams | Where-Object SettingsPath -eq 'ProvisioningCommands/DeviceContext/CommandLine')
if ($commands.Count -ne 1 -or $commands[0].value -cne 'cmd /c OOBE-Bridge.cmd VMEVAL') { throw 'Unexpected runtime CommandLine.' }
$mapped=@($allParams | Where-Object SettingsPath -eq 'ProvisioningCommands/DeviceContext/CommandFiles/CommandFile')
if ($mapped.Count -ne 6) { throw 'Expected six runtime file mappings.' }
foreach ($name in $m.new_commandfiles) {
  if (@($mapped | Where-Object value -eq $name).Count -ne 1) { throw "Runtime mapping missing/duplicate: $name" }
}
Write-Output 'PACKAGE_CONTENT_TEST=PASS: six embedded SHA256 hashes and six runtime mappings; VMEVAL CommandLine'
Write-Output 'Windows package export/import compatibility and automatic DeviceContext execution require guest acceptance.'
