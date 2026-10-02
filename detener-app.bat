@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\app-docker.ps1" stop
if errorlevel 1 (
  pause
  exit /b 1
)
