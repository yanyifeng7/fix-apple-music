@echo off
REM fix-apple-music.bat - one-click wrapper that bypasses PowerShell's
REM unsigned-script restriction. Just double-click this file.
REM
REM Equivalent to:
REM     powershell.exe -NoProfile -ExecutionPolicy Bypass -File fix-apple-music.ps1
REM
REM For: "File cannot be loaded. The file ... is not digitally signed."

setlocal
cd /d "%~dp0"

echo ============================================================
echo   fix-apple-music - one-click Apple Music error fix
echo ============================================================
echo.
echo This wrapper calls the PowerShell script with ExecutionPolicy Bypass
echo so Windows won't reject it for being unsigned. It may flash a UAC
echo prompt if the script needs administrator rights.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fix-apple-music.ps1"

REM If the script exited with an error, pause so the window stays open
if errorlevel 1 (
    echo.
    echo ============================================================
    echo   SCRIPT EXITED WITH ERROR (code %errorlevel%)
    echo   Check the log file in %%TEMP%%\fix-apple-music-*.log
    echo ============================================================
    pause
)

endlocal
