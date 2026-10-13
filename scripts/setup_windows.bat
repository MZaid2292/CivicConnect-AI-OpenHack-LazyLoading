@echo off
cd /d "%~dp0.."
where flutter >nul 2>nul
if errorlevel 1 (
 echo ERROR: Flutter SDK not found in PATH. Install Flutter and restart VS Code.
 pause
 exit /b 1
)
flutter create --project-name civicconnect_ai --platforms android,web .
if errorlevel 1 goto failed
flutter pub get
if errorlevel 1 goto failed
flutter analyze
if errorlevel 1 goto failed
echo Setup completed. Run: flutter run
pause
exit /b 0
:failed
echo Setup failed. Copy terminal error into ChatGPT for diagnosis.
pause
exit /b 1
