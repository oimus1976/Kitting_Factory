#================================================================================
# ゼロタッチ検証環境 構築・更新スクリプト (Build-TestEnvironment.ps1)
# (Version 2.3 - ログ出力エラー修正版)
#================================================================================

# --- スクリプトパラメータ定義 ---
param (
    # このスイッチを指定すると、PowerShellの内部的な詳細メッセージも表示されます
    [switch]$DebugMode
)

# --- 設定項目 ---
$FactoryPath = $PSScriptRoot
$SourcePath = Join-Path -Path $FactoryPath -ChildPath "Source"
$ServerIsoName = "26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso"
$ClientIsoName = "26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso"
$ServerImageName = "Windows Server 2025 Datacenter Evaluation (デスクトップ エクスペリエンス)"

#================================================================================
# --- ヘルパー関数 ---
#================================================================================

function Write-StatusMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Status
    )

    $formattedMessage = "[{0}] - {1}" -f $Status.ToUpper(), $Message

    # エラーと警告は専用ストリームに送る
    if ($Status -eq 'ERROR') {
        Write-Error $formattedMessage
        return
    }
    if ($Status -eq 'ACTION') {
        Write-Warning $formattedMessage
        return
    }

    # 通常のメッセージは色付きでコンソールに表示
    $colorMap = @{
        "OK"         = "Green"
        "SKIPPED"    = "Yellow"
        "CREATED"    = "Cyan"
        "CONFIGURED" = "Cyan"
        "INFO"       = "White"
    }

    # 安全に色を取得し、キーが存在しない場合はデフォルトの色(White)を使用
    $color = if ($colorMap.ContainsKey($Status)) { $colorMap[$Status] } else { 'White' }

    Write-Host $formattedMessage -ForegroundColor $color
}

#================================================================================
# --- 実行本体 ---
#================================================================================

# DebugModeが指定された場合、詳細メッセージを有効化
if ($DebugMode) {
    $VerbosePreference = "Continue"
    Write-StatusMessage -Status "INFO" -Message "デバッグモードが有効です。詳細なログが出力されます。"
}

Write-Host "================================================="
Write-Host "  検証環境の構築・更新チェックを開始します..."
Write-Host "================================================="
Write-Host ""

# --- 0. 前提条件のチェック ---
Write-Host "--- 0. 前提条件のチェック ---"
try {
    $requiredFiles = @(
        (Join-Path -Path $SourcePath -ChildPath $ServerIsoName),
        (Join-Path -Path $SourcePath -ChildPath $ClientIsoName),
        (Join-Path -Path $FactoryPath -ChildPath "unattend.xml"),
        (Join-Path -Path $FactoryPath -ChildPath "Setup-MockServer.ps1")
        (Join-Path -Path $FactoryPath -ChildPath "config.ps1")
    )

    $missingFiles = $requiredFiles | Where-Object { -not (Test-Path -Path $_ -PathType Leaf) }

    if ($missingFiles) {
        $missingFiles | ForEach-Object {
            Write-StatusMessage -Status "ERROR" -Message "必須ファイルが見つかりません: $_"
        }
        throw "必要なファイルが不足しているため、処理を中断します。Sourceフォルダとファイル名を確認してください。"
    }

    Write-StatusMessage -Status "OK" -Message "すべての必須ファイルが存在します。"
}
catch {
    Write-Error $_
    pause
    exit 1
}
Write-Host ""


# --- 1. 仮想スイッチのチェックと作成 ---
Write-Host "--- 1. 仮想スイッチの構成 ---"
try {
    if (-not (Get-VMSwitch -Name "vSwitch-Internet" -ErrorAction SilentlyContinue)) {
        $physAdapter = Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' -and $_.ComponentID -ne 'ms_pacer' } | Sort-Object -Property Speed -Descending | Select-Object -First 1
        if (-not $physAdapter) {
            throw "有効な物理ネットワークアダプターが見つかりません。"
        }
        New-VMSwitch -Name "vSwitch-Internet" -NetAdapterName $physAdapter.Name -AllowManagementOS $true
        Write-StatusMessage -Status "CREATED" -Message "仮想スイッチ 'vSwitch-Internet' を作成しました。"
    } else {
        Write-StatusMessage -Status "OK" -Message "仮想スイッチ 'vSwitch-Internet' はすでに存在します。"
    }

    if (-not (Get-VMSwitch -Name "vSwitch-LGWAN" -ErrorAction SilentlyContinue)) {
        New-VMSwitch -Name "vSwitch-LGWAN" -SwitchType Private
        Write-StatusMessage -Status "CREATED" -Message "仮想スイッチ 'vSwitch-LGWAN' を作成しました。"
    } else {
        Write-StatusMessage -Status "OK" -Message "仮想スイッチ 'vSwitch-LGWAN' はすでに存在します。"
    }
}
catch {
    Write-Error "仮想スイッチの構成中にエラーが発生しました: $($_.ToString())"
    pause
    exit 1
}
Write-Host ""

