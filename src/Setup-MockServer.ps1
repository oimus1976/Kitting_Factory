<#
.SYNOPSIS
    設定ファイルに基づき、仮想テストサーバーのセットアップを完全に自動化します。
    Windowsのunattend.xmlから初回起動時に呼び出されることを想定しています。
.DESCRIPTION
    このスクリプトは、config.ps1 ファイルからすべての構成を読み込み、
    ネットワークアダプターをハードコードされた名前で設定することで、信頼性の高いゼロタッチ実行を実現します。
    処理は再起動を挟んで2つのフェーズで実行され、完了後には自己クリーンアップを行います。
#>

# --- グローバル変数と定数 ---
$LogPath = "C:\Setup-MockServer-Log.txt"
$ScheduledTaskName = "PostRebootADDSSetup"
$SourcePath = "C:\Source" # unattend.xmlから実行されるため、パスを固定

# --- ログ記録の開始 ---
# -Append をつけることで、再起動後に同じファイルに追記する
Start-Transcript -Path $LogPath -Append

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

        # ネットワークアダプターの設定 (ハードコードされた名前を使用)
        Write-Host "ネットワークアダプターを設定しています..."
        
        # インターネット側アダプターの設定
        $internetAdapter = Get-NetAdapter -Name $InternetNicOriginalName -ErrorAction Stop
        Write-Host "アダプター '$($internetAdapter.Name)' を 'vNIC-Internet' に名前変更し、設定します..."
        Rename-NetAdapter -Name $internetAdapter.Name -NewName "vNIC-Internet" -ErrorAction Stop
        # 既存のIP設定をクリア (冪等性の確保)
        Get-NetIPAddress -InterfaceAlias "vNIC-Internet" -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        Get-NetRoute -InterfaceAlias "vNIC-Internet" -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne "0.0.0.0" } | Remove-NetRoute -Confirm:$false
        # 新しいIP設定を適用
        New-NetIPAddress -InterfaceAlias "vNIC-Internet" -IPAddress $InternetNicIpAddress -PrefixLength $InternetNicSubnetPrefix -DefaultGateway $InternetNicGateway -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceAlias "vNIC-Internet" -ServerAddresses $InternetNicDns -ErrorAction Stop
        Write-Host "'vNIC-Internet' の設定が完了しました。"

        # LGWAN側アダプターの設定
        $lgwanAdapter = Get-NetAdapter -Name $LgwanNicOriginalName -ErrorAction Stop
        Write-Host "アダプター '$($lgwanAdapter.Name)' を 'vNIC-LGWAN' に名前変更し、設定します..."
        Rename-NetAdapter -Name $lgwanAdapter.Name -NewName "vNIC-LGWAN" -ErrorAction Stop
        # 静的IPを設定する前にDHCPを無効化し、設定の信頼性を向上させる
        Set-NetIPInterface -InterfaceAlias "vNIC-LGWAN" -Dhcp Disabled -ErrorAction Stop
        # 既存のIP設定をクリア (冪等性の確保)
        Get-NetIPAddress -InterfaceAlias "vNIC-LGWAN" -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false
        # 新しいIP設定を適用
        New-NetIPAddress -InterfaceAlias "vNIC-LGWAN" -IPAddress $LgwanNicIpAddress -PrefixLength $LgwanNicSubnetPrefix -ErrorAction Stop
        Set-DnsClientServerAddress -InterfaceAlias "vNIC-LGWAN" -ServerAddresses "127.0.0.1" -ErrorAction Stop
        Write-Host "'vNIC-LGWAN' の設定が完了しました。"

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
        # 設定ファイルから読み込んだ平文パスワードをメモリ上でSecureStringに変換
        $safeModePasswordSecure = ConvertTo-SecureString $SafeModeAdminPasswordPlainText -AsPlainText -Force
        
        Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName -InstallDns -SafeModeAdministratorPassword $safeModePasswordSecure -Force -ErrorAction Stop
        Write-Host "ADフォレストの構築コマンドが正常に発行されました。サーバーは自動的に再起動します。"
    }
}
catch {
    # エラー発生時に詳細をログに出力して終了
    Write-Error "スクリプトの実行中に致命的なエラーが発生しました: $($_.Exception.Message)"
    # AD構築に失敗した場合、念のためスケジュールタスクを削除
    Unregister-ScheduledTask -TaskName $ScheduledTaskName -Confirm:$false -ErrorAction SilentlyContinue
    exit 1
}
finally {
    # --- ログ記録の終了 ---
    Write-Host "現在のフェーズの処理が完了しました。ログは $($LogPath) に保存されています。"
    Stop-Transcript
}