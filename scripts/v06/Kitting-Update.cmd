@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Kitting Factory v0.6 - Stage後の更新を1段階進める。USBルートで右クリック →「管理者として実行」。
rem 再起動は行わない。画面の案内に従って再起動し、DONE と出るまで再実行する。
rem 確認と処理はすべて Apply-OfflineUpdates.ps1 が行う。

if not exist "%~dp0Apply-OfflineUpdates.ps1" goto :missing
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Apply-OfflineUpdates.ps1"
set "RC=%ERRORLEVEL%"
goto :end

:missing
echo STOP: USBルートに Apply-OfflineUpdates.ps1 がありません。
set "RC=4"

:end
pause
exit /b %RC%
