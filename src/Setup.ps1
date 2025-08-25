#requires -Version 7
#requires -RunAsAdministrator

# =================================================================================
# Main Orchestration Script for Windows Server 2025 Deployment
# =================================================================================

# --- 初期設定とログ記録 ---
$LogFile = "C:\Windows\Temp\DeploymentLog.txt"
function Write-Log {
    param(
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = " $Message"
    Add-Content -Path $LogFile -Value $LogMessage
    Write-Host $LogMessage
}

try {
    Write-Log "--- Deployment Script Started ---"

    # スクリプトとモジュールのパスを定義
    $ScriptRoot = $PSScriptRoot
    $ModulesPath = Join-Path -Path $ScriptRoot -ChildPath "Modules"
    $ConfigPath = Join-Path -Path $ScriptRoot -ChildPath "Config"
    $InstallersPath = Join-Path -Path $ScriptRoot -ChildPath "Installers"

    # 必要なモジュールをインポート
    Import-Module (Join-Path -Path $ModulesPath -ChildPath "SystemConfiguration.psm1")
    Import-Module (Join-Path -Path $ModulesPath -ChildPath "SoftwareManagement.psm1")
    Import-Module (Join-Path -Path $ModulesPath -ChildPath "DriverManagement.psm1")
    Import-Module (Join-Path -Path $ModulesPath -ChildPath "UserEnvironment.psm1")

    # --- フェーズ1: プレドメイン構成 ---
    Write-Log "--- Phase 1: Pre-Domain Configuration ---"
    Set-CustomComputerName -BaseName "KR-PC" -IsChiseki $false # 地籍端末の場合は $true に変更
    Disable-FastStartup

    # --- フェーズ2: INET系ネットワークとソフトウェアインストール ---
    Write-Log "--- Phase 2: INET Network and Software Installation ---"
    # 注意: IPアドレス、ゲートウェイ、DNSは環境に合わせて別紙参照の値を設定してください
    Set-StaticIPAddress -InterfaceAlias "イーサネット" -IpAddress "172.17.1.10" -PrefixLength 24 -Gateway "172.17.1.1"
    Set-DnsServers -InterfaceAlias "イーサネット" -DnsServers "172.17.0.1", "172.17.0.2"
    Set-SystemProxy -ProxyServer "172.17.0.3:12080" -BypassLocal $false

    Write-Log "Starting Windows Update..."
    # (Windows Updateを実行するコードをここに実装)
    
    Write-Log "Starting Software Removal..."
    Remove-UnwantedApps -AppsToRemove "Microsoft Teams", "Microsoft Whiteboard", "HP Wolf Security", "HP Quick Drop"

    Write-Log "Starting Software Installation..."
    Install-AllSoftware -InstallersPath $InstallersPath
    
    # Officeライセンス認証 (プロダクトキーは安全な方法で管理・取得すること)
    # Invoke-OfficeActivation -ProductKey "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"

    # --- フェーズ3: 情報系ネットワークとドメイン統合 ---
    Write-Log "--- Phase 3: Internal Network and Domain Integration ---"
    # 注意: IPアドレス、ゲートウェイ、DNSは環境に合わせて別紙参照の値を設定してください
    Set-StaticIPAddress -InterfaceAlias "イーサネット" -IpAddress "103.100.1.50" -PrefixLength 24 -Gateway "103.100.1.1"
    Set-DnsServers -InterfaceAlias "イーサネット" -DnsServers "103.100.1.10", "103.100.1.11"
    Set-SystemProxy -ProxyServer "103.100.1.15:12080" -BypassLocal $true
    
    # ADオブジェクトを移動
    Move-ADComputerObjectToTargetOU -TargetOU "OU=forWindows10,DC=KATSURAGI,DC=local"

    # --- フェーズ4: ユーザー環境設定と最終処理 ---
    Write-Log "--- Phase 4: User Environment and Finalization ---"
    # setupユーザーと最終ユーザーを作成
    New-SetupUser -Username "setup" -Password "123456"
    # New-FinalUser -Username "kr12345" # 実際の職員番号で作成

    # UIカスタマイズ
    Apply-DefaultAppAssociations -XmlPath (Join-Path -Path $ConfigPath -ChildPath "DefaultAppAssociations.xml")
    Apply-TaskbarLayout -XmlPath (Join-Path -Path $ConfigPath -ChildPath "LayoutModification.xml")
    Set-SystemUI -Screensaver "Ribbons.scr" -ScreensaverTimeout 20
    Configure-OfficeApps
    Disable-OneDriveStartup

    # --- クリーンアップと再起動 ---
    Write-Log "--- Finalizing Setup ---"
    Disable-AutoLogon
    Write-Log "Deployment complete. Restarting computer in 30 seconds."
    Start-Sleep -Seconds 30
    Restart-Computer -Force

} catch {
    Write-Log "!!! An error occurred during deployment: $_"
    # エラー発生時にスクリプトを停止させる
    exit 1
} finally {
    Write-Log "--- Deployment Script Finished ---"
}