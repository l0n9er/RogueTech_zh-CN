@echo off
chcp 65001 >nul
title BATTLETECH / RogueTech 简体中文补丁
cd /d "%~dp0"

echo.
echo  BATTLETECH / RogueTech 简体中文补丁
echo  ----------------------------------------
echo  安装前请完全退出游戏和 RogueLauncher。
echo  请明确选择你的游戏版本，Steam 和 GOG 不能混用。
echo  预计需要 3~4 分钟，请勿关闭窗口。
echo.
echo  [1] Steam
echo  [2] GOG
echo.
choice /C 12 /N /M "请选择版本: "
if errorlevel 2 (set EDITION=GOG) else (set EDITION=Steam)
echo  已选择: %EDITION%
echo.
echo  按任意键开始安装...
pause >nul

echo.
echo  正在启动安装脚本，请稍候...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0工具\安装.ps1" -edition "%EDITION%"
set RC=%ERRORLEVEL%

echo.
if "%RC%"=="0" (
    echo  [完成] 汉化安装已完成，请重新启动游戏。
) else (
    echo  [失败] 安装未完成（返回码 %RC%）。请查看窗口中的错误和 install.log。
)
echo.
pause