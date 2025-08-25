$vhdPath = "C:\Kitting_Factory\MockServer.vhdx"
$vhdInfo = Get-VHD -Path $vhdPath -ErrorAction SilentlyContinue

if ($vhdInfo) {
    if ($vhdInfo.Attached) {
        if ($vhdInfo.VMId) {
            $vm = Get-VM -Id $vhdInfo.VMId
            Write-Host "VHDX is attached to VM: $($vm.VMName) (State: $($vm.State))"
        } else {
            Write-Host "VHDX is mounted to the Host OS."
        }
    } else {
        Write-Host "VHDX is not currently attached or mounted."
    }
} else {
    Write-Host "VHDX file not found or is inaccessible."
}