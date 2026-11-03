@echo off
setlocal
cd /d "%~dp0"
echo SVR2011-NX - build from your own game folder
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build_release.ps1" %*
if errorlevel 1 (
  echo.
  echo The build failed. The log is in:
  echo   %%LOCALAPPDATA%%\SVR2011-NX\work\build.log
  echo.
  pause
)
endlocal
