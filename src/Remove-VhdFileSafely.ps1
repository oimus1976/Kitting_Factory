function Remove-VhdFileSafely {
   
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [string]$Path
    )

    process {
        try {
            # VHDXファイルの存在を確認
            if (-not (Test-Path -Path $Path -PathType Leaf)) {
                throw "File not found or is not a file: $Path"
            }

            Write-Verbose "Analyzing VHDX file: $Path"
            $vhdInfo = Get-VHD -Path $Path -ErrorAction Stop

            # VMに接続されているか確認
            if ($vhdInfo.VMId) {
                $vm = Get-VM -Id $vhdInfo.VMId -ErrorAction SilentlyContinue
                if ($vm) {
                    Write-Warning "VHDX is attached to VM '$($vm.VMName)' (State: $($vm.State))."
                    if ($vm.State -ne 'Off') {
                        if ($PSCmdlet.ShouldProcess($vm.VMName, "Stop VM to release VHDX lock")) {
                            Write-Verbose "Stopping VM: $($vm.VMName)"
                            Stop-VM -VM $vm -Force -ErrorAction Stop
                        } else {
                            throw "Cannot proceed while VM is running."
                        }
                    }
                } else {
                    Write-Warning "VHDX is associated with a missing VM (ID: $($vhdInfo.VMId)). Consider advanced cleanup (Section 3)."
                    # ここで孤立したvmwp.exeを強制終了するロジックを追加することも可能
                }
            }
            # ホストOSにマウントされているか確認
            elseif ($vhdInfo.Attached) {
                if ($PSCmdlet.ShouldProcess($Path, "Dismount VHD from Host OS")) {
                    Write-Verbose "Dismounting VHDX from host: $Path"
                    Dismount-VHD -Path $Path -ErrorAction Stop
                } else {
                    throw "Cannot proceed while VHDX is mounted to host."
                }
            }

            # ファイルの削除
            if ($PSCmdlet.ShouldProcess($Path, "Delete VHDX file")) {
                Write-Verbose "Deleting file: $Path"
                Remove-Item -Path $Path -Force -ErrorAction Stop
                Write-Host "Successfully deleted VHDX file: $Path"
            }

        }
        catch {
            Write-Error "Failed to safely remove VHDX file '$Path'. Reason: $_"
        }
    }
}