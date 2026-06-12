@echo off
setlocal

rem Sync Memory OS into Hermes, start native dependencies, then launch Hermes.
rem llama.cpp is used by Memory OS as a local runtime dependency; this script
rem does not change Hermes' primary model provider.

cd /d "%~dp0"

set "MAA_ENV_PATH=%CD%\.env"

call "%CD%\start.bat"
if errorlevel 1 exit /b %ERRORLEVEL%

hermes %*
exit /b %ERRORLEVEL%
