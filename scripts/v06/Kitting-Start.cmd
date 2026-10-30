@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Kitting Factory v0.6 - デスクトップで「管理者として実行」を1回行い、既存 Start-Kitting.ps1 -Action Stage を呼ぶ。
rem 使い方: USBルートでこのファイルを右クリック →「管理者として実行」。
rem         Hyper-V評価VMに限り、引数 VMEVAL を付ける（自動判定はしない）。
rem 再試行、既存状態の削除・上書き、Windows Update、ベンダーBATは行わない。

set "ROOT=%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "VMARG="

if not "%~2"=="" goto :bad_arg
if "%~1"=="" goto :args_ok
if /I "%~1"=="VMEVAL" goto :vmeval
goto :bad_arg
:vmeval
set "VMARG=-AllowEnterpriseEvaluationVM"
:args_ok

"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if errorlevel 1 goto :not_admin

if not exist "%ROOT%Start-Kitting.ps1" goto :missing
if not exist "%ROOT%Update-Worker.ps1" goto :missing
if not exist "%ROOT%KITTING_FACTORY_USB_V03.TAG" goto :missing
if not exist "%ROOT%ClientSoft\" goto :missing

set "TS="
rem for /f 内で先頭が引用符だと cmd /c が引用符を外すため、空白を含まない %PS% は引用しない。
for /f "usebackq delims=" %%t in (`%PS% -NoProfile -NonInteractive -Command Get-Date -Format yyyyMMdd-HHmmss`) do set "TS=%%t"
if not defined TS goto :no_log
if not exist "%ROOT%logs\" mkdir "%ROOT%logs" >nul 2>&1
set "LOG=%ROOT%logs\%COMPUTERNAME%-%TS%-stage.log"
> "%LOG%" echo START %TS% COMPUTERNAME=%COMPUTERNAME% ARG=%~1
if errorlevel 1 goto :no_log

echo Stageを実行しています。USBを抜かずにお待ちください（数分かかることがあります）。
rem 末尾の \ が閉じ引用符をエスケープしないよう "%ROOT%." を渡す。
"%PS%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%ROOT%Start-Kitting.ps1" -Action Stage -SourceRoot "%ROOT%." -NewUnassignedPC %VMARG% >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
>> "%LOG%" echo EXIT_CODE=%RC%
type "%LOG%"
echo.
if "%RC%"=="0" goto :pass
echo STOP: 処理を中止しました（終了コード %RC%）。自動で再実行しないでください。
echo       ログ: %LOG%
goto :end
:pass
echo PASS: Stageが完了しました。状態は WAIT_INET です。
echo       ログ: %LOG%
goto :end

:bad_arg
echo STOP: 引数が正しくありません。引数なし、または VMEVAL のみ指定できます。
set "RC=2"
goto :end
:not_admin
echo STOP: 管理者として実行されていません。右クリック →「管理者として実行」で起動してください。
set "RC=3"
goto :end
:missing
echo STOP: USBルートに必要なファイルがありません（Start-Kitting.ps1 / Update-Worker.ps1 / KITTING_FACTORY_USB_V03.TAG / ClientSoft）。
set "RC=4"
goto :end
:no_log
echo STOP: USBにログを作成できません。USBが書込可能か確認してください。
set "RC=5"
goto :end

:end
pause
exit /b %RC%
