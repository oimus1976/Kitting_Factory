#Requires -Version 5.1
<#
Run ONCE in an elevated Windows PowerShell 5.1 host console.
PowerShell Direct reads only; Copy-Item writes only to a NEW host directory.
No guest staging files, task changes, VM lifecycle operations or cloud uploads.
Credentials stay in memory and are never included in files or console output.
#>
[CmdletBinding()]
param([string]$VMName='Test-PC',[string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$VerbosePreference='SilentlyContinue'
$DebugPreference='SilentlyContinue'
$ReviewedWorkerSHA256='5BB06BE78891C4250A05B8F647CB105AD5087C30B3AF66A2948AD992E15459BC'

function Write-NewPrivateText([string]$Path,[string]$Text) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Text)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
}
function Write-NewPrivateJson([string]$Path,$Value) {
    Write-NewPrivateText $Path ($Value | ConvertTo-Json -Depth 16)
}
function Assert-PrivateACL([string]$Path,[string]$OwnerSID) {
    $acl=Get-Acl -LiteralPath $Path
    $allowed=@($OwnerSID,'S-1-5-18','S-1-5-32-544')
    if ($acl.Owner -and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $allowed) { throw 'Unexpected owner.' }
    foreach ($ace in $acl.Access) {
        if ($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin $allowed) { throw 'Unexpected ACL access.' }
    }
}
function Set-PrivateFileACL([string]$Path,[string]$OwnerSID) {
    $security=New-Object Security.AccessControl.FileSecurity
    $security.SetAccessRuleProtection($true,$false)
    $security.SetOwner([Security.Principal.SecurityIdentifier]::new($OwnerSID))
    foreach ($sid in @($OwnerSID,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique) {
        [void]$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $security -ErrorAction Stop
    Assert-PrivateACL $Path $OwnerSID
}
function New-PrivateEvidenceRoot([string]$Path,[string]$OwnerSID) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -notmatch '^[A-Za-z]:\\' -or (Test-Path -LiteralPath $full)) { throw 'New local directory required.' }
    if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -ne 'Fixed') { throw 'Fixed local drive required.' }
    $parent=[IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Parent directory must already exist.' }
    $cursor=$parent
    while ($cursor) {
        if (Test-Path -LiteralPath (Join-Path $cursor '.git')) { throw 'Evidence must be outside every Git worktree.' }
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point destinations are not allowed.' }
        $parentInfo=[IO.Directory]::GetParent($cursor)
        if ($null -eq $parentInfo) { break }; $cursor=$parentInfo.FullName
    }
    foreach ($cloud in @($env:OneDrive,$env:OneDriveConsumer,$env:OneDriveCommercial,(Join-Path $env:USERPROFILE 'Dropbox'),(Join-Path $env:USERPROFILE 'GoogleDrive_Work'))) {
        if ($cloud -and ($full -ieq $cloud -or $full.StartsWith($cloud.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Cloud-synced destination is not allowed.' }
    }
    $security=New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true,$false)
    $security.SetOwner([Security.Principal.SecurityIdentifier]::new($OwnerSID))
    foreach ($sid in @($OwnerSID,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique) {
        $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        [void]$security.AddAccessRule($rule)
    }
    [void][IO.Directory]::CreateDirectory($full,$security)
    if (-not (Get-Acl -LiteralPath $full).AreAccessRulesProtected) { throw 'Root ACL inheritance was not disabled.' }
    Assert-PrivateACL $full $OwnerSID
    return $full
}
function Get-TaskAbsenceAssessment([bool]$Present,[bool]$WorkerMatches,[string]$Stage,[string]$LogText) {
    $passed=$LogText.LastIndexOf('Stage passed. KittingFactory state should now be WAIT_INET.',[StringComparison]::Ordinal)
    $removed=$LogText.LastIndexOf('First-logon task unregistered after successful Stage.',[StringComparison]::Ordinal)
    $stop=$LogText.LastIndexOf('STOP:',[StringComparison]::Ordinal)
    $reason='UNDETERMINED'
    if ($Present) { $reason='TASK_PRESENT' }
    elseif ($WorkerMatches -and $Stage -ceq 'WAIT_INET' -and $passed -ge 0 -and $removed -gt $passed -and $stop -lt $removed) { $reason='NORMAL_SELF_REMOVAL_SUPPORTED' }
    [pscustomobject]@{Reason=$reason;ReviewedWorkerMatches=$WorkerMatches;StagePassedLogOffset=$passed;SuccessfulUnregisterLogOffset=$removed;LastStopLogOffset=$stop;RegistrationFailureEstablished=$false}
}

# This block runs in the guest. It performs no writes or state-changing commands.
$ReadGuestSnapshot={
    Set-StrictMode -Version Latest
    $ErrorActionPreference='Stop'
    $guestIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($guestIdentity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Guest read requires an administrator token.' }
    function Assert-PlainPath([string]$Path) {
        $cursor=$Path
        while ($cursor) {
            if ((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse-point source rejected.' }
            $parentInfo=[IO.Directory]::GetParent($cursor)
            if ($null -eq $parentInfo) { break }; $cursor=$parentInfo.FullName
        }
    }
    $pd=$env:ProgramData
    $targets=@(
        @{Name='state.json';Relative='KittingFactory\state.json'},
        @{Name='oobe.log';Relative='KittingBridge\oobe.log'},
        @{Name='first-logon.log';Relative='KittingBridge\first-logon.log'},
        @{Name='After-First-Logon.ps1.txt';Relative='KittingBridge\After-First-Logon.ps1'},
        @{Name='controller.log';Relative='KittingFactory\logs\controller.log'},
        @{Name='stage-payload.robocopy.log';Relative='KittingFactory\logs\stage-payload.robocopy.log'},
        @{Name='v04-diagnostic-run.log';Relative='KF-v04-Diagnostic\run.log'}
    )
    $files=@(foreach ($target in $targets) {
        $p=Join-Path $pd $target.Relative
        if (-not (Test-Path -LiteralPath $p -ErrorAction Stop)) {
            [pscustomobject]@{Name=$target.Name;Path=$p;Exists=$false;Length=0;SHA256=$null;SDDL=$null}
            continue
        }
        Assert-PlainPath $p
        $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -gt 32MB) { throw 'Unexpected source type or size.' }
        $acl=Get-Acl -LiteralPath $p -ErrorAction Stop
        [pscustomobject]@{Name=$target.Name;Path=$p;Exists=$true;Length=$item.Length;SHA256=(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash;SDDL=$acl.Sddl}
    })
    $statePath=Join-Path $pd 'KittingFactory\state.json'
    $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($state.Schema -ne 1 -or $state.ComputerName -cne $env:COMPUTERNAME) { throw 'Unexpected state schema or computer identity.' }
    $props=@($state.BaselineHashes.PSObject.Properties)
    if ($props.Count -lt 1 -or $props.Count -gt 64) { throw 'Unexpected baseline hash count.' }
    $assetRoot=[IO.Path]::GetFullPath((Join-Path $pd 'KittingFactory\payload\ClientSoft')).TrimEnd('\')+'\'
    $assets=@(foreach ($prop in $props) {
        $relative=[string]$prop.Name
        if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|[:*?\x00]' -or [string]$prop.Value -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Unsafe baseline entry.' }
        $p=[IO.Path]::GetFullPath((Join-Path $assetRoot $relative))
        if (-not $p.StartsWith($assetRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Baseline path escapes payload.' }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction Stop)) { throw 'Baseline asset missing.' }
        Assert-PlainPath $p
        $current=(Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash
        [pscustomobject]@{RelativePath=$relative;ExpectedSHA256=[string]$prop.Value;CurrentSHA256=$current;MatchesBaseline=($current -ieq [string]$prop.Value);SDDL=(Get-Acl -LiteralPath $p -ErrorAction Stop).Sddl}
    })
    # A successful complete enumeration distinguishes absence from access failure.
    $registered=@(Get-ScheduledTask -ErrorAction Stop)
    $tasks=@(foreach ($name in @('KittingFactory-OOBE-FirstLogon','KF-v04-Diagnostic','KittingFactory-WindowsUpdate')) {
        $found=@($registered | Where-Object { $_.TaskName -ceq $name -and $_.TaskPath -ceq '\' })
        if ($found.Count -gt 1) { throw 'Duplicate task result.' }
        if ($found.Count -eq 0) {
            [pscustomobject]@{Name=$name;Present=$false;State=$null;XML=$null;Runtime=$null;Note='Absent after successful task enumeration; historical registration/result unavailable.'}
        } else {
            $info=Get-ScheduledTaskInfo -InputObject $found[0] -ErrorAction Stop
            [pscustomobject]@{Name=$name;Present=$true;State=$found[0].State.ToString();XML=(Export-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop);Runtime=($info | Select-Object LastRunTime,LastTaskResult,NextRunTime,NumberOfMissedRuns);Note=$null}
        }
    })
    [pscustomobject]@{CapturedUtc=[DateTime]::UtcNow.ToString('o');ComputerName=$env:COMPUTERNAME;Stage=[string]$state.Stage;Schema=$state.Schema;Files=$files;Assets=$assets;Tasks=$tasks;TaskQuerySucceeded=$true}
}

$session=$null; $credential=$null; $destination=$null; $phase='HOST_PRECHECK'
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use Windows PowerShell 5.1.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Use an elevated host console.' }
    $ownerSID=$identity.User.Value
    $vm=Get-VM -Name $VMName -ErrorAction Stop
    if ($vm.State.ToString() -ne 'Running') { throw 'VM must already be running; it will not be started.' }
    if (-not $OutputRoot) { $OutputRoot=Join-Path $env:USERPROFILE ('KittingEvidence-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)) }
    $destination=New-PrivateEvidenceRoot $OutputRoot $ownerSID
    $phase='AUTHENTICATION'
    $credential=Get-Credential -Message 'Enter the guest account for read-only Test-PC evidence collection. Credentials are not saved.'
    if ($null -eq $credential) { throw 'Credential entry cancelled.' }
    $session=New-PSSession -VMName $VMName -Credential $credential -ErrorAction Stop
    $credential=$null
    $phase='GUEST_READ_BEFORE'
    $before=Invoke-Command -Session $session -ScriptBlock $ReadGuestSnapshot -ErrorAction Stop
    Write-NewPrivateJson (Join-Path $destination 'guest-before.json') $before
    $phase='HOST_COPY'
    $copyDir=Join-Path $destination 'files'
    [void][IO.Directory]::CreateDirectory($copyDir)
    $copies=@(foreach ($file in $before.Files | Where-Object Exists) {
        $target=Join-Path $copyDir $file.Name
        if (Test-Path -LiteralPath $target) { throw 'Copy destination collision.' }
        Copy-Item -LiteralPath $file.Path -FromSession $session -Destination $target -ErrorAction Stop
        # Copy content only; never reproduce guest ACLs on host evidence.
        Set-PrivateFileACL $target $ownerSID
        $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -ne $file.SHA256 -or (Get-Item -LiteralPath $target).Length -ne $file.Length) { throw 'Source/copy mismatch.' }
        [pscustomobject]@{Name=$file.Name;SHA256=$hash;Length=$file.Length}
    })
    $phase='GUEST_READ_AFTER'
    $after=Invoke-Command -Session $session -ScriptBlock $ReadGuestSnapshot -ErrorAction Stop
    Write-NewPrivateJson (Join-Path $destination 'guest-after.json') $after
    foreach ($old in $before.Files) {
        $new=@($after.Files | Where-Object Name -ceq $old.Name)
        if ($new.Count -ne 1 -or $new[0].Exists -ne $old.Exists -or $new[0].SHA256 -ne $old.SHA256 -or $new[0].Length -ne $old.Length -or $new[0].SDDL -ne $old.SDDL) { throw 'Guest source changed during collection.' }
    }
    if ($before.Stage -cne $after.Stage -or ($before.Assets | ConvertTo-Json -Depth 6 -Compress) -cne ($after.Assets | ConvertTo-Json -Depth 6 -Compress) -or ($before.Tasks | ConvertTo-Json -Depth 8 -Compress) -cne ($after.Tasks | ConvertTo-Json -Depth 8 -Compress)) { throw 'Guest state/assets/tasks changed during collection.' }
    $phase='ASSESSMENT'
    $worker=@($copies | Where-Object Name -eq 'After-First-Logon.ps1.txt')
    $matches=($worker.Count -eq 1 -and $worker[0].SHA256 -eq $ReviewedWorkerSHA256)
    $logPath=Join-Path $copyDir 'first-logon.log'
    $logText=''
    if (Test-Path -LiteralPath $logPath -PathType Leaf) { $logText=[IO.File]::ReadAllText($logPath,[Text.Encoding]::UTF8) }
    $first=@($after.Tasks | Where-Object Name -eq 'KittingFactory-OOBE-FirstLogon')[0]
    $assessment=Get-TaskAbsenceAssessment ([bool]$first.Present) $matches $after.Stage $logText
    Write-NewPrivateJson (Join-Path $destination 'task-assessment.json') $assessment
    Write-NewPrivateJson (Join-Path $destination 'copy-verification.json') $copies
    $hostData=[ordered]@{VM=($vm | Select-Object Name,Id,@{n='State';e={$_.State.ToString()}},Status);Checkpoints=@(Get-VMSnapshot -VMName $VMName -ErrorAction Stop | Select-Object Name,Id,VMId,@{n='State';e={$_.State.ToString()}},Status,CreationTime,ParentSnapshotId);EvidenceRootSDDL=(Get-Acl -LiteralPath $destination).Sddl;ReviewedWorkerSHA256=$ReviewedWorkerSHA256;CollectorSHA256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash}
    Write-NewPrivateJson (Join-Path $destination 'host-metadata.json') $hostData
    $phase='VERIFY_LOCAL'
    foreach ($item in @(Get-Item -LiteralPath $destination)+@(Get-ChildItem -LiteralPath $destination -Recurse -Force)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Unexpected evidence reparse point.' }
        Assert-PrivateACL $item.FullName $ownerSID
    }
    $manifest=@(Get-ChildItem -LiteralPath $destination -File -Recurse | ForEach-Object { [pscustomobject]@{RelativePath=$_.FullName.Substring($destination.Length+1);Length=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    $manifestPath=Join-Path $destination 'SHA256-manifest.json'
    Write-NewPrivateJson $manifestPath $manifest
    # Windows PowerShell 5.1 emits a JSON array as one pipeline object.
    $readback=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $readback=@($readback)
    if ($readback.Count -ne $manifest.Count) { throw 'Manifest readback mismatch.' }
    foreach ($entry in $readback) {
        $p=Join-Path $destination $entry.RelativePath
        if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $entry.SHA256 -or (Get-Item -LiteralPath $p).Length -ne $entry.Length) { throw 'Evidence readback mismatch.' }
    }
    $baselineOK=(@($after.Assets | Where-Object { -not $_.MatchesBaseline }).Count -eq 0)
    $requiredOK=(@($copies | Where-Object Name -in @('state.json','oobe.log','first-logon.log','After-First-Logon.ps1.txt')).Count -eq 4)
    $status='PASS'
    if (-not $baselineOK -or -not $requiredOK) { $status='FAIL' }
    $receipt=[ordered]@{Collection=$status;Stage=$after.Stage;TaskAbsenceReason=$assessment.Reason;SourceCopySHA256Match=$true;SourceStableAcrossCollection=$true;ACLVerified=$true;ReadbackVerified=$true;BaselineHashesMatch=$baselineOK;RequiredEvidencePresent=$requiredOK;VerifiedFileCount=$readback.Count;ManifestSHA256=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash;RestoreApprovalReady=($status -eq 'PASS' -and $after.Stage -ceq 'WAIT_INET' -and $assessment.Reason -eq 'NORMAL_SELF_REMOVAL_SUPPORTED');CollectedUtc=[DateTime]::UtcNow.ToString('o')}
    $receiptPath=Join-Path $destination 'verification-receipt.json'
    Write-NewPrivateJson $receiptPath $receipt
    Assert-PrivateACL $receiptPath $ownerSID
    $r=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($r.ManifestSHA256 -ne $receipt.ManifestSHA256 -or $r.Collection -ne $status) { throw 'Receipt readback mismatch.' }
    $receiptHash=(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash
    $checksumPath=Join-Path $destination 'verification-receipt.sha256.txt'
    Write-NewPrivateText $checksumPath ($receiptHash+'  verification-receipt.json')
    Assert-PrivateACL $checksumPath $ownerSID
    if ([IO.File]::ReadAllText($checksumPath) -cne ($receiptHash+'  verification-receipt.json') -or (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash -ne $receiptHash) { throw 'Receipt checksum readback mismatch.' }
    # Deliberately emit only non-sensitive status codes, never log/state contents.
    $safeStage='OTHER'
    if ($after.Stage -cmatch '^(WAIT_INET|WAIT_NETWORK|UPDATE_READY|UPDATE_RUNNING|UPDATE_REBOOT_PENDING|UPDATE_REVIEW|NETWORK_CONFIRMED|VENDOR_REVIEW|MANUAL_REVIEW)$') { $safeStage=$after.Stage }
    Write-Output ('EVIDENCE='+$status)
    Write-Output ('STAGE='+$safeStage)
    Write-Output ('FIRST_LOGON_TASK='+$assessment.Reason)
    Write-Output ('RESTORE_APPROVAL_READY='+$receipt.RestoreApprovalReady)
    Write-Output ('LOCAL_OUTPUT='+$destination)
    if ($status -ne 'PASS') { exit 1 }
} catch {
    # Never serialize ErrorRecord/InvocationInfo: bound arguments could be sensitive.
    if ($destination -and (Test-Path -LiteralPath $destination -PathType Container)) {
        try { Write-NewPrivateJson (Join-Path $destination 'collection-failed.json') ([ordered]@{Collection='FAIL';Phase=$phase;Detail='Inspect locally. No exception/credential data was logged.';CollectedUtc=[DateTime]::UtcNow.ToString('o')}) } catch {}
    }
    Write-Output 'EVIDENCE=FAIL'
    Write-Output ('FAILED_PHASE='+$phase)
    if ($destination) { Write-Output ('LOCAL_OUTPUT='+$destination) }
    exit 1
} finally {
    if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    $credential=$null
}
