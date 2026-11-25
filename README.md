# T1 Touch Bar driver for Linux 6.8–7.3+

A small, reproducible DKMS build for the fixed-function Touch Bar on 2016/2017
MacBook Pros with the Apple T1/iBridge chip. It clones the upstream driver at a
pinned commit, applies two patches, and installs the modules. No firmware blobs
or machine-specific NVRAM are included.

## What the patches fix

- **`apple-t1-touchbar-s2idle-resume.patch`** — the upstream HID driver has
  `.suspend` and `.reset_resume` but no ordinary `.resume`. Under `s2idle` the
  iBridge stays powered, so HID takes the ordinary resume path and the driver
  stays internally suspended. The patch routes ordinary resume through the
  existing restore function. This fix is needed on all supported kernels.
- **`apple-t1-touchbar-descriptor-pm.patch`** — three bugs in the upstream
  fork, all visible around suspend/resume:
  1. The iBridge display-control interface's report descriptor contains two
     64-bit fields (page 0xff12, usage 0x51). HID 1.11 §8.4 forbids fields
     wider than 4 bytes, so the kernel logs
     `hid_field_extract() called with n (64) > 32!` whenever the T1 sends a
     report containing one — typically right after resume. The fork's rewrite
     dropped the original driver's `report_fixup()`; this patch restores it
     (splitting the fields into two 32-bit values), with the return type
     adapted per kernel because `struct hid_driver.report_fixup` became
     const-qualified in 6.12.
  2. `appleib_forward_int_op()` contained a stray unconditional `break;`, so
     PM callbacks reached only the first virtual sub-device. The
     ambient-light sensor's `reset_resume()` never ran, leaving the ALS
     unconfigured after every resume (GNOME ambient brightness via
     `iio-sensor-proxy` stops following light changes until reboot).
  3. `appletb_reset_resume()` decided when to restore state from per-interface
     flags that never get set when the iBridge is already runtime-suspended at
     system suspend (the common case once the Touch Bar is idle) — the restore
     then ran once per resume callback, logging `Touchbar resumed.` twice. The
     patch replaces the flags with a two-interface resume mask that restores
     exactly once per resume wave regardless of callback order.
  It also fixes an out-of-bounds read in `appleib_add_device()`'s error unwind.
- **`apple-t1-touchbar-linux73.patch`** — Linux 7.3 removed `struct acpi_driver`
  in commit `541b293ab186` ("ACPI: bus: Eliminate struct acpi_driver"), so the
  upstream driver no longer compiles. The patch registers a `platform_driver`
  against the ACPI-created `APP7777:00` platform device and replaces
  `acpi_driver_data()` with `platform_get_drvdata()`. Applied only on 7.3 and
  newer; do not apply it to older kernels.

## Tested environment

- MacBookPro13,2 (A1706), iBridge `05ac:8600`
- Ubuntu 26.04, kernel `7.0.0-30-generic` (without the 7.3 patch)
- Ubuntu 26.10, kernel `7.3.0-11-generic` (with both patches)

The driver is not model-specific beyond requiring a T1 iBridge in normal
(non-recovery) mode. It should also work on MacBookPro13,x/14,x machines; the
installer checks for `05ac:8600` rather than a board ID. Feedback with your
kernel/model is welcome in issues.

## Install

```bash
git clone https://github.com/bgausden/mbp-t1-touchbar-linux73.git
cd mbp-t1-touchbar-linux73
sudo ./install.sh
sudo reboot
```

The installer:

1. installs `build-essential`, `dkms`, `git`, `patch` and the running kernel's
   headers;
2. refuses to continue if the T1 is in recovery mode (`05ac:1281`) — boot macOS
   to the desktop and shut down cleanly first;
3. clones upstream at the pinned commit, applies the s2idle and descriptor/PM
   patches, and the `platform_driver` patch when `uname -r` is 7.3 or newer;
4. removes any previous DKMS instance, builds and installs for the running
   kernel, and records the provenance in `/usr/src/apple-t1-touchbar-0.1/.source`;
5. blacklists the generic HID sensor drivers, loads `apple-ib-tb`/`apple-ib-als`
   at boot, adds the USB unbind/reprobe rule, and excludes the iBridge from
   `usbmuxd`;
6. regenerates the initramfs.

## Verify

After reboot:

```bash
sudo ./verify.sh
```

Expected: the three modules are loaded, DKMS reports the module installed for
your running kernel, `APP7777:00` is bound to `apple-ibridge` (7.3+), the real
iBridge HID interfaces are bound to `apple-ibridge-hid`, and the live iBridge
report descriptors contain no 64-bit fields (proves the descriptor fixup ran).
`Touchbar resumed` appears in the kernel log after a suspend/resume cycle;
before the first suspend, its absence is normal.

## Wi-Fi on Linux 7.3

Separate from the Touch Bar, kernel 7.3 has a BCM43602 DMA regression
([Ubuntu Launchpad 2169339](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2169339)):
DMAR faults against `0000:02:00.0`, `Failed to reserve space in commonring`,
query timeouts and scan errors, and no association. The verified workaround is
`intel_iommu=off`. See [docs/linux73-wifi.md](docs/linux73-wifi.md). This repo
does not change your boot command line; the Wi-Fi choice is left to you because
it disables Intel IOMMU DMA isolation globally.

For the complete BCM43602 NVRAM, suspend, NVMe and Thunderbolt procedure, see
the [hardware enablement gist](https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2).

## Safety

- **Never reload the Touch Bar modules live.** Reloading only `apple_ib_tb`
  leaves stale sysfs state and a failed second probe; reloading the whole
  iBridge stack made the tested machine unresponsive. Install, then reboot.
- The installer blacklists HID sensor drivers globally. This can disable
  unrelated HID sensors attached to the machine.
- Suspended Thunderbolt storage is not supported by the broader suspend
  procedure linked above. Do not suspend with Thunderbolt storage attached.

## Rollback

```bash
sudo dkms remove apple-t1-touchbar/0.1 --all
sudo rm -rf /usr/src/apple-t1-touchbar-0.1
sudo rm -f /etc/modprobe.d/blacklist-hid-sensor-ibridge.conf
sudo rm -f /etc/modules-load.d/apple-t1-touchbar.conf
sudo rm -f /etc/udev/rules.d/99-apple-t1-touchbar.rules
sudo rm -f /etc/udev/rules.d/39-usbmuxd.rules
sudo update-initramfs -u
sudo reboot
```

Restore `/etc/udev/rules.d/39-usbmuxd.rules.pre-mbp132` if the installer created
it, rather than leaving no override.

## Provenance and licenses

See [NOTICE.md](NOTICE.md). In short: the C sources come from Ronald Tschalär's
GPL-2.0 driver via the pinned upstream fork; the patches are under the same
GPL-2.0 terms; the scripts and documentation here are MIT. The s2idle fix
follows the approach published by michaelahess. No firmware, NVRAM, or Bluetooth
blobs are distributed here.
