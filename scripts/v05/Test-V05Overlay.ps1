#Requires -Version 5.1
[CmdletBinding()]
param([string] $WorkRoot)
$ErrorActionPreference = 'Stop'
if (-not $WorkRoot) { $WorkRoot = Join-Path $PSScriptRoot '..\..\local-v05\release' }
$m = Get-Content -LiteralPath (Join-Path $WorkRoot 'v05-build-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$dir = Join-Path $WorkRoot 'WCD-CommandFiles-v05'
$expected = @('OOBE-Bridge.cmd','OOBE-Bridge-Core-v04.cmd','OOBE-Bridge.ps1','After-First-Logon.ps1','Start-Kitting.ps1','Update-Worker.ps1')
$actual = @(Get-ChildItem -LiteralPath $dir -File)
if ($actual.Count -ne 6) { throw 'Expected exactly six CommandFiles.' }
foreach ($name in $expected) {
  $path = Join-Path $dir $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing CommandFile: $name" }
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $m.output_file_sha256.$name) { throw "Output hash changed: $name" }
  if ($name -like '*.ps1') {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $m.original_file_sha256.$name) { throw "Stage changed: $name" }
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw "PowerShell parse errors in $name : $parseErrors" }
  } else {
    [byte[]]$b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 2 -or $b[0] -ne 0x40 -or $b[1] -ne 0x65) { throw "CMD must start with ASCII @e: $name" }
  }
}
# Reopen the archive; manifest baselines alone cannot prove provenance.
if (-not (Test-Path -LiteralPath $m.original_zip -PathType Leaf)) { throw 'Original ZIP unavailable; cannot verify provenance.' }
if ((Get-FileHash -LiteralPath $m.original_zip -Algorithm SHA256).Hash -ne $m.original_zip_sha256) { throw 'Original ZIP changed.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($m.original_zip)
try {
  foreach ($name in @('OOBE-Bridge.cmd','OOBE-Bridge.ps1','After-First-Logon.ps1','Start-Kitting.ps1','Update-Worker.ps1')) {
    $entries = @($zip.Entries | Where-Object { $_.Name -ieq $name })
    if ($entries.Count -ne 1) { throw "Ambiguous source: $name" }
    $stream=$entries[0].Open(); $mem=New-Object IO.MemoryStream
    try { $stream.CopyTo($mem); [byte[]]$bytes=$mem.ToArray() } finally { $stream.Dispose(); $mem.Dispose() }
    if ($name -eq 'OOBE-Bridge.cmd') {
      if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bytes=[byte[]]$bytes[3..($bytes.Length-1)] }
      $outputName='OOBE-Bridge-Core-v04.cmd'
    } else { $outputName=$name }
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
    if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $dir $outputName) -Algorithm SHA256).Hash) { throw "Archive/output mismatch: $name" }
  }
} finally { $zip.Dispose() }
if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'OOBE-Bridge.cmd') -Algorithm SHA256).Hash -ne $m.output_file_sha256.'OOBE-Bridge.cmd') { throw 'Build wrapper differs from reviewed wrapper.' }
Write-Output 'STATIC_TEST=PASS: 6 files; 4 original PS1 bytes + parse; core equals original minus BOM; wrapper + ZIP SHA256'
Write-Output 'NOT TESTED: PPKG build/extraction, DeviceContext automatic execution, OOBE, Stage runtime.'
