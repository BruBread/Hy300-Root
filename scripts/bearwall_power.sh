#!/system/bin/sh
# Remote POWER button: short press = sleep / wake, hold 2 s or more = turn the picture 180 degrees.
# Install: /data/bearwall_power.sh, started at boot by /data/hdmi_autoswitch.sh (root).
# Android's own POWER mapping is commented out in the remote's key layout,
# so this is the only thing that reacts to the button. BearWall sees Lcd_en = 0 and pauses its page.
#
# No hold-to-shut-down: on this board `svc power shutdown` halts Android but leaves the LED lit (a bright
# rectangle, fan possibly stopped) and nothing listens to the remote afterwards. To turn it fully off, unplug it.
#
# Sleep = panel off in the right order: Lcd_en off, then Lcd_power off. Only Lcd_power turns the LED
# light off; Lcd_en alone leaves an evenly lit rectangle. Wake = Lcd_power on, 0.5 s, Lcd_en on.
# A panel power cycle can leave the panel upside down, and the restart at boot (vendor init file, see
# scripts/panel_flip.md) doesn't always end the right way up. Software can't tell which way the panel
# faces, so the hold flips the picture by rotating the stored keystone corners 180 degrees (the same
# transform as panel_flip.md; it is its own inverse, so holding again flips it back).
# Never put Android to sleep here: deep suspend crashes the RK628 HDMI-in driver (a wake lock at boot prevents it).
LCD=/sys/class/leds/Lcd_en/brightness
PWR=/sys/class/leds/Lcd_power/brightness
FRONT=/data/data/com.bearwall/files/front   # "1" while BearWall's wall is on screen (WallActivity writes it)

flip_picture() {
  for c in lt rt lb rb; do
    v=$(getprop persist.sys.keystone.$c); x=${v%,*}; y=${v#*,}
    case $c in
      lt) x=$((1280 - x)); y=$((-720 - y)) ;;
      rt) x=$((-1280 - x)); y=$((-720 - y)) ;;
      lb) x=$((1280 - x)); y=$((720 - y)) ;;
      rb) x=$((-1280 - x)); y=$((720 - y)) ;;
    esac
    setprop persist.sys.keystone.$c "$x,$y"
  done
  setprop persist.sys.keystone.update 1
  service call SurfaceFlinger 1022 f 0.999 >/dev/null; service call SurfaceFlinger 1022 f 1.0 >/dev/null   # force a redraw
}

# Hold length from getevent's own timestamps ("[  12.345678] 0001 0074 00000001": POWER = key 0x74,
# 1 = down, 0 = up), so there is no background timer to kill.
press_length() {
  awk '{ t = $0; sub(/^\[ */, "", t); sub(/\].*/, "", t) }
       / 0001 0074 00000001$/ { down = t }
       / 0001 0074 00000000$/ { print (t - down >= 2) ? "long" : "short"; fflush() }'
}
getevent -t -q /dev/input/event0 | press_length | while read -r press; do
  if [ "$press" = long ]; then
    am broadcast -a com.bearwall.SOUND --es id flip >/dev/null 2>&1 &   # BearWall plays the flip whoosh
    flip_picture; log -t bearwall_power "held: picture turned 180 degrees"
  elif [ "$(cat $LCD)" = "0" ]; then
    echo 255 > $PWR; sleep 0.5; echo 255 > $LCD; input keyevent KEYCODE_WAKEUP; log -t bearwall_power "wake"
  else
    # BearWall on screen: let it play its power-down animation (the intro in reverse) before the panel goes dark.
    # Anything else (HDMI-in, Moonlight): dark at once.
    if [ "$(cat $FRONT 2>/dev/null)" = "1" ]; then
      am broadcast -a com.bearwall.POWERDOWN >/dev/null 2>&1 &
      sleep 2.5
    fi
    echo 0 > $LCD; sleep 0.2; echo 0 > $PWR; log -t bearwall_power "sleep"
  fi
done
