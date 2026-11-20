# ProjectorRoot

I bought a cheap HY300 projector and wanted root on it. The firmware has developer options ripped out, so this repo is everything I tried to get in, what worked, and a lot of what didn't.

It's sold as a Magcubic/HY300, but inside it's a **Rockchip RK3326** board (`rk3326_sgo`, Android 12 Go, `userdebug/release-keys`) running firmware from a company called **TXCZ**. Out of the box there's no way in. The "tap Build Number 7 times" trick was deleted from the code, and normal boot has no ADB at all.

I got there in the end: persistent ADB and root in normal boot, over Wi-Fi, no cable, and it survives reboots. Below is how, including the dead ends (most of this project was dead ends) and the one firmware mystery I never figured out.

> Everything here was done on a projector I own, to learn and to make it do what I want. Read [Legal & scope](#legal--scope) before trying it on yours. None of this is a remote exploit. It all starts from having the device in your hands and using its own recovery.

> **Security notice:** this projector came with what looks like residential-proxy malware. An app installed by the projector's own settings app was relaying other people's traffic through it, and there was a hidden root toolkit next to it. Evidence, indicators and how I removed it: [MALWARE_FINDINGS.md](MALWARE_FINDINGS.md). If you have an HY300 / TXCZ RK3326 unit, run [`scripts/check_malware.sh`](scripts/check_malware.sh). It only reads, it doesn't change anything.

## Quick facts

| | |
|---|---|
| Device | Magcubic / HY300-branded projector |
| Actual chip | Rockchip RK3326 (`rk3326_sgo`), 4× Cortex-A35, Android 12 Go |
| Firmware | `userdebug/release-keys`, reskinned by TXCZ (`com.shzhtxcz.txbox` pretending to be `com.android.tv.settings`) |
| Goal | Persistent ADB + root in normal boot (stock gives you neither) |
| Result | Done. `adb connect PROJECTOR_IP:5555`, `adb root`, `uid=0 (u:r:su:s0)`, survives reboots |
| Still unsolved | `/system` edits get wiped every boot, by something in U-Boot or earlier |
| Tools | Stock recovery root, liblp loop-mounts, jadx, my own AXML/DEX parsers, capstone, Ghidra 12.1.3 |
| Attempts logged | 20, each with why I tried it, in [PROGRESS_LOG.md](PROGRESS_LOG.md) |

## What I wanted to do with it

The hardware is fine. The software is the problem, and none of it is mine. Once I had root, the plan was:

- Debloat it. Get rid of the TXCZ launcher and its bundled apps, put a clean launcher on.
- Control it from my PC with `adb` and `scrcpy` instead of the cut-down settings menu.
- Block ads and tracking, and see what the OEM apps phone home with.
- Turn it on and off and launch apps from Home Assistant.
- Long shot: the same RK3326 runs mainline Linux on handhelds like the Odroid Go Advance and Anbernic RG351. A real custom OS would mean porting the projector's display, keystone and focus drivers. Months of work and probably not worth it, but at least it's possible.

None of that needs `/system` to be writable. It all lives in `/data`, so persistent ADB was the thing to get.

## What I've built on it since

Once root worked, I kept going:

- **Projection mapping.** A browser page that warps the picture live by dragging the 4 corners, plus shape masks so only a circle or polygon is lit. It runs off the projector's own keystone. See [`keystone/`](keystone/).
- **Sleep mode.** Turns the light and fan off without shutting the projector down, so it wakes instantly ([`scripts/sleep_mode.bat`](scripts/sleep_mode.bat)). Found the right control line by testing them one by one. The wrong one powered off the LCD panel, and it came back upside down.
- **Custom boot screen.** My own static logo and a CRT-style boot animation ([`scripts/make_static_logo.py`](scripts/make_static_logo.py), [`scripts/make_crt_bootanim.py`](scripts/make_crt_bootanim.py)).
- **PC streaming.** One click streams my desktop to the projector with Sunshine and Moonlight ([`scripts/cast_to_projector.bat`](scripts/cast_to_projector.bat)).
- **HDMI auto-switch and brightness control** ([`scripts/hdmi_autoswitch.sh`](scripts/hdmi_autoswitch.sh), [`scripts/brightness.bat`](scripts/brightness.bat)).
- **Found and removed the malware** it shipped with ([MALWARE_FINDINGS.md](MALWARE_FINDINGS.md)).

## How I get in

Two things always work, and everything else builds on them:

- **Recovery root.** Hold the power button while powering on and you land in the stock AOSP recovery. There, `adb root` gives you a root shell (`uid=0`, context `u:r:su:s0`) every single time, no exploit needed. Nobody locked this build down.
- **Mounting partitions from recovery.** `/data` is plain ext4 and mounts directly. `/system` isn't its own partition. It's a logical volume inside the dynamic `super` partition, and recovery's "Mount /system" is broken on this board. So I read `super`'s liblp metadata header by hand to find where it sits and loop-mounted it:

  ```sh
  losetup -f -s -o 1048576 -S 800915456 /dev/block/by-name/super
  mount -t ext4 -o rw /dev/block/loop0 /mnt_system
  ```

The catch: normal boot has no ADB, and the usual unlock is gone. Recovery root can't just flip the switch either. The setting that controls ADB (`Settings.Global.adb_enabled`) is in `/data/system`, which is **FBE-encrypted**, and the keys only exist once Android has booted.

## How I got permanent ADB + root

There are two separate locks, and they don't fail the same way.

1. `/data/local.prop` is plain text and **stays** across reboots (unlike `/system`, more on that below). From recovery root I added:

   ```properties
   persist.sys.usb.config=mtp,adb
   persist.service.adb.enable=1
   persist.adb.tcp.port=5555
   service.adb.tcp.port=5555
   ```

2. The build is `userdebug` (`ro.debuggable=1`), so init reads `local.prop` early in boot. ADB (USB and TCP 5555) comes up for about **one second**. Then `system_server`'s `UsbDeviceManager` sees `adb_enabled=0` and kills it. I tried catching that second by hand a bunch of times and always missed.

3. So I scripted it ([`scripts/race.sh`](scripts/race.sh)). The moment ADB shows up, it spams `settings put global adb_enabled 1` over USB and Wi-Fi until it sticks. It got in on **try 3, about 1 s** in. Once the running system has written `adb_enabled=1` into the encrypted settings database, `UsbDeviceManager` reads `1` and leaves ADB on.

4. `ro.adb.secure` was unset, so there's no RSA prompt. ADB is trusted right away and `adb root` works (userdebug). That also means anything on your network gets root. After I found the malware I turned authorization on with my PC's key ([how](MALWARE_FINDINGS.md#closing-my-own-hole)). Do that once you're in.

The prop trick only gives you about one second. What actually makes it stick is flipping the real `adb_enabled` setting inside that second, while Android is running, through the settings provider that recovery can't reach.

After `adb reboot` the projector came back on its own at `PROJECTOR_IP:5555`, `adb_enabled=1`, port 5555 listening, `adb root` gives `uid=0`. No cable, no second race. You only race once.

## The mystery I didn't solve: `/system` resets every boot

Any change to `/system`, even a brand-new file, is gone after the next boot. Same bytes as stock, mtime back to the `1970-01-01` build date, new inode every time. That isn't something watching for changes. Something rewrites the whole partition from a reference copy.

I spent most of this project chasing it and ruled out a lot:

- **It happens below Android.** Rebooting straight back into recovery still wipes the edits, and recovery shares no Android code with normal boot. That kills every Android-side idea at once: overlayfs, `txcz_ota`, fstab dm-verity, the reserved eMMC area, the (empty) `backup` partition.
- **It's not U-Boot's boot path.** I found U-Boot's load address and command table from raw bytes ([`scripts/find_cmdtbl.py`](scripts/find_cmdtbl.py), [`scripts/walk_cmdtbl.py`](scripts/walk_cmdtbl.py)) and traced `do_boot_android` and `do_bootrkp` all the way through in Ghidra. Both only read. None of the seven partition-write functions I was looking for are reachable. `boot_fit` doesn't even exist as a command in this build (no gap for it in the command table).
- **It's older than my build.** Compared against a stock ROM from 7 months earlier, `do_boot_android` and `do_bootrkp` are identical instruction for instruction, and `trust.bin` is byte-identical. So `uboot.bin` is out on both versions.

My best guess is a custom TXCZ addition (stock Rockchip U-Boot doesn't do this) in either the **pre-GPT idbloader/SPL stage** that runs before U-Boot (dumped, no suspicious strings, never disassembled) or the **TEE** (`trust.bin`, only string-scanned). Fixing it for real means patching and reflashing `uboot`/`trust`. If that goes wrong the only way back is Maskrom, which needs the case opened, so I stopped there. Details in [PROGRESS_LOG.md](PROGRESS_LOG.md), attempts 11–19.

It doesn't get in the way. ADB and root live in `/data`, which never resets.

## Do it on your own board

You need the projector, a USB cable, a PC with `adb`, and the same `rk3326_sgo` userdebug firmware (check `getprop ro.build.fingerprint` in recovery). Roughly:

1. Boot to recovery (hold power while powering on), then `adb root`.
2. Mount userdata: `mount -t ext4 /dev/block/by-name/userdata /mnt_data`. *(On Git Bash, run `export MSYS_NO_PATHCONV=1` first or the path gets mangled.)*
3. Add the four `persist.*`/`service.*` lines above to `/mnt_data/local.prop`, then `sync; umount /mnt_data`.
4. `adb reboot`, then right away run [`scripts/race.sh`](scripts/race.sh) `<logfile>` on your PC.
5. When it says `adb_enabled` stuck, you have permanent normal-boot ADB. `adb root` for root.
6. Turn on ADB authorization and run [`scripts/check_malware.sh`](scripts/check_malware.sh).

This only works on a **userdebug** build with `ro.adb.secure` unset. A `user` build needs a different way in.

## What's in here

```
README.md              this file
PROGRESS_LOG.md        every attempt and why, 20 of them
MALWARE_FINDINGS.md    the proxy malware it shipped with, how to spot it, how I removed it
SAFETY_PLAYBOOK.md     the backup-first rules and brick-recovery notes I followed
scripts/               everything I wrote (table below)
scripts/ghidra/        headless Ghidra scripts for the U-Boot tracing
keystone/              the projection-mapping controller (warp + shape masks)
backups/               firmware and config pulled from my unit (boot, vbmeta, uboot, trust, super header, init.rc)
analysis/              the evidence: hypothesis results (JSON), kernel logs, Ghidra logs, malware evidence
```

### Scripts

| Script | What it does |
|--------|--------------|
| [`scripts/race.sh`](scripts/race.sh) | The one that got me in. Races `adb_enabled=1` into the ~1 s early-boot window over USB and Wi-Fi until it sticks. |
| [`scripts/check_malware.sh`](scripts/check_malware.sh) | Read-only check for the preinstalled proxy malware: apps, hidden files, port-9000 connections, `daemon12138`. See [MALWARE_FINDINGS.md](MALWARE_FINDINGS.md). |
| [`scripts/sleep_mode.bat`](scripts/sleep_mode.bat) | Turns the light (and fan) off and on without shutting down. Toggles, or takes `sleep` / `wake`. |
| [`scripts/find_cmdtbl.py`](scripts/find_cmdtbl.py) | Finds U-Boot's command table in a raw image and works out this build's `cmd_tbl_s` layout. |
| [`scripts/walk_cmdtbl.py`](scripts/walk_cmdtbl.py) | Walks the table from one known entry to get the whole command list. No Ghidra needed. |
| [`scripts/fullscan.py`](scripts/fullscan.py) | Threaded TCP port scan (1–65535) of the projector over the LAN. |
| [`scripts/banner.py`](scripts/banner.py) · [`scripts/http.py`](scripts/http.py) | Banner grab and HTTP probe on the open ports. Turned out to be just a screen-casting stack. |
| [`scripts/axml_dump.py`](scripts/axml_dump.py) | Decodes a binary `AndroidManifest.xml` without aapt. |
| [`scripts/dex_strings.py`](scripts/dex_strings.py) | Dumps the string pool from a `classes.dex` so you can grep it. |
| [`scripts/ghidra/`](scripts/ghidra/) | Headless Ghidra scripts that walk the `do_boot_android`/`do_bootrkp` call graphs and flag any block write. |
| [`keystone/keystone.py`](keystone/keystone.py) | Projection-mapping controller. Serves a page to any browser on the LAN (phone or laptop). **Warp** drags the projector's built-in 4-corner keystone live through `persist.sys.keystone.*`. **Shape** masks everything outside a circle, line or polygon, drawn by [`keystone/helper/ProjMap.java`](keystone/helper/ProjMap.java), which runs on the projector through `app_process` and owns a layer on top of everything. Has presets and a projected alignment grid. Run `keystone/keystone.bat`, or [`ProjectorControl.bat`](ProjectorControl.bat) to also stream the PC desktop (C in its window opens the page; the grid button switches between grid and stream). |

## Legal & scope

- The projector is mine. This is interoperability and security research on hardware I own. Nothing here gets around any remote protection. It all starts from physical access and the vendor's own recovery.
- I'm not affiliated with Magcubic, TXCZ or Rockchip. "HY300" is a name slapped on unrelated hardware, and guides for the Allwinner "HY300 Pro" do **not** apply to this Rockchip board.
- The firmware images in `backups/` belong to their vendors. They're here as reference dumps from my unit, not licensed to you. Dump your own.
- Only do this on a device you own, and read [SAFETY_PLAYBOOK.md](SAFETY_PLAYBOOK.md) first. The `/system` section above explains why I didn't reflash the bootloader.

## License

My own code and writeups (everything in `scripts/`, the Markdown docs and `analysis/`) are MIT, see [LICENSE](LICENSE). The firmware images in `backups/` are not covered and still belong to their owners.
