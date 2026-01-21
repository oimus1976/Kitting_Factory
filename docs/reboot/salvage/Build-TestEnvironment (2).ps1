#================================================================================
# ゼロタッチ検証環境 構築・更新スクリプト (Build-TestEnvironment.ps1)
# (改訂版 - 互換性と堅牢性を向上)
#================================================================================

# --- 設定項目 ---
$FactoryPath = $PSScriptRoot # スクリプトが置かれているフォルダを自動的に取得
$SourcePath = Join-Path -Path $FactoryPath -ChildPath "Source"
$ServerIsoName = "17763.3650.221105-1748.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso" # Sourceフォルダ内の正しいファイル名に修正してください
$ClientIsoName = "26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso"         # Sourceフォルダ内の正しいファイル名に修正してください

# --- ヘルパー関数 (結果を色付きで表示) ---
function Write-Status {
    param(
        [string]$Message,
        [string]$Status
    )
    $ColorMap = @{
        "OK"         = "Green"
        "SKIPPED"    = "Yellow"
        "CREATED"    = "Cyan"
        "CONFIGURED" = "Cyan"
        "INFO"       = "White"
        "ACTION"     = "Magenta"
        "ERROR"      = "Red"
    }
    $Color = $ColorMap[$Status]
    if (-not $Color) { $Color = "White" }
    Write-Host ("[{0}] - {1}" -f $Status.ToUpper(), $Message) -ForegroundColor $Color
}

#================================================================================
# --- 実行本体 ---
#================================================================================
Write-Host "================================================="
Write-Host "  検証環境の構築・更新チェックを開始します..."
Write-Host "================================================="
Write-Host ""

# --- 0. 前提条件のチェック ---
Write-Host "--- 0. 前提条件のチェック ---"
$requiredFiles = @(
    (Join-Path -Path $SourcePath -ChildPath $ServerIsoName),
    (Join-Path -Path $SourcePath -ChildPath $ClientIsoName),
    (Join-Path -Path $FactoryPath -ChildPath "autounattend.xml"),
    (Join-Path -Path $FactoryPath -ChildPath "Setup-MockServer.ps1")
)
$filesMissing = $false
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -Path $file)) {
        Write-Status "必須ファイルが見つかりません: $file" "ERROR"
        $filesMissing = $true
    }
}
if ($filesMissing) {
    Write-Status "必要なファイルが不足しているため、処理を中断します。Sourceフォルダとファイル名を確認してください。" "ERROR"
    exit 1
}
Write-Status "すべての必須ファイルが存在します。" "OK"
Write-Host ""


# --- 1. 仮想スイッチのチェックと作成 ---
Write-Host "--- 1. 仮想スイッチの構成 ---"
if (-not (Get-VMSwitch -Name "vSwitch-Internet" -ErrorAction SilentlyContinue)) {
    $physAdapter = Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -First 1
    New-VMSwitch -Name "vSwitch-Internet" -NetAdapterName $physAdapter.Name -AllowManagementOS $true
    Write-Status "仮想スイッチ 'vSwitch-Internet' を作成しました。" "CREATED"
} else {
    Write-Status "仮想スイッチ 'vSwitch-Internet' はすでに存在します。" "OK"
}

if (-not (Get-VMSwitch -Name "vSwitch-LGWAN" -ErrorAction SilentlyContinue)) {
    New-VMSwitch -Name "vSwitch-LGWAN" -SwitchType Private
    Write-Status "仮想スイッチ 'vSwitch-LGWAN' を作成しました。" "CREATED"
} else {
    Write-Status "仮想スイッチ 'vSwitch-LGWAN' はすでに存在します。" "OK"
}
Write-Host ""

