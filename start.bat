@ECHO OFF
ECHO ***** Automating User, OU, SecGroups and Shares (if config provided) *****
ECHO ***** Please press any key to begin...                               *****
PAUSE >nul
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '.\script\UserAndGroupManagement.ps1'"

ECHO ***** Setup has completed... Press any key to close this window *****
PAUSE >nul