@echo off
setlocal
rem Sleep mode: turns the projector's light off (and the fan stops) while Android and wifi stay up,
rem so it wakes instantly. Your PC must be on the same wifi as the projector.
rem Usage: sleep_mode.bat          toggle
rem        sleep_mode.bat sleep    light off
rem        sleep_mode.bat wake     light on
rem Same sequence as the remote's power button (scripts/bearwall_power.sh): Lcd_en off then Lcd_power off,
rem and back on in reverse with a 0.5 s gap. Only Lcd_power turns the LED off. A panel power cycle leaves
rem the panel upside down, which is why the vendor init file restarts it at boot and the keystone corners
rem are stored rotated 180 degrees (scripts/panel_flip.md). Android is never put to sleep: deep suspend
rem crashes the RK628 HDMI-in driver.

set PROJ_IP=PROJECTOR_IP
set PROJ_MAC=PROJECTOR_MAC
set SUBNET=192.168.1
set LINE=/sys/class/leds/Lcd_en/brightness
set PWR=/sys/class/leds/Lcd_power/brightness

adb connect %PROJ_IP%:5555 | find "connected to" >nul || call :find_projector
adb -s %PROJ_IP%:5555 get-state >nul 2>&1 || (echo Projector not found. Is it on and on the same wifi? & goto :fail)
set ADB=adb -s %PROJ_IP%:5555

rem adb root restarts adbd after a reboot, which drops the wifi connection: reconnect.
%ADB% root | find "restarting" >nul && (timeout /t 3 >nul & adb connect %PROJ_IP%:5555 >nul)

set MODE=%1
if "%MODE%"=="" (
  for /f %%v in ('%ADB% shell cat %LINE%') do if "%%v"=="0" (set MODE=wake) else (set MODE=sleep)
)

if /i "%MODE%"=="sleep" (
  %ADB% shell "echo 0 > %LINE%; sleep 0.2; echo 0 > %PWR%" || goto :fail
  echo Projector asleep: light off, fan stops within a minute.
  exit /b 0
)
if /i "%MODE%"=="wake" (
  %ADB% shell "echo 255 > %PWR%; sleep 0.5; echo 255 > %LINE%; input keyevent KEYCODE_WAKEUP" || goto :fail
  echo Projector awake.
  exit /b 0
)
echo Usage: sleep_mode.bat [sleep^|wake]   no argument toggles
goto :fail

rem The projector's DHCP address changed: ping the subnet to fill the ARP table, then look it up by MAC.
:find_projector
for /L %%i in (1,1,254) do start /b "" ping -n 1 -w 300 %SUBNET%.%%i >nul
timeout /t 3 >nul
for /f "tokens=1" %%a in ('arp -a ^| find /i "%PROJ_MAC%"') do set PROJ_IP=%%a
adb connect %PROJ_IP%:5555 >nul
exit /b 0

:fail
pause
exit /b 1
