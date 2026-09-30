@echo off
chcp 65001 >nul
cd /d "%~dp0"
python tools\protected_export.py export
if errorlevel 1 (
  echo 加密导出未完成，请检查上方错误。不要分发失败目录。
) else (
  echo 加密导出完成。请分发输出目录中的整套游戏文件，不要分发项目源码或密钥。
)
pause
