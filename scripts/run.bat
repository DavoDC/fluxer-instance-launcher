@echo off
rem Thin launcher for fluxer-instance-launcher.ps1. Usage: run.bat [--no-pause] [action] [options]
rem Actions: launch (default), apply, repair, status, uninstall. Exits with the ps1 exit code.
set "HERE=%~dp0"
set "NOPAUSE=0"
set "ARGS="
:collect
if "%~1"=="" goto run
if /i "%~1"=="--no-pause" (set "NOPAUSE=1") else (set ARGS=%ARGS% %1)
shift
goto collect

:run
echo Started %DATE% %TIME%
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%fluxer-instance-launcher.ps1"%ARGS%
set "RC=%ERRORLEVEL%"
echo Finished %DATE% %TIME% (exit %RC%)
if "%NOPAUSE%"=="1" exit /b %RC%
echo.
cmd /k
