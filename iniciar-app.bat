@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\app-docker.ps1" start
if errorlevel 1 (
  echo.
  echo No se pudo iniciar Relay. Revisa el error y que Docker Desktop este arrancado.
  pause
  exit /b 1
)
