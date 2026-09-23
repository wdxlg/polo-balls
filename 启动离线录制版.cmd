@echo off
chcp 65001 >nul
setlocal
set "ENGINE=%~dp0..\polo-balls-tools\offline-engine\runtime\Godot.4.7.2.offline.exe"
if not exist "%ENGINE%" (
  echo 找不到独立离线引擎，请查看 tools\offline_engine\README.md
  pause
  exit /b 1
)
start "" "%ENGINE%" --path "%~dp0." %*
