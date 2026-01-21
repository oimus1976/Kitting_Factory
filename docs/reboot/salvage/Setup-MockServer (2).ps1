# ログ記録を開始
Start-Transcript -Path C:\Setup-MockServer-Log.txt

# ネットワークアダプターの名前を変更して分かりやすくする
Rename-NetAdapter -Name "イーサネット" -NewName "vNIC-Internet"
Rename-NetAdapter -Name "イーサネット 2" -NewName "vNIC-LGWAN"

# ネットワーク設定
Set-NetIPAddress -InterfaceAlias "vNIC-Internet" -IPAddress "192.168.0.200" -PrefixLength 24 -DefaultGateway "192.168.0.1"
Set-DnsClientServerAddress -InterfaceAlias "vNIC-Internet" -ServerAddresses "192.168.0.1"
Set-NetIPAddress -InterfaceAlias "vNIC-LGWAN" -IPAddress "192.168.100.10" -PrefixLength 24
Set-DnsClientServerAddress -InterfaceAlias "vNIC-LGWAN" -ServerAddresses "127.0.0.1"

# 役割のインストール
Install-WindowsFeature AD-Domain-Services, File-Services -IncludeManagementTools

# ADフォレストの構築
$safeModePassword = ConvertTo-SecureString "P@ssw0rd12345!" -AsPlainText -Force
Install-ADDSForest -DomainName "katsuragi-test.local" -DomainNetbiosName "KATSURAGI-TEST" -InstallDns -SafeModeAdministratorPassword $safeModePassword -Force

# この後、サーバーはAD構築のために自動的に再起動します。
# 再起動後、手動でログインし、残りの設定を行ってください。
# (完全自動化のためには、ここからさらに再起動後の処理を継続する仕組みが必要です)

# WinGateのサイレントインストール
# Start-Process -FilePath "C:\Source\wingate_installer.exe" -ArgumentList "/S" -Wait

# 共有フォルダの作成と設定
New-Item -Path "C:\PC_Kitting" -ItemType Directory
New-SmbShare -Name "PC_Kitting" -Path "C:\PC_Kitting" -FullAccess "Everyone"
Set-Content -Path "C:\PC_Kitting\NextPCNumber.txt" -Value "0"

New-Item -Path "C:\Installers" -ItemType Directory
New-SmbShare -Name "Installers" -Path "C:\Installers" -ReadAccess "Everyone"

# ファイアウォールでファイル共有を許可
Enable-NetFirewallRule -DisplayGroup "ファイルとプリンターの共有"

Stop-Transcript