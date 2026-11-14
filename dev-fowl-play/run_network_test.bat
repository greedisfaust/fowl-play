@echo off
cd /d "%~dp0"
set G="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
echo =================================================
echo Running host...
echo =================================================
start "" %G% --headless --path . --scene res://tests/test_house_network.tscn --is-host
timeout /t 3 /nobreak
echo =================================================
echo Running client...
echo =================================================
%G% --headless --path . --scene res://tests/test_house_network.tscn
echo.
echo Both finished.
pause
