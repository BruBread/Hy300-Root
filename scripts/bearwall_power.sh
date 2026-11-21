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
# The hold length comes from getevent's own timestamps (POWER = key 0x74, 1 = down, 0 = up), so there is
# no background timer to kill. (A killed "(sleep 3; ...) &" timer took the whole script down with it.)
# A hold of 3 s or more shuts down when the button is released.
press_length() {
  awk '{ t = $0; sub(/^\[ */, "", t); sub(/\].*/, "", t) }
       / 0001 0074 00000001$/ { down = t }
       / 0001 0074 00000000$/ { print (t - down >= 3) ? "long" : "short"; fflush() }'
}
getevent -t -q /dev/input/event0 | press_length | while read -r press; do
  if [ "$press" = long ]; then
    log -t bearwall_power "held 3 s: shutting down"; svc power shutdown
  elif [ "$(cat $LCD)" = "0" ]; then
    echo 255 > $PWR; sleep 0.5; echo 255 > $LCD; input keyevent KEYCODE_WAKEUP; log -t bearwall_power "wake"
  else
    echo 0 > $LCD; sleep 0.2; echo 0 > $PWR; log -t bearwall_power "sleep"
  fi
done
