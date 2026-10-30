#Requires -Version 5.1
<# No VM access or credentials. Exercises only collector helpers on synthetic data. #>
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'Collect-GuestEvidence.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Collector parse failed.' }
$helpers=@('Write-NewPrivateText','Write-NewPrivateJson','Assert-PrivateACL','Set-PrivateFileACL','New-PrivateEvidenceRoot','Get-TaskAbsenceAssessment')
foreach ($name in $helpers) {
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if ($null -eq $function) { throw 'Missing helper.' }
    . ([scriptblock]::Create($function.Extent.Text))
}
$log="Stage passed. KittingFactory state should now be WAIT_INET.`r`nFirst-logon task unregistered after successful Stage.`r`n"
$cases=@(
    @{Present=$false;Match=$true;Stage='WAIT_INET';Log=$log;Expected='NORMAL_SELF_REMOVAL_SUPPORTED'},
    @{Present=$true;Match=$true;Stage='WAIT_INET';Log=$log;Expected='TASK_PRESENT'},
    @{Present=$false;Match=$false;Stage='WAIT_INET';Log=$log;Expected='UNDETERMINED'},
    @{Present=$false;Match=$true;Stage='WAIT_NETWORK';Log=$log;Expected='UNDETERMINED'},
    @{Present=$false;Match=$true;Stage='WAIT_INET';Log='';Expected='UNDETERMINED'},
    @{Present=$false;Match=$true;Stage='WAIT_INET';Log=($log+'STOP: synthetic failure');Expected='UNDETERMINED'},
    @{Present=$false;Match=$true;Stage='WAIT_INET';Log='First-logon task unregistered after successful Stage.';Expected='UNDETERMINED'}
)
foreach ($case in $cases) {
    $r=Get-TaskAbsenceAssessment $case.Present $case.Match $case.Stage $case.Log
    if ($r.Reason -ne $case.Expected) { throw 'Task assessment test failed.' }
}
$root=Join-Path $env:TEMP ('KF-CollectorValidation-'+[guid]::NewGuid().ToString('N'))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$dir=New-PrivateEvidenceRoot $root $sid
$path=Join-Path $dir 'synthetic.json'
Write-NewPrivateJson $path ([ordered]@{Synthetic=$true;Value='readback'})
if ((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).Value -ne 'readback') { throw 'JSON readback failed.' }
$arrayPath=Join-Path $dir 'array.json'
Write-NewPrivateJson $arrayPath @([pscustomobject]@{Index=1},[pscustomobject]@{Index=2})
$array=Get-Content -LiteralPath $arrayPath -Raw -Encoding UTF8 | ConvertFrom-Json
$array=@($array)
if ($array.Count -ne 2 -or $array[1].Index -ne 2) { throw 'PS5.1 manifest array readback failed.' }
Assert-PrivateACL $path $sid
Set-PrivateFileACL $path $sid
$hash=(Get-FileHash -LiteralPath $path).Hash
$refused=$false
try { Write-NewPrivateText $path 'overwrite' } catch { $refused=$true }
if (-not $refused -or (Get-FileHash -LiteralPath $path).Hash -ne $hash) { throw 'File overwrite guard failed.' }
$refused=$false
try { [void](New-PrivateEvidenceRoot $root $sid) } catch { $refused=$true }
if (-not $refused) { throw 'Existing-directory guard failed.' }
$refused=$false
try { [void](New-PrivateEvidenceRoot (Join-Path $PSScriptRoot 'not-created-evidence') $sid) } catch { $refused=$true }
if (-not $refused) { throw 'Git-worktree destination guard failed.' }
$snapshot=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$ReadGuestSnapshot'},$true)
$allowed=@('Set-StrictMode','Get-Item','Get-Content','Get-FileHash','Get-Acl','Get-ScheduledTask','Get-ScheduledTaskInfo','Export-ScheduledTask','Where-Object','Select-Object','ConvertFrom-Json','Join-Path','Test-Path','Assert-PlainPath')
foreach ($command in $snapshot.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)) {
    if ($command.GetCommandName() -notin $allowed) { throw 'Unexpected guest command.' }
}
Write-Output 'COLLECTOR_LOCAL_TEST=PASS: 5.1 parse, seven conservative task assessments, restricted ACL/readback, no-overwrite/Git-root guards, guest read-only command allowlist'
Write-Output 'NOT TESTED: authenticated PowerShell Direct, Copy-Item transfer, actual guest data. Synthetic fixture retained in protected TEMP directory.'
