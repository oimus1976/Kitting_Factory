#================================================================================
# マスターキッティングPowerShellスクリプト (MasterKittingScript.ps1)
# 作成者: [あなたの名前]
# 説明: 新規PCのセットアップをゼロタッチで自動化します。
#       旧「新規PC設定マニュアル（情報系_2022版）」[1]の全工程を網羅します。
#================================================================================
param (
    [Parameter(Mandatory=$true)]
   
    [string]$Environment,

    [string]$Phase = "1"
)

#--------------------------------------------------------------------------------
# 【環境設定項目】: 実行環境に応じて、以下の設定が自動的に選択されます
#--------------------------------------------------------------------------------
$Settings = @{}

if ($Environment -eq "Test") {
    Write-Host "【情報】検証環境モードでスクリプトを実行します。" -ForegroundColor Yellow
    $Settings = @{
        # --- 検証環境用の設定 ---
        InetProxyAddress     = "192.168.0.200:12080"      # MockServerのINET側IPとWinGateのポート
        LgwanProxyAddress    = "192.168.100.10:12080"     # 模擬LGWANプロキシ（MockServerのLGWAN側IP）
        DomainName           = "katsuragi-test.local"     # 検証用ドメイン名
        NameCounterSharePath = "\\192.168.100.10\PC_Kitting" # MockServerのLGWAN側IPと共有フォルダ
        TargetOU             = "OU=Workstations,DC=katsuragi-test,DC=local" # 検証用OUパス
        DomainJoinUser       = "katsuragi-test\Administrator" # 検証用ドメイン参加アカウント
    }
}
elseif ($Environment -eq "Production") {
    Write-Host "【警告】本番環境モードでスクリプトを実行します。" -ForegroundColor Red
    $Settings = @{
        # --- 本番環境用の設定 ---
        InetProxyAddress     = "172.17.0.3:12080"
        LgwanProxyAddress    = "103.100.1.15:12080"
        DomainName           = "KATSURAGI.local"
        NameCounterSharePath = "\\kr-sv01\PC_Kitting" # 本番ファイルサーバーのパスを想定
        TargetOU             = "OU=forWindows10,OU=Workstations,DC=KATSURAGI,DC=local" # 本番OUパス
        DomainJoinUser       = "KATSURAGI\administrator" # 本番ドメイン参加アカウント
    }
}

#--------------------------------------------------------------------------------
# スクリプト本体
#--------------------------------------------------------------------------------

# --- ログ記録の開始 ---
try {
    Start-Transcript -Path "C:\KittingLog.txt" -Append -ErrorAction Stop
}
catch {
    Write-Host "ログファイル C:\KittingLog.txt を開始できませんでした。"
    exit 1
}

# --- フェーズ分岐 ---
if ($Phase -eq "1") {
    #==========================================================
    # フェーズ1: INET系ネットワークでの処理
    #==========================================================
    Write-Host "【フェーズ1】INET系ネットワークでの処理を開始します..." -ForegroundColor Cyan

    # 1. INET用プロキシ設定 [1]
    Write-Host "1. INET用プロキシを設定しています..."
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 1
    Set-ItemProperty -Path $regPath -Name "ProxyServer" -Value $Settings['InetProxyAddress']

    # 2. Windows Updateの実行 [1]
    Write-Host "2. Windows Updateを実行しています... (完了まで時間がかかる場合があります)"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction SilentlyContinue
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -ErrorAction SilentlyContinue
    Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
    Get-WindowsUpdate -AcceptAll -Install -AutoReboot | Out-File -FilePath C:\WindowsUpdate.log

    # 3. ネットワーク切り替えの指示
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "INET系フェーズが完了しました。" -ForegroundColor Yellow
    Write-Host "PCをシャットダウンし、ネットワークを【情報系（LGWAN）】に切り替えてください。" -ForegroundColor Yellow
    Write-Host "切り替え後、再度電源を入れると、自動的に次のステップが開始されます。" -ForegroundColor Yellow
    Write-Host "========================================================================" -ForegroundColor Yellow

    # 4. フェーズ2への引き継ぎ設定
    # 一時的な管理者アカウントでの自動ログオンを設定
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultUserName" -Value "jyohoadmin" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Value "katsuragi" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "1" -Force

    # 再起動後にフェーズ2を実行するためのRunOnceキーを登録
    $command = "powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Temp\MasterKittingScript.ps1 -Environment $Environment -Phase 2"
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "ContinueKitting" -Value $command -Force

    Stop-Transcript
    # この後、担当者が手動でシャットダウンし、ネットワークを切り替える
}
elseif ($Phase -eq "2") {
    #==========================================================
    # フェーズ2: 情報系（LGWAN）ネットワークでの処理
    #==========================================================
    Write-Host "【フェーズ2】情報系（LGWAN）ネットワークでの処理を継続します..." -ForegroundColor Cyan

    # 1. 高速スタートアップを無効化 [1]
    Write-Host "1. 高速スタートアップを無効化しています..." [2, 3, 4, 5]
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Force

    # 2. 情報系用プロキシ設定 [1]
    Write-Host "2. 情報系用プロキシを設定しています..." [6, 7, 8, 9]
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Set-ItemProperty -Path $regPath -Name "ProxyEnable" -Value 1
    Set-ItemProperty -Path $regPath -Name "ProxyServer" -Value $Settings['LgwanProxyAddress']
    Set-ItemProperty -Path $regPath -Name "ProxyOverride" -Value "<local>"

    # 3. ドメイン参加 [1]
    Write-Host "3. ドメインに参加します..."
    $credential = New-Object System.Management.Automation.PSCredential($Settings, (ConvertTo-SecureString "katsuragi" -AsPlainText -Force))
    Add-Computer -DomainName $Settings -OUPath $Settings -Credential $credential -Force -ErrorAction SilentlyContinue [10, 11, 12]

    # 4. 不要なプリインストールアプリの削除 [1]
    Write-Host "4. 不要なプリインストールアプリを削除しています..." [13, 14, 15]
    # (ここにUWPアプリやWin32アプリを削除するコードを記述)

    # 5. ソフトウェアのサイレントインストール [1]
    Write-Host "5. 各種ソフトウェアをインストールしています..."
    # (ここにSymantec, Adobe, Lhaplusなどのサイレントインストールコマンドを記述) [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]

    # 6. 各種設定の適用 [1]
    Write-Host "6. 各種設定を適用しています..."
    # (ここに壁紙、電源設定、既定アプリ、プリンターなどの設定コードを記述) [3, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75]

    # 7. クリーンアップ処理
    Write-Host "7. クリーンアップ処理を実行しています..."
    # 自動ログオン設定を解除
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "DefaultPassword" -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoAdminLogon" -Value "0" -Force

    # --- 完了 ---
    Write-Host "======== すべてのキッティングプロセスが完了しました！ ========" -ForegroundColor Green
    Stop-Transcript
    Restart-Computer -Force
}