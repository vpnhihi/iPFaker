@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
title iPFaker PC

echo.
echo  iPFaker PC — dieu khien iPhone qua Wi-Fi SSH
echo  =============================================
echo.

where python >nul 2>&1
if errorlevel 1 (
  echo [!] Khong tim thay Python. Cai Python 3.10+ roi chay lai.
  pause
  exit /b 1
)

python -c "import paramiko" 2>nul
if errorlevel 1 (
  echo [*] Cai paramiko...
  python -m pip install paramiko -q
)

python pc_app\app.py
if errorlevel 1 pause
