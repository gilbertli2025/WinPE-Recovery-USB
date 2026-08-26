@echo off
rem Profile Repair Utility - launcher (double-click this file)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0ProfileRepair-Utility.ps1"
