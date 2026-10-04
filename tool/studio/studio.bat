@echo off
rem SPC Studio, the brand builder: serves http://127.0.0.1:4777 and opens it.
rem Double-click it or run it from anywhere; it moves to the repo root itself.
rem Extra arguments pass through, e.g. "studio.bat --check".
setlocal
cd /d "%~dp0..\.."

rem The full path, never a bare "dart": cmd gives a quoted batch file found
rem on PATH the wrong %~dp0, and Flutter's dart.bat then cannot find itself.
set "DART="
for /f "delims=" %%d in ('where dart.bat 2^>nul') do if not defined DART set "DART=%%d"
if not defined DART if exist "%FLUTTER_ROOT%\bin\dart.bat" set "DART=%FLUTTER_ROOT%\bin\dart.bat"
if not defined DART (
  echo Studio needs Dart, which comes with Flutter. Put Flutter's bin folder on
  echo PATH or set FLUTTER_ROOT. On the Windows build machine it is C:\src\flutter.
  pause
  exit /b 1
)

call "%DART%" run tool/studio/bin/studio.dart %*
if errorlevel 1 pause
