#================================================================================
# 検証環境 健全性チェックプログラム (Verify-TestEnvironment.ps1)
# 説明: Build-TestEnvironment.ps1で構築した環境が正しいかを確認します。
# 実行方法: ホストPCで、PowerShellを管理者として実行し、このスクリプトを実行します。
#================================================================================

#--------------------------------------------------------------------------------
# 【設定項目】
#--------------------------------------------------------------------------------

# --- Verify 用 固定識別子 ---
# HostMgmt NIC は Build / Setup で静的MACが保証されている
$HostMgmtNicMacAddress = "00-15-5D-00-01-0C"

# MockServerのINET側IPアドレス（vSwitch-Internetに接続されている方）
# $MockServer_IP = "192.168.0.200" # 廃止: HostMgmt 経由に切替

# MockServerにログインするための管理者資格情報
# スクリプト実行時にパスワードの入力が求められます
$Credential = Get-Credential -UserName "$MockServer_IP\Administrator" -Message "MockServerのAdministratorパスワードを入力してください"

#--------------------------------------------------------------------------------
# ヘルパー関数 (チェック結果を色付きで表示)
#--------------------------------------------------------------------------------
function Write-CheckResult {
    param(
        [bool]$Condition,
        [string]$SuccessMessage,
        [string]$FailureMessage
    )
    if ($Condition) {
        Write-Host "[OK] - $SuccessMessage" -ForegroundColor Green
    } else {
        Write-Host "[NG] - $FailureMessage" -ForegroundColor Red
    }
}

#================================================================================
# --- チェック開始 ---
#================================================================================
Write-Host "================================================="
Write-Host "  検証環境 健全性チェックを開始します..."
Write-Host "================================================="
Write-Host ""

# --- 1. ホストPCレベルのチェック ---
Write-Host "--- 1. Hyper-V ホストの構成チェック ---"

# 仮想スイッチのチェック
$vSwitchInternet = Get-VMSwitch -Name "vSwitch-Internet" -ErrorAction SilentlyContinue
$vSwitchLgwan = Get-VMSwitch -Name "vSwitch-LGWAN" -ErrorAction SilentlyContinue
Write-CheckResult ($null -ne $vSwitchInternet) "仮想スイッチ 'vSwitch-Internet' が存在します。" "仮想スイッチ 'vSwitch-Internet' が見つかりません。"
Write-CheckResult ($vSwitchInternet.SwitchType -eq "External") "'vSwitch-Internet' は正しい種類 (外部) です。" "'vSwitch-Internet' の種類が不正です (外部であるべき)。"
Write-CheckResult ($null -ne $vSwitchLgwan) "仮想スイッチ 'vSwitch-LGWAN' が存在します。" "仮想スイッチ 'vSwitch-LGWAN' が見つかりません。"
Write-CheckResult ($vSwitchLgwan.SwitchType -eq "Private") "'vSwitch-LGWAN' は正しい種類 (プライベート) です。" "'vSwitch-LGWAN' の種類が不正です (プライベートであるべき)。"
Write-Host ""

# 仮想マシンのチェック
$vmMockServer = Get-VM -Name "MockServer" -ErrorAction SilentlyContinue
$vmTestPC = Get-VM -Name "Test-PC" -ErrorAction SilentlyContinue
Write-CheckResult ($null -ne $vmMockServer) "仮想マシン 'MockServer' が存在します。" "仮想マシン 'MockServer' が見つかりません。"
Write-CheckResult ($null -ne $vmTestPC) "仮想マシン 'Test-PC' が存在します。" "仮想マシン 'Test-PC' が見つかりません。"
Write-Host ""

