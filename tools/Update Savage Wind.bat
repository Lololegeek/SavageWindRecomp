@echo off
rem Updates Savage Wind in this folder to the newest release, keeping the game files, game code, saves and settings
rem (tools/update.ps1: "Update Savage Wind.bat -Help" style options are passed through, e.g. -Stable, -Zip file.zip).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
