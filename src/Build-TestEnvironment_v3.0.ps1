#================================================================================
# ゼロタッチ検証環境 構築・更新スクリプト (Build-TestEnvironment.ps1)
# (改訂版 v3 - OS展開プロセスの堅牢性を向上)
#================================================================================

# --- 設定項目 ---
$FactoryPath = $PSScriptRoot
$SourcePath = Join-Path -Path $FactoryPath -ChildPath "Source"
$ServerIsoName = "26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_ja-jp.iso"
$ClientIsoName = "26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_ja-jp.iso"
$ServerImageName = "Windows Server 2025 Datacenter Evaluation (デスクトップ エクスペリエンス)"

# --- ヘルパー関数 ---
function Write-Status {
    param([string]$Message, [string]$Status)
    $ColorMap = @{"OK"="Green"; "SKIPPED"="Yellow"; "CREATED"="Cyan"; "CONFIGURED"="Cyan"; "INFO"="White"; "ACTION"="Magenta"; "ERROR"="Red"}
    $Color = if ($ColorMap.ContainsKey($Status)) { $ColorMap[$Status] } else { "White" }
    Write-Host ("[{0}] - {1}" -f $Status.ToUpper(), $Message) -ForegroundColor $Color
}

#================================================================================
# --- 実行本体 ---
#================================================================================
Write-Host "================================================="
Write-Host "  検証環境の構築・更新チェックを開始します..."
Write-Host "================================================="
Write-Host ""

# (--- 0. 前提条件のチェック --- と --- 1. 仮想スイッチの構成 --- は変更なし)

# --- 2. MockServerのチェックと作成 ---
Write-Host "--- 2. MockServer の構成 ---"
$isoMount = $null
try {
    if (-not (Get-VM -Name "MockServer" -ErrorAction SilentlyContinue)) {
        Write-Status "'MockServer' を新規作成します..." "INFO"
        $vmMockServer = New-VM -Name "MockServer" -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "$FactoryPath\MockServer.vhdx" -NewVHDSizeBytes 80GB -SwitchName "vSwitch-LGWAN"
        Add-VMNetworkAdapter -VMName "MockServer" -SwitchName "vSwitch-Internet"
        Set-VMKeyProtector -VMName "MockServer" -NewLocalKeyProtector
        Enable-VMTPM -VMName "MockServer"
        Set-VMFirmware -VMName "MockServer" -EnableSecureBoot On
        Write-Status "仮想マシン 'MockServer' を作成しました。" "CREATED"

        Write-Host "  - OSイメージを展開中... (時間がかかります)"
        # VHDをマウントし、ディスクオブジェクトを取得
        $vhd = Mount-VHD -Path "$FactoryPath\MockServer.vhdx" -Passthru | Get-Disk
        if (-not $vhd) { throw "VHDのマウントに失敗しました。" }

        # ディスクを初期化し、パーティションを作成・フォーマット
        $vhd | Initialize-Disk -Passthru -PartitionStyle GPT
        $osPartition = $vhd | New-Partition -AssignDriveLetter -UseMaximumSize
        if (-not $osPartition) { throw "パーティションの作成に失敗しました。" }
        
        # ★★★ ここからが重要な修正点 ★★★
        # OSがドライブレターを確実に認識するまで少し待機し、変数を確実に取得する
        Start-Sleep -Seconds 5
        $osDriveLetter = (Get-Partition -DiskNumber $vhd.Number | Where-Object { $_.Type -eq 'Basic' }).DriveLetter
        if (-not $osDriveLetter) { throw "ドライブレターの取得に失敗しました。" }
        Format-Volume -DriveLetter $osDriveLetter -FileSystem NTFS -Confirm:$false
        Write-Status "VHDXの準備が完了しました。ドライブレター: $osDriveLetter" "OK"
        # ★★★ ここまでが重要な修正点 ★★★

        # ISOイメージをマウントし、WIM情報を取得
        $isoMount = Mount-DiskImage -ImagePath "$SourcePath\$ServerIsoName" -Passthru
        if (-not $isoMount) { throw "ISOイメージのマウントに失敗しました。" }
        $wimPath = Join-Path -Path ($isoMount | Get-Volume).DriveLetter -ChildPath "sources\install.wim"
        $wim = Get-WindowsImage -ImagePath $wimPath -Name $ServerImageName
        if (-not $wim) { throw "指定されたOSイメージ '$ServerImageName' がISO内に見つかりません。" }

        # OSイメージを展開
        Expand-WindowsImage -ImagePath $wim.ImagePath -ImageIndex $wim.ImageIndex -ApplyPath ($osDriveLetter + ":\")

        # 無人応答ファイルなどをコピー
        Write-Host "  - 無人応答ファイルと設定スクリプトをコピー中..."
        $pantherPath = Join-Path -Path ($osDriveLetter + ":") -ChildPath "Windows\Panther"
        $sourcePathInVHD = Join-Path -Path ($osDriveLetter + ":") -ChildPath "Source"
        New-Item -Path $pantherPath -ItemType Directory -Force
        Copy-Item -Path "$FactoryPath\autounattend.xml" -Destination $pantherPath
        New-Item -Path $sourcePathInVHD -ItemType Directory
        Copy-Item -Path "$FactoryPath\Setup-MockServer.ps1" -Destination $sourcePathInVHD
        Copy-Item -Path "$SourcePath\*" -Destination $sourcePathInVHD -Recurse

        Write-Host "  - VHDXをアンマウント中..."
        Dismount-VHD -Path "$FactoryPath\MockServer.vhdx"
        Dismount-DiskImage -ImagePath "$SourcePath\$ServerIsoName"
        $isoMount = $null
        Write-Status "OSイメージの展開が完了しました。" "OK"
    } else {
        Write-Status "仮想マシン 'MockServer' はすでに存在します。OS展開はスキップします。" "SKIPPED"
    }
}
catch {
    # エラーメッセージをより詳細に表示するよう改善
    Write-Status "MockServerの構築中にエラーが発生しました: $($_.Exception.Message)" "ERROR"
}
finally {
    # エラーが発生してもISOがマウントされたままにならないようにクリーンアップ
    if ($isoMount) {
        Dismount-DiskImage -ImagePath "$SourcePath\$ServerIsoName"
    }
}
Write-Host ""

# (--- 3. Test-PC の構成 --- 以降は変更なし)
# ...