#!/system/bin/sh
# Remote POWER button: short press = sleep / wake, hold 3 s = shut down.
# Install: /data/bearwall_power.sh, started at boot by /data/hdmi_autoswitch.sh (root).
# Android's own POWER mapping is commented out in /vendor/usr/keylayout/ff200010_pwm.kl,
# so this is the only thing that reacts to the button. Sleep = Lcd_en off (never Lcd_power);
# BearWall sees Lcd_en = 0 and pauses its page.
LCD=/sys/class/leds/Lcd_en/brightness
timer=""
getevent -q /dev/input/event0 | while read -r line; do
  case "$line" in
    *"0001 0074 00000001")   # POWER down: start the 3 s hold timer
      (sleep 3; log -t bearwall_power "held 3 s: shutting down"; svc power shutdown) &
      timer=$! ;;
    *"0001 0074 00000000")   # POWER up before 3 s = short press
      if [ -n "$timer" ] && kill "$timer" 2>/dev/null; then
        if [ "$(cat $LCD)" = "0" ]; then
          echo 255 > $LCD; input keyevent KEYCODE_WAKEUP; log -t bearwall_power "wake"
        else
          echo 0 > $LCD; log -t bearwall_power "sleep"
        fi
      fi
      timer="" ;;
  esac
done
