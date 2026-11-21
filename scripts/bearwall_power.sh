#!/system/bin/sh
# Remote POWER button: short press = sleep / wake, hold 3 s = shut down.
# Install: /data/bearwall_power.sh, started at boot by /data/hdmi_autoswitch.sh (root).
# Android's own POWER mapping is commented out in the remote's key layout,
# so this is the only thing that reacts to the button. BearWall sees Lcd_en = 0 and pauses its page.
# Sleep = panel off in the right order: Lcd_en off, then Lcd_power off. Only Lcd_power turns the LED
# light off; Lcd_en alone leaves an evenly lit rectangle. Wake = Lcd_power on, 0.5 s, Lcd_en on.
# A panel power cycle leaves the panel upside down, so the vendor init file restarts it once at boot and
# the keystone corners are stored rotated 180 degrees (see scripts/panel_flip.md). Never put Android to
# sleep here: deep suspend crashes the RK628 HDMI-in driver (a wake lock at boot prevents it).
LCD=/sys/class/leds/Lcd_en/brightness
PWR=/sys/class/leds/Lcd_power/brightness
timer=""
getevent -q /dev/input/event0 | while read -r line; do
  case "$line" in
    *"0001 0074 00000001")   # POWER down: start the 3 s hold timer
      (sleep 3; log -t bearwall_power "held 3 s: shutting down"; svc power shutdown) &
      timer=$! ;;
    *"0001 0074 00000000")   # POWER up before 3 s = short press
      if [ -n "$timer" ] && kill "$timer" 2>/dev/null; then
        if [ "$(cat $LCD)" = "0" ]; then
          echo 255 > $PWR; sleep 0.5; echo 255 > $LCD; input keyevent KEYCODE_WAKEUP; log -t bearwall_power "wake"
        else
          echo 0 > $LCD; sleep 0.2; echo 0 > $PWR; log -t bearwall_power "sleep"
        fi
      fi
      timer="" ;;
  esac
done
