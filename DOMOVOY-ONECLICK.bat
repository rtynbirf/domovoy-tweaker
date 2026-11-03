@echo off
setlocal EnableExtensions
chcp 65001 >nul
title DOMOVOY ONE-CLICK - local CI + build
set "REPO_DIR=%USERPROFILE%\domovoy-tweaker"
set "REPO_URL=https://github.com/rtynbirf/domovoy-tweaker.git"
set "SCRIPT_REL=tools\Invoke-DomovoyLocalCI.ps1"

echo ==================================================================
echo  DOMOVOY - one-click local run: CI equivalent + artifact build
echo  repo      : %REPO_URL%
echo  local copy: %REPO_DIR%
echo  Nothing in the repository is modified. Artifacts and logs go to
echo  LOCALAPPDATA. No admin rights needed (one UAC prompt is possible
echo  ONLY if git is missing and has to be installed via winget).
echo ==================================================================
echo.

rem ---------- [1/4] git ----------
set "GIT_EXE=git"
where git >nul 2>nul
if errorlevel 1 (
    if exist "%ProgramFiles%\Git\cmd\git.exe" (
        set "GIT_EXE=%ProgramFiles%\Git\cmd\git.exe"
    ) else (
        echo [1/4] git not found. Installing via winget - one UAC prompt possible...
        winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
        if exist "%ProgramFiles%\Git\cmd\git.exe" (
            set "GIT_EXE=%ProgramFiles%\Git\cmd\git.exe"
        ) else (
            echo [ERROR] git is still missing. Install it manually: https://git-scm.com/download/win
            pause
            exit /b 10
        )
    )
)
echo [1/4] git OK: %GIT_EXE%

rem ---------- [2/4] PowerShell engine ----------
set "PSEXE=powershell.exe"
where pwsh >nul 2>nul
if not errorlevel 1 set "PSEXE=pwsh.exe"
echo [2/4] PowerShell engine: %PSEXE%

rem ---------- [3/4] repository ----------
if not exist "%REPO_DIR%\.git" (
    echo [3/4] First run: cloning the repository...
    "%GIT_EXE%" clone --quiet "%REPO_URL%" "%REPO_DIR%"
    if errorlevel 1 (
        echo [ERROR] Clone failed - check the internet connection and re-run.
        pause
        exit /b 11
    )
) else (
    echo [3/4] Local copy found: %REPO_DIR%
)
if not exist "%REPO_DIR%\%SCRIPT_REL%" (
    echo [3/4] Local copy is old - updating...
    "%GIT_EXE%" -C "%REPO_DIR%" pull --ff-only --quiet origin main
)
if not exist "%REPO_DIR%\%SCRIPT_REL%" (
    echo [ERROR] %SCRIPT_REL% not found even after update.
    echo         Try manually: git -C "%REPO_DIR%" pull
    pause
    exit /b 12
)
echo [3/4] Repository ready.

rem ---------- [4/4] local CI + build ----------
echo [4/4] Running the full local CI + build. First run takes a few minutes.
echo.
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%REPO_DIR%\%SCRIPT_REL%" -RepoDir "%REPO_DIR%" -GitExe "%GIT_EXE%"
set "EC=%ERRORLEVEL%"
echo.
if "%EC%"=="0" (
    echo  VERDICT: GREEN - all steps passed. Repo is in working state.
) else (
    echo  VERDICT: RED - failed steps: %EC%. See step details above.
)
echo  Log and artifacts: %LOCALAPPDATA%\Domovoy
echo  This window closes by itself in 120 s. Press any key to close now.
timeout /t 120 >nul
exit /b %EC%
