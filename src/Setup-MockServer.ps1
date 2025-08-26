<#
.SYNOPSIS
    設定ファイルに基づき、仮想テストサーバーのセットアップを完全に自動化します。(改訂版)
    Windowsのunattend.xmlから初回起動時に呼び出されることを想定しています。
.DESCRIPTION
    このスクリプトは、config.ps1 ファイルからすべての構成を読み込み、
    MACアドレスを使用してネットワークアダプターを決定論的に識別・設定することで、信頼性の高いゼロタッチ実行を実現します。
    処理は再起動を挟んで2つのフェーズで実行され、完了後には自己クリーンアップを行います。
#>

# --- グローバル変数と定数 ---
$LogPath = "C:\Setup-MockServer-Log.txt"
$ScheduledTaskName = "PostRebootADDSSetup"
$SourcePath = "C:\Source" # unattend.xmlから実行されるため、パスを固定

# --- ログ記録の開始 ---
# -Append をつけることで、再起動後に同じファイルに追記する
Start-Transcript -Path $LogPath -Append

# --- ヘルパー関数 ---
function Set-StaticIPConfiguration {

    param(
        [Parameter(Mandatory = $true)]
        [string]$MacAddress,

        [Parameter(Mandatory = $true)]
        [string]$IPAddress,

        [Parameter(Mandatory = $true)]
        [int]$PrefixLength,

        [Parameter(Mandatory = $false)]
        [string]$DefaultGateway,

        [Parameter(Mandatory = $true)]
        [string[]]$DnsServerAddresses,

        [Parameter(Mandatory=$true)]
        [string]$NewName
    )
    try {
        Write-Verbose "Starting static IP configuration for MAC address: $MacAddress"

        # 1. 安定した識別子（MACアドレス）を使用してアダプターを確実に特定する
        $adapter = Get-NetAdapter -Physical | Where-Object { $_.MacAddress -eq $MacAddress }
        if (-not $adapter) {
            throw "Network adapter with MAC address '$MacAddress' not found."
        }
        $ifIndex = $adapter.ifIndex
        Write-Verbose "Adapter '$($adapter.Name)' with InterfaceIndex '$ifIndex' found."

        # --- 変更点: AD DSインストールの警告を抑制するため、IPv6を無効化 ---
        Write-Verbose "Disabling IPv6 on adapter '$($adapter.Name)'."
        Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 | Disable-NetAdapterBinding -PassThru -Confirm:$false | Out-Null

        # 2. 既存のIP設定をクリアしてクリーンな状態を確保する
        $existingIPs = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($existingIPs) {
            Write-Verbose "Removing existing IP addresses from the adapter."
            $existingIPs | Remove-NetIPAddress -Confirm:$false
        }
    
        # デフォルトゲートウェイもクリアする
        $existingRoute = Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        if ($existingRoute) {
            Write-Verbose "Removing existing default gateway."
            $existingRoute | Remove-NetRoute -Confirm:$false
        }

        # 3. DHCPを無効化し、状態変更を検証する
        $ipInterface = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4
        if ($ipInterface.Dhcp -ne 'Disabled') {
            Write-Verbose "Disabling DHCP on the adapter..."
            $ipInterface | Set-NetIPInterface -Dhcp Disabled
        
            # --- 競合状態を回避するための重要な検証ループ ---
            $timeout = 30 # 30秒のタイムアウト
            $counter = 0
            do {
                Start-Sleep -Seconds 1
                $currentDhcpState = (Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4).Dhcp
                $counter++
                if ($counter -ge $timeout) {
                    throw "Timeout waiting for DHCP to be disabled. Current state: $currentDhcpState"
                }
            } while ($currentDhcpState -ne 'Disabled')
            Write-Verbose "DHCP successfully disabled."
        } else {
            Write-Verbose "DHCP is already disabled."
        }

        # 4. 新しい静的IPアドレスとデフォルトゲートウェイを設定する
        $netIPAddressParams = @{
            InterfaceIndex = $ifIndex
            IPAddress      = $IPAddress
            PrefixLength   = $PrefixLength
        }
        if (-not [string]::IsNullOrWhiteSpace($DefaultGateway)) {
            Write-Verbose "Setting new IP address: $IPAddress/$PrefixLength with Gateway: $DefaultGateway"
            $netIPAddressParams.Add("DefaultGateway", $DefaultGateway)
        } else {
            Write-Verbose "Setting new IP address: $IPAddress/$PrefixLength (No Gateway)"
        }
        New-NetIPAddress @netIPAddressParams

        # 5. DNSサーバーを設定する
        Write-Verbose "Setting DNS servers: $($DnsServerAddresses -join ', ')"
        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $DnsServerAddresses

        # アダプター名が既に目的の名前でない場合のみ、名前変更を実行
        if ($adapter.Name -ne $NewName) {
            Write-Verbose "Renaming adapter from '$($adapter.Name)' to '$NewName'"
            $adapter | Rename-NetAdapter -NewName $NewName
        } else {
            Write-Verbose "Adapter is already named '$NewName'. Skipping rename."
        }

        Write-Verbose "Static IP configuration completed successfully."
        return $true
    }
    catch {
        Write-Error "Failed to configure static IP. Error: $($_.Exception.Message)"
        return $false
    }
}

