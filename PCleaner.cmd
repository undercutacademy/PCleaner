@echo off
rem Opens the PCleaner window straight from this folder, without installing.
rem It runs src\PCleaner.ps1 (readable PowerShell) and asks once for administrator rights.
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0src\PCleaner.ps1"
