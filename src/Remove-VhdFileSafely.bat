@echo off
echo =================================================================
echo.
echo   VHD�t�@�C���폜 �X�N���v�g���N�����܂�...
echo.
echo =================================================================
echo.

REM PowerShell�X�N���v�g���A���s�|���V�[���ꎞ�I�Ƀo�C�p�X���Ď��s���܂�
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Remove-VhdFileSafely.ps1"

echo.
echo =================================================================
echo.
echo   �������������܂����B
echo.
echo =================================================================
pause