# --- メイン処理 ---
try {
    # --- 設定ファイルの読み込み ---
    $configPath = Join-Path $SourcePath "config.ps1"

    if (-not (Test-Path $configPath)) {
        throw "設定ファイルが見つかりません: $configPath"
    }
    . $configPath # ドットソーシングで設定ファイル内の変数を読み込む

    # --- スクリプトの実行フェーズを判断 ---
    $PostRebootTask = Get-ScheduledTask -TaskName $ScheduledTaskName -ErrorAction SilentlyContinue

    if ($PostRebootTask) {
        # --- フェーズ2: 再起動後の処理 ---
        Write-Host "フェーズ2: 再起動後の処理を開始します。" -ForegroundColor Green
        
        # 自己クリーンアップ: スケジュールタスクを削除
        Write-Host "一時スケジュールタスク '$($ScheduledTaskName)' を削除しています..."
        Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction Stop
        Write-Host "スケジュールタスクの削除に成功しました。"
        
        # 共有フォルダの作成と設定
        Write-Host "共有フォルダ 'PC_Kitting' を作成しています..."
        if (-not (Test-Path -Path "C:\PC_Kitting")) { New-Item -Path "C:\PC_Kitting" -ItemType Directory -ErrorAction Stop | Out-Null }
        New-SmbShare -Name "PC_Kitting" -Path "C:\PC_Kitting" -FullAccess "Everyone" -ErrorAction Stop | Out-Null
        Set-Content -Path "C:\PC_Kitting\NextPCNumber.txt" -Value "0" -ErrorAction Stop
        Write-Host "'PC_Kitting' 共有の作成に成功しました。"

        Write-Host "共有フォルダ 'Installers' を作成しています..."
        if (-not (Test-Path -Path "C:\Installers")) { New-Item -Path "C:\Installers" -ItemType Directory -ErrorAction Stop | Out-Null }
        New-SmbShare -Name "Installers" -Path "C:\Installers" -ReadAccess "Everyone" -ErrorAction Stop | Out-Null
        Write-Host "'Installers' 共有の作成に成功しました。"

        # ファイアウォールでファイル共有を許可
        Write-Host "ファイアウォールで 'ファイルとプリンターの共有' を有効化しています..."
        Enable-NetFirewallRule -DisplayGroup "ファイルとプリンターの共有" -ErrorAction Stop
        Write-Host "ファイアウォール規則の有効化に成功しました。"

        # (セキュリティ対策) 自己クリーンアップ: セットアップファイルを削除
        Write-Host "セットアップファイルをクリーンアップしています..."
        Remove-Item -Path $SourcePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "クリーンアップが完了しました。"

        Write-Host "サーバーのセットアップがすべて完了しました。" -ForegroundColor Green

    }
    else {
        # --- フェーズ1: 初期セットアップ処理 ---
        Write-Host "フェーズ1: 初期セットアップを開始します。" -ForegroundColor Green

        # ネットワークアダプターの設定 (MACアドレスによる堅牢な識別)
        Write-Host "ネットワークアダプターの設定を開始します..."

        # インターネット側アダプターの設定
        $internetNicParams = @{
            MacAddress         = $InternetNicMacAddress
            IPAddress          = $InternetNicIpAddress
            PrefixLength       = $InternetNicSubnetPrefix
            DefaultGateway     = $InternetNicGateway
            DnsServerAddresses = $InternetNicDns
            NewName            = "vNIC-Internet"
        }
        $internetResult = Set-StaticIPConfiguration @internetNicParams
        if (-not $internetResult) {
            throw "インターネット側NICの設定に失敗しました。ログを確認してください。"
        }

        # LGWAN側アダプターの設定
        $lgwanNicParams = @{
            MacAddress         = $LgwanNicMacAddress
            IPAddress          = $LgwanNicIpAddress
            PrefixLength       = $LgwanNicSubnetPrefix
            DnsServerAddresses = "127.0.0.1"
            NewName            = "vNIC-LGWAN"
        }
        $lgwanResult = Set-StaticIPConfiguration @lgwanNicParams
        if (-not $lgwanResult) {
            throw "LGWAN側NICの設定に失敗しました。ログを確認してください。"
        }

        Write-Host "すべてのネットワーク設定が完了しました。" -ForegroundColor Green

        # 役割のインストール
        Write-Host "役割 (AD-Domain-Services, File-Services) をインストールしています..."
        Install-WindowsFeature AD-Domain-Services, File-Services -IncludeManagementTools -ErrorAction Stop
        Write-Host "役割のインストールに成功しました。"

        # 再起動後の処理を継続するためのスケジュールタスクを登録
        Write-Host "再起動後にスクリプトを継続するためのスケジュールタスクを登録しています..."
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
        $taskTrigger = New-ScheduledTaskTrigger -AtStartup
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $ScheduledTaskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Description "AD DS構築後の残りのセットアップを実行します。" -Force -ErrorAction Stop
        Write-Host "スケジュールタスクの登録に成功しました。"

        # ADフォレストの構築
        Write-Host "Active Directory フォレスト '$($DomainName)' を構築しています..."
        $safeModePasswordSecure = ConvertTo-SecureString $SafeModeAdminPasswordPlainText -AsPlainText -Force
        Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName -InstallDns -SafeModeAdministratorPassword $safeModePasswordSecure -Force -ErrorAction Stop
        Write-Host "ADフォレストの構築コマンドが正常に発行されました。サーバーは自動的に再起動します。"
    }
}
catch {
    Write-Error "スクリプトの実行中に致命的なエラーが発生しました: $($_.Exception.Message)"
    Write-Error "エラーが発生した行: $($_.InvocationInfo.ScriptLineNumber)"
    Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}
finally {
    Write-Host "現在のフェーズの処理が完了しました。ログは $($LogPath) に保存されています。"
    Stop-Transcript
}