# --- 2. MockServerのチェックと作成 ---
Write-Host "--- 2. MockServer の構成 ---"
if (-not (Get-VM -Name "MockServer" -ErrorAction SilentlyContinue)) {
    Write-Status "'MockServer' を新規作成します..." "INFO"
    if (Test-Path "$FactoryPath\MockServer.vhdx") {
        $vmMockServer = New-VM -Name "MockServer" -MemoryStartupBytes 4GB -Generation 2 -VHDPath "$FactoryPath\MockServer.vhdx"
    } else {
        $vmMockServer = New-VM -Name "MockServer" -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "$FactoryPath\MockServer.vhdx" -NewVHDSizeBytes 80GB
    }
    Add-VMNetworkAdapter -VMName "MockServer" -SwitchName "vSwitch-Internet"
    #Set-VMNetworkAdapter -VMName "MockServer" -Name "ネットワーク アダプター" -SwitchName "vSwitch-LGWAN"
    Add-VMNetworkAdapter -VMName "MockServer" -SwitchName "vSwitch-LGWAN"
#    # SecurityType のチェック
#    if (Get-Command Set-VMSecurity -ParameterName SecurityType -ErrorAction SilentlyContinue) {
#        Set-VMSecurity -VMName "MockServer" -SecurityType Standard
#    } else {
#        Write-Host "SecurityType パラメーターはこの環境ではサポートされていません。スキップします。"
#    }
#
#    # EnableShielding のチェック
#    if (Get-Command Set-VMSecurity -ParameterName EnableShielding -ErrorAction SilentlyContinue) {
#        Set-VMSecurity -VMName "MockServer" -EnableShielding $false
#    } else {
#        Write-Host "EnableShielding パラメーターはこの環境ではサポートされていません。スキップします。"
#    }

    # 1. セキュリティタイプを Shielded に設定
    Set-VMSecurity -VMName "MockServer" -SecurityType Shielded

    # 2. Key Protector を作成して仮想マシンに割り当て
    $kp = New-VMKeyProtector -VMName "MockServer" -AllowUntrustedRoot
    Set-VMKeyProtector -VMName "MockServer" -KeyProtector $kp
    
    # 3. TPM を有効化
    Enable-VMTPM -VMName "MockServer"

    Set-VMFirmware -VMName "MockServer" -EnableSecureBoot On
    Write-Status "仮想マシン 'MockServer' を作成しました。" "CREATED"

    # --- OSイメージの展開 (新規作成時のみ実行) ---
    Write-Host "  - OSイメージを展開中... (時間がかかります)"
    $vhd = Mount-VHD -Path "$FactoryPath\MockServer.vhdx" -Passthru | Get-Disk | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false | Initialize-Disk -Passthru -PartitionStyle GPT
    $osPartition = $vhd | New-Partition -AssignDriveLetter -UseMaximumSize
    $osPartition | Format-Volume -FileSystem NTFS -Confirm:$false
    $osDriveLetter = $osPartition.DriveLetter

    $isoMount = Mount-DiskImage -ImagePath "$SourcePath\$ServerIsoName" -Passthru
    $wim = Get-WindowsImage -ImagePath (($isoMount | Get-Volume).DriveLetter + ":\sources\install.wim") -Name "Windows Server 2022 SERVERDATACENTER"
    Expand-WindowsImage -ImagePath $wim.ImagePath -ImageIndex $wim.ImageIndex -ApplyPath ($osDriveLetter + ":\")

    Write-Host "  - 無人応答ファイルと設定スクリプトをコピー中..."
    New-Item -Path ($osDriveLetter + ":\Windows\Panther") -ItemType Directory -Force
    Copy-Item -Path "$FactoryPath\autounattend.xml" -Destination ($osDriveLetter + ":\Windows\Panther\unattend.xml")
    New-Item -Path ($osDriveLetter + ":\Source") -ItemType Directory
    Copy-Item -Path "$FactoryPath\Setup-MockServer.ps1" -Destination ($osDriveLetter + ":\Source\")
    Copy-Item -Path "$SourcePath\*" -Destination ($osDriveLetter + ":\Source\") -Recurse

    Write-Host "  - VHDXをアンマウント中..."
    Dismount-VHD -Path "$FactoryPath\MockServer.vhdx"
    Dismount-DiskImage -ImagePath "$SourcePath\$ServerIsoName"
    Write-Status "OSイメージの展開が完了しました。" "OK"
} else {
    Write-Status "仮想マシン 'MockServer' はすでに存在します。OS展開はスキップします。" "SKIPPED"
}
Write-Host ""

# --- 3. Test-PCのチェックと作成 ---
Write-Host "--- 3. Test-PC の構成 ---"
if (-not (Get-VM -Name "Test-PC" -ErrorAction SilentlyContinue)) {
    Write-Status "'Test-PC' を新規作成します..." "INFO"
    #New-VM -Name "Test-PC" -MemoryStartupBytes 4GB -Generation 2 -VHDPath "$FactoryPath\Test-PC.vhdx" -NewVHDSizeBytes 80GB
    if (Test-Path "$FactoryPath\Test-PC.vhdx") {
        $vmMockServer = New-VM -Name "Test-PC" -MemoryStartupBytes 4GB -Generation 2 -VHDPath "$FactoryPath\Test-PC.vhdx"
    } else {
        $vmMockServer = New-VM -Name "Test-PC" -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "$FactoryPath\Test-PC.vhdx" -NewVHDSizeBytes 80GB
    }
    #Set-VMNetworkAdapter -VMName "Test-PC" -Name "ネットワーク アダプター" -SwitchName "vSwitch-Internet"
    Add-VMNetworkAdapter -VMName "Test-PC" -SwitchName "vSwitch-Internet"
    Add-VMDvdDrive -VMName "Test-PC" -Path "$SourcePath\$ClientIsoName"
    Write-Status "仮想マシン 'Test-PC' を作成しました。" "CREATED"
    Write-Status ">>> 'Test-PC'を起動して手動でOSをインストールし、OOBE画面でシャットダウン後、チェックポイントを作成してください <<<" "ACTION"
} else {
    Write-Status "仮想マシン 'Test-PC' はすでに存在します。" "OK"
}

# --- 4. Test-PCのWindows 11要件設定を検証・修正 ---
$vmTestPC = Get-VM -Name "Test-PC"
if ($vmTestPC.ProcessorCount -ne 2) {
    Set-VMProcessor -VMName "Test-PC" -Count 2
    Write-Status "'Test-PC' の仮想プロセッサ数を2に設定しました。" "CONFIGURED"
} else {
    Write-Status "'Test-PC' の仮想プロセッサ数は要件を満たしています。" "OK"
}

$vmSecurity = Get-VMSecurity -VMName "Test-PC"
if (-not $vmSecurity.TpmEnabled) {
    # Hyper-Vホストのバージョンに応じて適切なコマンドで標準セキュリティを設定
    $cmd = Get-Command Set-VMSecurity
    if ($cmd.Parameters.ContainsKey('SecurityType')) {
        # 新しい構文 (Windows Server 2022 / Windows 11など)
        Set-VMSecurity -VMName "Test-PC" -SecurityType Standard
    }
    else {
        # 古い構文 (Windows Server 2019 / Windows 10など)
        Set-VMSecurity -VMName "Test-PC" -EnableShielding $false
    }
    Enable-VMTPM -VMName "Test-PC"
    Write-Status "'Test-PC' の仮想TPMを有効化しました。" "CONFIGURED"
} else {
    Write-Status "'Test-PC' の仮想TPMは有効です。" "OK"
}

$vmFirmware = Get-VMFirmware -VMName "Test-PC"
if ($vmFirmware.SecureBoot -ne "On") {
    Set-VMFirmware -VMName "Test-PC" -EnableSecureBoot On
    Write-Status "'Test-PC' のセキュアブートを有効化しました。" "CONFIGURED"
} else {
    Write-Status "'Test-PC' のセキュアブートは有効です。" "OK"
}
Write-Host ""

Write-Host "================================================="
Write-Host "  構築・更新チェックが完了しました。"
Write-Host "  'MockServer'を起動して初回セットアップを完了させてください。"
Write-Host "=================================================" -ForegroundColor Green