# --- 2. MockServerのチェックと作成 ---
Write-Host "--- 2. MockServer の構成 ---"
$isoMount = $null
$vhdPath = Join-Path -Path $FactoryPath -ChildPath "MockServer.vhdx"
$vhdObject = $null

try {
    if (-not (Get-VM -Name "MockServer" -ErrorAction SilentlyContinue)) {
        Write-StatusMessage -Status "INFO" -Message "'MockServer' を新規作成します..."
        $vmMockServer = New-VM -Name "MockServer" -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes 80GB -SwitchName "vSwitch-LGWAN"
        Add-VMNetworkAdapter -VMName "MockServer" -SwitchName "vSwitch-Internet"
        Set-VMKeyProtector -VMName "MockServer" -NewLocalKeyProtector
        Enable-VMTPM -VMName "MockServer"
        Set-VMFirmware -VMName "MockServer" -EnableSecureBoot On
        # 仮想マシン名（例: MockServer）
        $vmName = "MockServer"

        # VMのハードディスクドライブがあれば先頭を取得、なければ $null
        $vmVhdList = Get-VMHardDiskDrive -VMName $vmName
        $vmVhd = if ($vmVhdList.Count -gt 0) { $vmVhdList } else { $null }

        # 同様にDVDドライブ
        $vmDvdList = Get-VMDvdDrive -VMName $vmName
        $vmDvd = if ($vmDvdList.Count -gt 0) { $vmDvdList } else { $null }

        # ネットワークアダプター
        $vmNicList = Get-VMNetworkAdapter -VMName $vmName
        $vmNic = if ($vmNicList.Count -gt 0) { $vmNicList } else { $null }

        # 有効なデバイスのみ配列で指定（nullは除外する）
        $bootDevices = @()
        if ($vmVhd) { $bootDevices += $vmVhd }
        if ($vmDvd) { $bootDevices += $vmDvd }
        if ($vmNic) { $bootDevices += $vmNic }

        # ブート順の設定
        if ($bootDevices.Count -gt 0) {
            Set-VMFirmware -VMName $vmName -BootOrder $bootDevices
            Write-Host "ブート順を仮想ハードディスク優先に変更しました。"
        } else {
            Write-Warning "対象のVMに設定可能なブートデバイスが見つかりません。"
        }

        Write-StatusMessage -Status "CREATED" -Message "仮想マシン 'MockServer' を作成しました。"

        Write-StatusMessage -Status "INFO" -Message "OSイメージを展開中... (時間がかかります)"
        $vhdObject = Mount-VHD -Path $vhdPath -Passthru
        $disk = $vhdObject | Get-Disk
        if (-not $disk) { throw "VHDのマウントまたはディスクオブジェクトの取得に失敗しました。" }

        # --- UEFIブート用のパーティション構成（予約 → EFI → リカバリ → OS）---
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru | Out-Null

        # 1) Microsoft予約パーティション (MSR) 16MB
        Write-StatusMessage -Status "INFO" -Message "  - Microsoft予約パーティションを作成中..."
        New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' | Out-Null

        # 2) EFIシステムパーティション 500MB
        Write-StatusMessage -Status "INFO" -Message "  - EFIシステムパーティションを作成中..."
        $efiPartition = New-Partition -DiskNumber $disk.Number -Size 500MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
        $efiDriveLetter = ($efiPartition | Get-Volume).DriveLetter
        if (-not $efiDriveLetter) {
            # 手動割り当て処理（必要なら）
            $efiPartition | Set-Partition -NewDriveLetter Z
            $efiDriveLetter = 'Z'
        }

        Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false | Out-Null

        # 3) 回復パーティション 1GB
        Write-StatusMessage -Status "INFO" -Message "  - 回復パーティションを作成中..."
        New-Partition -DiskNumber $disk.Number -Size 1GB -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' | Out-Null

        # 4) OSパーティション（残り全領域）
        Write-StatusMessage -Status "INFO" -Message "  - OSパーティションを作成中..."
        $osPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        $osDriveLetter = ($osPartition | Get-Volume).DriveLetter
        Format-Volume -Partition $osPartition -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null

        Start-Sleep -Seconds 3
        $osDriveLetter = $osPartition.DriveLetter
        if (-not $osDriveLetter) { throw "OSパーティションのドライブレター取得に失敗しました。" }
        Write-StatusMessage -Status "OK" -Message "VHDXの準備が完了しました。ドライブレター: $osDriveLetter"

        $serverIsoPath = Join-Path -Path $SourcePath -ChildPath $ServerIsoName
        $isoMount = Mount-DiskImage -ImagePath $serverIsoPath -PassThru
        if (-not $isoMount) { throw "ISOイメージのマウントに失敗しました。" }

        $isoDrive = Get-Volume -DiskImage $isoMount
        if (-not $isoDrive) { throw "マウントされたISOのボリューム情報を取得できませんでした。" }
        $wimPath = Join-Path -Path ($isoDrive.DriveLetter + ":") -ChildPath "sources\install.wim"
        if (-not (Test-Path $wimPath)) { throw "ISOマウント内に sources\install.wim が見つかりません。" }

        $wim = Get-WindowsImage -ImagePath $wimPath -Name $ServerImageName -ErrorAction Stop
        Expand-WindowsImage -ImagePath $wim.ImagePath -Index $wim.ImageIndex -ApplyPath ($osDriveLetter + ":\")

        # Windows を起動可能にする BCD を作成
        # bcdboot実行
        # 実行ファイルのフルパス（通常はこちら）
        $bcdbootExe = "$env:SystemRoot\System32\bcdboot.exe"

        # 起動パスと引数
        $bcdbootArgs = @("$($osDriveLetter):\Windows", "/s", "$($efiDriveLetter):", "/f", "UEFI")

        # bcdboot実行
        $bcdbootResult = Start-Process -FilePath $bcdbootExe -ArgumentList $bcdbootArgs -Wait -NoNewWindow -PassThru

        if ($bcdbootResult.ExitCode -ne 0) {
            # より詳細なエラー情報を取得するために例外をスローする
            throw "bcdboot.exe が失敗しました。コード: $($bcdbootResult.ExitCode)。OSイメージが破損しているか、パーティション構成に問題がある可能性があります。"
        } else {
            Write-StatusMessage -Status "OK" -Message "ブートファイル(BCD)の作成が完了しました。"
        }

        Write-StatusMessage -Status "INFO" -Message "無人応答ファイルと設定スクリプトをコピー中..."

        # ★★★ 修正点 ★★★
        # ファイル名を unattend.xml に変更し、コピー先を2か所に増やす
        $unattendFileName = "unattend.xml"
        $unattendSourcePath = Join-Path -Path $FactoryPath -ChildPath $unattendFileName

        # コピー先1: C:\Windows\Panther
        $pantherPath = Join-Path -Path ($osDriveLetter + ":") -ChildPath "Windows\Panther"
        $null = New-Item -Path $pantherPath -ItemType Directory -Force
        Copy-Item -Path $unattendSourcePath -Destination $pantherPath

        # コピー先2: C:\Windows\System32\Sysprep
        $sysprepPath = Join-Path -Path ($osDriveLetter + ":") -ChildPath "Windows\System32\Sysprep"
        $null = New-Item -Path $sysprepPath -ItemType Directory -Force
        Copy-Item -Path $unattendSourcePath -Destination $sysprepPath
        # ★★★ ここまで修正 ★★★

        $sourcePathInVHD = Join-Path -Path ($osDriveLetter + ":") -ChildPath "Source"
        $null = New-Item -Path $sourcePathInVHD -ItemType Directory -Force
        Copy-Item -Path (Join-Path -Path $FactoryPath -ChildPath "Setup-MockServer.ps1") -Destination $sourcePathInVHD
        Copy-Item -Path (Join-Path -Path $FactoryPath -ChildPath "config.ps1") -Destination $sourcePathInVHD
        Copy-Item -Path (Join-Path -Path $SourcePath -ChildPath "*") -Destination $sourcePathInVHD -Recurse -Force

        Write-StatusMessage -Status "INFO" -Message "VHDXをアンマウント中..."
        Dismount-VHD -Path $vhdPath
        $vhdObject = $null
        Dismount-DiskImage -ImagePath $serverIsoPath
        $isoMount = $null
        Write-StatusMessage -Status "OK" -Message "OSイメージの展開が完了しました。"
    } else {
        Write-StatusMessage -Status "SKIPPED" -Message "仮想マシン 'MockServer' はすでに存在します。OS展開はスキップします。"
    }
}
catch {
    Write-Error "MockServerの構築中にエラーが発生しました: $($_.ToString())"
    if ($_.ScriptStackTrace) {
        Write-Warning "スタックトレース: $($_.ScriptStackTrace)"
    }
    pause
    exit 1
}
finally {
    if ($vhdObject) {
        try {
            Write-Warning "クリーンアップ処理: VHDをアンマウントします..."
            Dismount-VHD -Path $vhdPath -ErrorAction Stop
        } catch {
            Write-Error "クリーンアップ中のVHDアンマウントに失敗しました: $($_.ToString())"
        }
    }
    if ($isoMount) {
        try {
            Write-Warning "クリーンアップ処理: ISOイメージをアンマウントします..."
            Dismount-DiskImage -ImagePath (Join-Path -Path $SourcePath -ChildPath $ServerIsoName) -ErrorAction Stop
        } catch {
            Write-Error "クリーンアップ中のISOアンマウントに失敗しました: $($_.ToString())"
        }
    }
}
Write-Host ""


# --- 3. Test-PCのチェックと作成 ---
Write-Host "--- 3. Test-PC の構成 ---"
try {
    $vmTestPC = Get-VM -Name "Test-PC" -ErrorAction SilentlyContinue
    if (-not $vmTestPC) {
        Write-StatusMessage -Status "INFO" -Message "'Test-PC' を新規作成します..."
        $clientIsoPath = Join-Path -Path $SourcePath -ChildPath $ClientIsoName
        $vmTestPC = New-VM -Name "Test-PC" -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath (Join-Path -Path $FactoryPath -ChildPath "Test-PC.vhdx") -NewVHDSizeBytes 80GB -SwitchName "vSwitch-Internet"
        Add-VMDvdDrive -VMName "Test-PC" -Path $clientIsoPath
        Write-StatusMessage -Status "CREATED" -Message "仮想マシン 'Test-PC' を作成しました。"
        Write-StatusMessage -Status "ACTION" -Message ">>> 'Test-PC'を起動して手動でOSをインストールし、OOBE画面でシャットダウン後、チェックポイントを作成してください <<<"
    } else {
        Write-StatusMessage -Status "OK" -Message "仮想マシン 'Test-PC' はすでに存在します。"
    }

    # --- 4. Test-PCのWindows 11要件設定を検証・修正 ---
    if ($vmTestPC.ProcessorCount -ne 2) {
        Set-VMProcessor -VM $vmTestPC -Count 2
        Write-StatusMessage -Status "CONFIGURED" -Message "'Test-PC' の仮想プロセッサ数を2に設定しました。"
    } else {
        Write-StatusMessage -Status "OK" -Message "'Test-PC' の仮想プロセッサ数は要件を満たしています。"
    }

    $vmSecurity = Get-VMSecurity -VM $vmTestPC
    if (-not $vmSecurity.TpmEnabled) {
        Set-VMKeyProtector -VM $vmTestPC -NewLocalKeyProtector
        Enable-VMTPM -VM $vmTestPC
        Write-StatusMessage -Status "CONFIGURED" -Message "'Test-PC' の仮想TPMを有効化しました。"
    } else {
        Write-StatusMessage -Status "OK" -Message "'Test-PC' の仮想TPMは有効です。"
    }

    $vmFirmware = Get-VMFirmware -VM $vmTestPC
    if ($vmFirmware.SecureBoot -ne "On") {
        Set-VMFirmware -VM $vmTestPC -EnableSecureBoot On
        Write-StatusMessage -Status "CONFIGURED" -Message "'Test-PC' のセキュアブートを有効化しました。"
    } else {
        Write-StatusMessage -Status "OK" -Message "'Test-PC' のセキュアブートは有効です。"
    }
}
catch {
    Write-Error "Test-PCの構成中にエラーが発生しました: $($_.ToString())"
    pause
    exit 1
}
Write-Host ""

Write-Host "=================================================" -ForegroundColor Green
Write-Host "  構築・更新チェックが完了しました。" -ForegroundColor Green
Write-Host "  'MockServer'を起動して初回セットアップを完了させてください。" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green