#Requires -Version 5.1
<# Isolated CMD control-flow checks. Never executes the original core or Stage. #>
[CmdletBinding()]
param([string]$TestRoot)
$ErrorActionPreference='Stop'
if (-not $TestRoot) { $TestRoot=Join-Path $PSScriptRoot ('..\..\local-v05\entry-tests-'+[guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $TestRoot) { throw 'Test destination exists.' }
[void](New-Item -ItemType Directory -Path $TestRoot)
$results=@()
foreach ($case in @('missing','reject-update','return-code','fallback','no-log')) {
  $dir=Join-Path $TestRoot ($case+' space & path')
  [void](New-Item -ItemType Directory -Path $dir)
  $entry=Join-Path $dir 'OOBE-Bridge.cmd'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'OOBE-Bridge.cmd') -Destination $entry
  $programData=Join-Path $dir 'programdata'
  $systemDrive=Join-Path $dir 'systemdrive'
  [void](New-Item -ItemType Directory -Path $programData,$systemDrive)
  $expected=91; $argument='VMEVAL'
  if ($case -eq 'reject-update') { $expected=93; $argument='AUTOUPDATE' }
  if ($case -eq 'return-code') {
    $expected=7
    [IO.File]::WriteAllText((Join-Path $dir 'OOBE-Bridge-Core-v04.cmd'), "@echo off`r`nexit /b 7`r`n",[Text.Encoding]::ASCII)
    foreach ($file in @('OOBE-Bridge.ps1','After-First-Logon.ps1','Start-Kitting.ps1','Update-Worker.ps1')) {
      [IO.File]::WriteAllText((Join-Path $dir $file),'# Inert test file; never invoked.',[Text.Encoding]::ASCII)
    }
  }
  if ($case -in @('fallback','no-log')) {
    [IO.File]::WriteAllText((Join-Path $programData 'KF-v05-Probe'),'block directory creation')
  }
  if ($case -eq 'no-log') {
    $expected=90
    [void](New-Item -ItemType Directory -Path (Join-Path $systemDrive 'KF-v05-entry-fallback.log'))
  }
  $si=New-Object Diagnostics.ProcessStartInfo
  $si.FileName=$env:ComSpec
  $si.Arguments='/d /c ""'+$entry+'" '+$argument+'"'
  $si.WorkingDirectory=$dir
  $si.UseShellExecute=$false; $si.CreateNoWindow=$true
  $si.RedirectStandardOutput=$true; $si.RedirectStandardError=$true
  $si.EnvironmentVariables['ProgramData']=$programData
  $si.EnvironmentVariables['SystemDrive']=$systemDrive
  $p=[Diagnostics.Process]::Start($si)
  $stdout=$p.StandardOutput.ReadToEnd(); $stderr=$p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if ($p.ExitCode -ne $expected) { throw "$case exit=$($p.ExitCode), expected=$expected; stderr=$stderr" }
  if ($stdout -or $stderr) { throw "$case produced console output: $stdout $stderr" }
  $log=Join-Path $programData 'KF-v05-Probe\devicecontext.log'
  if ($case -eq 'fallback') { $log=Join-Path $systemDrive 'KF-v05-entry-fallback.log' }
  if ($case -ne 'no-log') {
    $text=Get-Content -LiteralPath $log -Raw
    if ($text -notmatch "EXIT_CODE=$expected" -or $text -notmatch 'entry END') { throw "$case log incomplete" }
  }
  $results += [pscustomobject]@{Case=$case;ExitCode=$p.ExitCode;Silent=$true;Result='PASS'}
  $p.Dispose()
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $TestRoot 'results.json') -Encoding UTF8
$results | Format-Table -AutoSize
Write-Output "ENTRY_TEST=PASS; evidence=$TestRoot"
