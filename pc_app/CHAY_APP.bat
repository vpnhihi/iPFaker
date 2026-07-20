@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
title iPFaker PC
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo.
echo  iPFaker PC
echo  ==========
echo  Folder: %CD%
echo.

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo [!] Khong tim thay Python. Cai python.org ^(tick Add to PATH + tcl/tk^)
  pause
  exit /b 1
)

echo Python: 
%PY% --version
echo.

%PY% -c "import tkinter" 2>nul
if errorlevel 1 (
  echo [!] Thieu tkinter
  pause
  exit /b 1
)

%PY% -c "import paramiko" 2>nul
if errorlevel 1 %PY% -m pip install paramiko -q

echo [*] Mo app...
%PY% -u pc_app\app.py
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" (
  echo [!] Ma loi %ERR%
  if exist pc_app\last_error.txt (
    echo --- last_error.txt ---
    type pc_app\last_error.txt
  )
  if exist pc_app\startup.log (
    echo --- startup.log ---
    type pc_app\startup.log
  )
)
echo.
pause
exit /b %ERR%
