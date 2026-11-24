# Provenance and licensing

This repository contains no C source files of its own. `install.sh` downloads
the upstream driver at build time.

## Upstream driver

- Project: https://github.com/parport0/mbp-t1-touchbar-driver
- Pinned commit: `6d62f38c6b2c27da1becd311ad7b15826e58ed41`
- Original author: Ronald Tschalär, © 2018
- License: GPL-2.0 (`SPDX-License-Identifier: GPL-2.0` in the source files)
- The `linux/` directory and `dkms.conf` are used from that upstream source.

## Patches

- `patches/apple-t1-touchbar-s2idle-resume.patch` implements the ordinary-resume
  approach described by michaelahess in
  https://github.com/michaelahess/macbook-pro-t1-touchbar-linux (MIT).
- `patches/apple-t1-touchbar-linux73.patch` ports the upstream iBridge driver
  from the removed `struct acpi_driver` API to `platform_driver`.

Because patch files are derivative of the GPL-2.0 source they modify, the
patches are distributed under GPL-2.0, the same terms as the upstream driver.
They must not be treated as MIT-licensed because the surrounding scripts are.

## Scripts and documentation

`install.sh`, `verify.sh`, `README.md` and `docs/` are © 2026 Barry Gausden and
licensed under the MIT license in [LICENSE](LICENSE).

## Not included

No Broadcom firmware, calibrated NVRAM, Bluetooth firmware, or other binary
blobs are included. Those files are proprietary and/or specific to one machine.
The full hardware-enablement runbook, including where to obtain calibrated
NVRAM, lives in
https://gist.github.com/bgausden/c7f8a3737c1e52a260dfcdb1fb2e90b2.