# Test-PCのWindows 11要件チェック
Write-Host "--- 2. Test-PC のWindows 11要件チェック ---"
if ($vmTestPC) {
    Write-CheckResult ($vmTestPC.Generation -eq 2) "'Test-PC' は第2世代です。" "'Test-PC' が第1世代です (第2世代であるべき)。"
    Write-CheckResult ((Get-VMProcessor -VMName "Test-PC").Count -ge 2) "'Test-PC' の仮想プロセッサは2コア以上です。" "'Test-PC' の仮想プロセッサが1コアです (2コア以上であるべき)。"
    Write-CheckResult ((Get-VMSecurity -VMName "Test-PC").TpmEnabled) "'Test-PC' の仮想TPMは有効です。" "'Test-PC' の仮想TPMが無効です。"
    Write-CheckResult ((Get-VMFirmware -VMName "Test-PC").SecureBoot -eq "On") "'Test-PC' のセキュアブートは有効です。" "'Test-PC' のセキュアブートが無効です。"
} else {
    Write-Host "Test-PC が存在しないため、チェックをスキップします。" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "=== Verify 前提条件チェック ==="

# $MockServerIp = "192.168.0.200"
# Write-Host "[ASSUME] MockServer IP: $MockServerIp"

#
# Verify 前提条件チェック（確定仕様）
# - 接続先は vSwitch-HostMgmt の IPv4 のみ
# - 外部ネットワーク / DNS / IPv6 には依存しない
#

# --- HostMgmt インターフェースの IPv4 を取得 ---
$hostMgmtIp = Get-NetIPAddress `
    -InterfaceAlias "vEthernet (vSwitch-HostMgmt)" `
    -AddressFamily IPv4 `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $hostMgmtIp) {
    Write-Warning "[PRECONDITION NG] vSwitch-HostMgmt に IPv4 アドレスが割り当てられていません"
    Write-Warning "  - Host 側の Internal vSwitch 設定を確認してください"
    exit 1
}

Write-Host "[ASSUME] Verify Target Interface : vSwitch-HostMgmt"
Write-Host "[ASSUME] Verify Target IP        : $($hostMgmtIp.IPAddress)"

# --- Ping チェック（WinRM 以前の前提） ---
$pingOk = Test-Connection -ComputerName $hostMgmtIp.IPAddress -Count 1 -Quiet

if (-not $pingOk) {
    Write-Warning "[PRECONDITION NG] HostMgmt 経由で MockServer に Ping が届きません"
    Write-Warning "  - Host IP   : $($hostMgmtIp.IPAddress)"
    Write-Warning "  - これは WinRM 以前の問題です"
    exit 1
}

Write-Host "[OK] - HostMgmt 経由の Ping に成功しました"

# --- TCP 5985 (WinRM) チェック ---
$winrmTcp = Test-NetConnection -ComputerName $hostMgmtIp.IPAddress -Port 5985

if (-not $winrmTcp.TcpTestSucceeded) {
    Write-Warning "[PRECONDITION NG] TCP 5985 (WinRM) に接続できません"
    Write-Warning "  - 接続先 : $($hostMgmtIp.IPAddress)"
    Write-Warning "  - 確認事項:"
    Write-Warning "      * MockServer 側で WinRM が有効か"
    Write-Warning "      * NetworkProfile が Private / Domain か"
    Write-Warning "      * Firewall で TCP 5985 が許可されているか"
    exit 1
}

Write-Host "[OK] - TCP 5985 (WinRM) に接続可能です"

# --- L3 到達性チェック ---
$netProbe = Test-NetConnection $MockServerIp -Port 5985 -InformationLevel Detailed

Write-Host "[INFO] Host Source IP   : $($netProbe.SourceAddress)"
Write-Host "[INFO] InterfaceAlias  : $($netProbe.InterfaceAlias)"

if (-not $netProbe.PingSucceeded) {
    Write-Warning "[PRECONDITION NG] MockServer に Ping が届きません"
    Write-Warning "  - ホストIPとMockServer IPが同一セグメントか確認してください"
    $srcIp = ($netProbe.SourceAddress | Select-Object -ExpandProperty IPAddress -ErrorAction SilentlyContinue)
    Write-Host "[INFO] Host Source IP   : $srcIp"
    Write-Warning "  - MockServer IP : $MockServerIp"
    Write-Warning "  - これは WinRM 以前の問題です"
    return
}

if (-not $netProbe.TcpTestSucceeded) {
    Write-Warning "[PRECONDITION NG] TCP 5985 (WinRM) に接続できません"
    Write-Warning "  - MockServer 側で WinRM / FW / NetworkProfile を確認してください"
    return
}
Write-Host ""
Write-Host "[ASSUME] WinRM over HTTP (5985) を使用します"

$trustedHosts = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
if ($trustedHosts -notmatch [regex]::Escape($MockServerIp)) {
    Write-Warning "[PRECONDITION NG] TrustedHosts に $MockServerIp が登録されていません"
    Write-Warning "  実行例:"
    Write-Warning "  Set-Item WSMan:\localhost\Client\TrustedHosts -Value '$MockServerIp' -Force"
    return
}
Write-Host ""

# --- 2. MockServer内部のチェック ---
Write-Host "--- 3. MockServer 内部の構成チェック ---"
try {
    # Invoke-Commandを使ってMockServer内部でコマンドを実行
    $results = Invoke-Command -ComputerName $MockServer_IP -Credential $Credential -ScriptBlock {
        # 各チェック項目をハッシュテーブルに格納して返す
        $checks = @{}

        # ネットワーク設定のチェック
        $adapters = Get-NetAdapter
        $checks.AdapterCount = $adapters.Count
        $ipConfig = Get-NetIPConfiguration
        $checks.HasInetIP = $ipConfig.IPv4Address.IPAddress -contains "192.168.0.200"
        $checks.HasLgwanIP = $ipConfig.IPv4Address.IPAddress -contains "192.168.100.10"

        # 役割インストールのチェック
        $checks.ADDS_Installed = (Get-WindowsFeature -Name AD-Domain-Services).Installed
        $checks.FileServices_Installed = (Get-WindowsFeature -Name File-Services).Installed

        # ドメイン状態のチェック
        $checks.IsDomainController = (Get-ADDomainController -Discover -Service PrimaryDC -ErrorAction SilentlyContinue) -ne $null
        if ($checks.IsDomainController) {
            $checks.DomainName = (Get-ADDomain).NetBIOSName
        } else {
            $checks.DomainName = "N/A"
        }

        # 共有フォルダのチェック
        $checks.Share_PC_Kitting = (Get-SmbShare -Name "PC_Kitting" -ErrorAction SilentlyContinue) -ne $null
        $checks.Share_Installers = (Get-SmbShare -Name "Installers" -ErrorAction SilentlyContinue) -ne $null

        return $checks
    }

    # 返された結果を評価して表示
    Write-CheckResult ($results.AdapterCount -eq 2) "ネットワークアダプターが2つ存在します。" "ネットワークアダプターが2つではありません (現在: $($results.AdapterCount))。"
    Write-CheckResult ($results.HasInetIP) "INET側IPアドレス (192.168.0.200) が設定されています。" "INET側IPアドレス (192.168.0.200) が見つかりません。"
    Write-CheckResult ($results.HasLgwanIP) "LGWAN側IPアドレス (192.168.100.10) が設定されています。" "LGWAN側IPアドレス (192.168.100.10) が見つかりません。"
    Write-Host ""
    Write-CheckResult ($results.ADDS_Installed) "役割 'Active Directory ドメインサービス' はインストール済みです。" "役割 'Active Directory ドメインサービス' がインストールされていません。"
    Write-CheckResult ($results.FileServices_Installed) "役割 'ファイルサービス' はインストール済みです。" "役割 'ファイルサービス' がインストールされていません。"
    Write-Host ""
    Write-CheckResult ($results.IsDomainController) "サーバーはドメインコントローラーとして機能しています。" "サーバーはドメインコントローラーではありません。"
    Write-CheckResult ($results.DomainName -eq "KATSURAGI-TEST") "ドメイン名が 'katsuragi-test.local' に設定されています。" "ドメイン名が不正です (現在: $($results.DomainName))。"
    Write-Host ""
    Write-CheckResult ($results.Share_PC_Kitting) "共有フォルダ 'PC_Kitting' が存在します。" "共有フォルダ 'PC_Kitting' が見つかりません。"
    Write-CheckResult ($results.Share_Installers) "共有フォルダ 'Installers' が存在します。" "共有フォルダ 'Installers' が見つかりません。"

}
catch {
    Write-Host "[NG] - MockServerに接続できませんでした。以下の点を確認してください：" -ForegroundColor Red
    Write-Host "      - MockServer仮想マシンは起動していますか？" -ForegroundColor Red
    Write-Host "      - スクリプト冒頭のIPアドレス ($MockServer_IP) は正しいですか？" -ForegroundColor Red
    Write-Host "      - 入力したパスワードは正しいですか？" -ForegroundColor Red
    Write-Host "      - ホストPCとMockServerの間のネットワーク接続とファイアウォール設定を確認してください。" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================="
Write-Host "  チェックが完了しました。"
Write-Host "================================================="