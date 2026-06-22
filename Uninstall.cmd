@echo off
setlocal
title Codex Usage Island Uninstaller
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
if errorlevel 1 (
  echo.
  echo Uninstallation failed. Review the error above.
  pause
  exit /b 1
)
echo.
echo Uninstallation completed.
timeout /t 2 /nobreak >nul
