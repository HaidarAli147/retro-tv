@echo off
rem Starts the Retro TV app on Windows (needs MSYS2 - see README_WINDOWS.txt)
set PATH=C:\msys64\ucrt64\bin;%PATH%
cd /d "%~dp0"
C:\msys64\ucrt64\bin\python.exe tv.py %*
pause
