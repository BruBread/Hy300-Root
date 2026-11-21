# Sleep mode, the upside-down panel, and the 180° keystone trick

## The problem

I wanted a sleep mode that actually turns the light off. The projector has two control lines for the LCD:

- `Lcd_en` (`/sys/class/leds/Lcd_en/brightness`) only switches the panel. The LED behind it stays on, so the wall shows an evenly lit rectangle. No energy saved.
- `Lcd_power` (`/sys/class/leds/Lcd_power/brightness`) cuts the panel's power, and the LED goes with it. Fully dark, fan stops.

The catch: after any `Lcd_power` off/on, the panel comes back **upside down** (rotated 180°, not mirrored) and stays that way until a full power cycle. I tried a lot to fix it in hardware: Android sleep/wake, the proper power-then-enable order, toggling the `IO_A`/`IO_B` lines. Nothing flipped it back. The vendor's own "projection mode" setting doesn't use a hardware flip either. It rotates the picture by swapping the keystone corners (`ProjectorModel.newPoint` in their settings app).

## The fix: keep the panel flipped on purpose

1. **Restart the panel once at boot**, before the boot animation, so it's always in the flipped state. Appended to `/vendor/etc/init/hw/init.rk3326.rc`:

   ```
   on post-fs
       exec u:r:su:s0 root root -- /system/bin/sh -c "echo 0 > /sys/class/leds/Lcd_en/brightness; sleep 0.2; echo 0 > /sys/class/leds/Lcd_power/brightness; sleep 0.5; echo 255 > /sys/class/leds/Lcd_power/brightness; sleep 0.5; echo 255 > /sys/class/leds/Lcd_en/brightness"
   ```

2. **Store the keystone corners rotated 180°**, so SurfaceFlinger draws the picture upside down on an upside-down panel, which means right side up on the wall. It covers everything that goes through SurfaceFlinger, boot animation included.
3. **Sleep / wake** in the right order (`scripts/bearwall_power.sh`, `scripts/sleep_mode.bat`):
   - sleep: `Lcd_en` 0, 0.2 s, `Lcd_power` 0
   - wake: `Lcd_power` 255, 0.5 s, `Lcd_en` 255

   The panel is already flipped, so waking can't flip it again.

## The corner math

The keystone props `persist.sys.keystone.{lt,rt,lb,rb}` are `x,y` offsets from that corner of the 1280×720 screen, **y pointing up**. Corner bases: `lt (0,0)`, `rt (1280,0)`, `lb (0,720)`, `rb (1280,720)`. So a prop `ox,oy` puts that image corner at screen `(base_x + ox, base_y - oy)`.

To rotate 180°, keep each label but move its screen point `(x, y)` to `(1280 - x, 720 - y)`, then convert back to an offset. Per corner, from the normal offset `ox,oy` to the stored one:

| Corner | Stored value |
|---|---|
| `lt` | `1280 - ox` , `-720 - oy` |
| `rt` | `-1280 - ox` , `-720 - oy` |
| `lb` | `1280 - ox` , `720 - oy` |
| `rb` | `-1280 - ox` , `720 - oy` |

Example from my unit: normal `lt=0,0 rt=-62,0 lb=16,107 rb=0,204` is stored as `lt=1280,-720 rt=-1218,-720 lb=1264,613 rb=-1280,516`. Apply with `setprop persist.sys.keystone.update 1` and force a redraw (`service call SurfaceFlinger 1022 f 0.999` then `f 1.0`).

**Anything that edits the keystone (a warp UI, presets) must work in normal coordinates and apply this transform when it writes the props.** Reading the props back: apply the same transform again, since it's its own inverse.

## Two more things I learned the hard way

- **Never put Android to sleep on this unit after a debloat.** With nothing holding a wake lock, the chip goes into deep suspend and the RK628 HDMI-in driver panics (`rk628_csi_suspend`, null pointer), which hard-resets the projector. A wake lock at boot (`write /sys/power/wake_lock projectorroot_awake` on `sys.boot_completed`) prevents it.
- `/vendor` is 100% full. Appending to an existing file inside its last block works. Rewriting a file there (for example `sed -i`) truncates it.

## Undo

Delete the `on post-fs` panel block from `init.rk3326.rc` (backup: `/cust/init.rk3326.rc.pre-panelflip`), set the keystone props back to normal values (backup: `/cust/keystone_before_flip.txt`), and power-cycle.

## Update: the boot restart isn't reliable, so the remote can flip the picture

On 2026-11-22 the panel came up the wrong way even though the boot restart ran (`dmesg` showed the `exec` at about 10 s). Software can't tell which way the panel faces, so `scripts/bearwall_power.sh` now turns the picture 180° when POWER is **held 2 s or more**. It applies the corner transform above to the four keystone props, then forces a redraw. The transform is its own inverse, so holding again flips it back. Hold-to-shut-down is gone: a shutdown on this board left the LED lit and the remote dead.
