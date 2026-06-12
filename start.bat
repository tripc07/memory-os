@echo off
setlocal

rem Start the native Windows Memory OS runtime after a reboot.
rem This delegates service details to setup\start_services.ps1.

cd /d "%~dp0"

if not exist "%CD%\.env" (
    echo [WARN] .env was not found at "%CD%\.env".
    echo        Run setup\setup_windows.ps1 or create .env before starting services.
)

set "MAA_ENV_PATH=%CD%\.env"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%CD%\setup\start_services.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] Memory OS startup failed with exit code %EXIT_CODE%.
    echo         Check logs under %%LOCALAPPDATA%%\hermes\logs.
    exit /b %EXIT_CODE%
)

echo.
echo Memory OS runtime is started.
echo Services: Redis, Qdrant, Ollama embeddings, llama.cpp chat, ARQ worker.
exit /b 0
