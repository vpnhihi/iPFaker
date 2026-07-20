@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0\.."
title iPFaker PC
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

echo.
echo  iPFaker PC — dieu khien iPhone qua Wi-Fi SSH
echo  =============================================
echo  Thu muc: %CD%
echo.

REM Prefer "py -3" launcher, then python, then python3
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY (
  where python >nul 2>&1 && set "PY=python"
)
if not defined PY (
  where python3 >nul 2>&1 && set "PY=python3"
)
if not defined PY (
  echo [!] Khong tim thay Python.
  echo     Cai Python 3.10+ tu python.org ^(tick "Add to PATH"^) roi chay lai.
  echo.
  pause
  exit /b 1
)

echo [*] Dung: %PY%
%PY% --version
echo.

%PY% -c "import tkinter" 2>nul
if errorlevel 1 (
  echo [!] Thieu tkinter — cai lai Python va chon tcl/tk.
  pause
  exit /b 1
)

%PY% -c "import paramiko" 2>nul
if errorlevel 1 (
  echo [*] Cai paramiko...
  %PY% -m pip install paramiko -q
)

%PY% -c "import frida" 2>nul
if errorlevel 1 (
  echo [*] Cai frida ^(Reg tu dong^)...
  %PY% -m pip install frida -q
)

echo [*] Mo giao dien...
echo.
%PY% pc_app\app.py
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" (
  echo [!] App thoat ma loi %ERR%
  if exist "pc_app\last_error.txt" (
    echo --- last_error.txt ---
    type pc_app\last_error.txt
    echo ---------------------
  )
) else (
  echo [*] App da dong binh thuong.
)
echo.
pause
endlocal
exit /b %ERR%
