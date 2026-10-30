#Requires -Version 5.1
<# Read an existing collection only. Write a verification receipt to a NEW sibling.
 No credentials, guest connection, source writes, VM operations or cloud transfer. #>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=$null; $phase='PRECHECK'
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell 5.1 required.' }
    $EvidenceRoot=[IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw 'Evidence not available.' }
    # Load only reviewed pure/local helpers, never the collector's executable body.
    $collector=Join-Path $PSScriptRoot 'Collect-GuestEvidence.ps1'
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($collector,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Collector parse failed.' }
    foreach ($name in @('Write-NewPrivateText','Write-NewPrivateJson','Assert-PrivateACL','New-PrivateEvidenceRoot','Get-TaskAbsenceAssessment')) {
        $fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        if ($null -eq $fn) { throw 'Missing verification helper.' }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $phase='SOURCE_ACL'
    foreach ($i in @(Get-Item -LiteralPath $EvidenceRoot)+@(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -Force)) {
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source reparse point rejected.' }
        Assert-PrivateACL $i.FullName $sid
    }
    $sourceFiles=@(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File)
    $initial=@($sourceFiles | ForEach-Object { [pscustomobject]@{RelativePath=$_.FullName.Substring($EvidenceRoot.Length+1);Length=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
    $phase='MANIFEST'
    $manifestPath=Join-Path $EvidenceRoot 'SHA256-manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest=@($manifest)
    if ($manifest.Count -lt 1) { throw 'Empty manifest.' }
    foreach ($entry in $manifest) {
        $p=[IO.Path]::GetFullPath((Join-Path $EvidenceRoot $entry.RelativePath))
        if (-not $p.StartsWith($EvidenceRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe manifest path.' }
        if ((Get-FileHash -LiteralPath $p).Hash -ne $entry.SHA256 -or (Get-Item -LiteralPath $p).Length -ne $entry.Length) { throw 'Manifest mismatch.' }
    }
    $phase='CAPTURE_STABILITY'
    $before=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'guest-before.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $after=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'guest-after.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $state=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'files\state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($state.Schema -ne 1 -or $state.ComputerName -cne $before.ComputerName -or $state.Stage -cne $before.Stage -or $before.Stage -cne $after.Stage -or -not $before.TaskQuerySucceeded -or -not $after.TaskQuerySucceeded) { throw 'State or task query mismatch.' }
    foreach ($old in $before.Files) {
        $new=@($after.Files | Where-Object Name -ceq $old.Name)
        if ($new.Count -ne 1 -or $new[0].Exists -ne $old.Exists -or $new[0].SHA256 -ne $old.SHA256 -or $new[0].Length -ne $old.Length -or $new[0].SDDL -ne $old.SDDL) { throw 'Unstable source snapshot.' }
        if ($old.Exists) {
            $copy=Join-Path (Join-Path $EvidenceRoot 'files') $old.Name
            if ((Get-FileHash -LiteralPath $copy).Hash -ne $old.SHA256 -or (Get-Item -LiteralPath $copy).Length -ne $old.Length) { throw 'Source/copy mismatch.' }
        }
    }
    if (($before.Assets | ConvertTo-Json -Depth 6 -Compress) -cne ($after.Assets | ConvertTo-Json -Depth 6 -Compress) -or ($before.Tasks | ConvertTo-Json -Depth 8 -Compress) -cne ($after.Tasks | ConvertTo-Json -Depth 8 -Compress)) { throw 'Unstable assets/tasks.' }
    if (@($after.Assets).Count -lt 1 -or @($after.Assets | Where-Object { -not $_.MatchesBaseline -or $_.ExpectedSHA256 -ine $_.CurrentSHA256 }).Count) { throw 'Baseline mismatch.' }
    foreach ($name in @('state.json','oobe.log','first-logon.log','After-First-Logon.ps1.txt')) {
        if (@($after.Files | Where-Object { $_.Name -ceq $name -and $_.Exists }).Count -ne 1) { throw 'Required evidence missing.' }
    }
    $phase='ASSESSMENT'
    $worker=Join-Path $EvidenceRoot 'files\After-First-Logon.ps1.txt'
    $match=((Get-FileHash -LiteralPath $worker).Hash -eq '5BB06BE78891C4250A05B8F647CB105AD5087C30B3AF66A2948AD992E15459BC')
    $log=[IO.File]::ReadAllText((Join-Path $EvidenceRoot 'files\first-logon.log'),[Text.Encoding]::UTF8)
    $first=@($after.Tasks | Where-Object Name -eq 'KittingFactory-OOBE-FirstLogon')
    if ($first.Count -ne 1) { throw 'Invalid task snapshot.' }
    $assessment=Get-TaskAbsenceAssessment ([bool]$first[0].Present) $match $after.Stage $log
    $hostData=Get-Content -LiteralPath (Join-Path $EvidenceRoot 'host-metadata.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (@($hostData.Checkpoints | Where-Object Name -eq 'OOBE-Before-PPKG-20261019').Count -ne 1) { throw 'Checkpoint evidence missing.' }
    $phase='WRITE_NEW_RECEIPT'
    $candidate=Join-Path ([IO.Path]::GetDirectoryName($EvidenceRoot)) ('KittingEvidenceVerification-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    $output=New-PrivateEvidenceRoot $candidate $sid
    foreach ($entry in $initial) {
        $p=Join-Path $EvidenceRoot $entry.RelativePath
        if ((Get-FileHash -LiteralPath $p).Hash -ne $entry.SHA256 -or (Get-Item -LiteralPath $p).Length -ne $entry.Length) { throw 'Evidence changed during verification.' }
    }
    if (@(Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File).Count -ne $initial.Count) { throw 'Source inventory changed.' }
    Write-NewPrivateJson (Join-Path $output 'source-inventory.json') $initial
    $ready=($after.Stage -ceq 'WAIT_INET' -and $assessment.Reason -eq 'NORMAL_SELF_REMOVAL_SUPPORTED')
    $receipt=[ordered]@{Evidence='PASS';StageAtCapture=$after.Stage;TaskAbsenceReason=$assessment.Reason;TaskAssessment=$assessment;ACLVerified=$true;ManifestEntriesVerified=$manifest.Count;SourceCopyHashesVerified=$true;BaselineHashesVerified=$true;StableDuringCapture=$true;SourceUntouchedDuringVerification=$true;RestoreApprovalReady=$ready;SourceEvidenceRoot=$EvidenceRoot;SourceManifestSHA256=(Get-FileHash -LiteralPath $manifestPath).Hash;VerifierSHA256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;VerifiedUtc=[DateTime]::UtcNow.ToString('o');Limitation='Verifies the saved capture. No new guest connection or current-state claim. No checkpoint restore authorization.'}
    $receiptPath=Join-Path $output 'verification-receipt.json'
    Write-NewPrivateJson $receiptPath $receipt
    $r=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.Evidence -ne 'PASS' -or $r.SourceManifestSHA256 -ne $receipt.SourceManifestSHA256) { throw 'Receipt readback failed.' }
    $hashes=@(Get-ChildItem -LiteralPath $output -File | ForEach-Object { Assert-PrivateACL $_.FullName $sid; (Get-FileHash -LiteralPath $_.FullName).Hash+'  '+$_.Name }) -join "`r`n"
    $sums=Join-Path $output 'SHA256SUMS.txt'
    Write-NewPrivateText $sums $hashes
    Assert-PrivateACL $sums $sid
    if ([IO.File]::ReadAllText($sums) -cne $hashes) { throw 'Checksum readback failed.' }
    Write-Output 'EVIDENCE=PASS'
    $safeStage='OTHER'; if ($after.Stage -ceq 'WAIT_INET') { $safeStage='WAIT_INET' }
    Write-Output ('STAGE_AT_CAPTURE='+$safeStage)
    Write-Output ('FIRST_LOGON_TASK='+$assessment.Reason)
    Write-Output ('RESTORE_APPROVAL_READY='+$ready)
    Write-Output ('VERIFICATION_OUTPUT='+$output)
} catch {
    Write-Output 'EVIDENCE=FAIL'
    Write-Output ('FAILED_PHASE='+$phase)
    if ($output) { Write-Output ('VERIFICATION_OUTPUT='+$output) }
    exit 1
}
