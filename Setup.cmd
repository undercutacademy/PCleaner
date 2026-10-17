@echo off
rem PCleaner installer. Double-click to install for the current user. Nothing is cleaned during installation.
rem Everything this starts is readable PowerShell in the installer\ and src\ folders.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0installer\Install-PCleaner.ps1" %*
if errorlevel 1 pause
