#!/usr/bin/env bash
# Build and install the T1 Touch Bar DKMS module with the s2idle and
# Linux 7.3+ platform-driver patches. See README.md before running.
set -euo pipefail

UPSTREAM=https://github.com/parport0/mbp-t1-touchbar-driver.git
COMMIT=6d62f38c6b2c27da1becd311ad7b15826e58ed41
NAME=apple-t1-touchbar
VERSION=0.1
SRC=/usr/src/${NAME}-${VERSION}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

[[ $EUID -eq 0 ]] || die 'run with sudo'
[[ -f $HERE/patches/apple-t1-touchbar-s2idle-resume.patch ]] || die 'patches directory is missing'
[[ -f $HERE/patches/apple-t1-touchbar-linux73.patch ]] || die 'patches directory is missing'
[[ -f $HERE/dkms.conf ]] || die 'dkms.conf is missing'

kernel_release=$(uname -r)
kernel_version=${kernel_release%%-*}
IFS=. read -r kernel_major kernel_minor _ <<<"$kernel_version"
kernel_minor=${kernel_minor:-0}
need_linux73=false
if (( kernel_major > 7 || (kernel_major == 7 && kernel_minor >= 3) )); then
	need_linux73=true
fi

echo '== Installing build dependencies =='
apt-get update
apt-get install -y build-essential dkms git patch usbutils "linux-headers-${kernel_release}"

echo '== Checking T1 iBridge state =='
if lsusb | grep -q '05ac:1281'; then
	die 'T1 is in recovery mode; boot full macOS to the desktop and shut down cleanly'
fi
lsusb | grep -q '05ac:8600' || die 'Apple iBridge 05ac:8600 not found'

echo '== Fetching pinned upstream driver and applying patches =='
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone "$UPSTREAM" "$work/driver"
git -C "$work/driver" checkout --detach "$COMMIT"
patch -d "$work/driver" -p1 < "$HERE/patches/apple-t1-touchbar-s2idle-resume.patch"
if $need_linux73; then
	echo 'Applying Linux 7.3+ platform-driver patch'
	patch -d "$work/driver" -p1 < "$HERE/patches/apple-t1-touchbar-linux73.patch"
fi

echo '== Installing DKMS module =='
if dkms status | grep -q "^${NAME}/${VERSION}"; then
	dkms remove "${NAME}/${VERSION}" --all
fi
rm -rf "$SRC"
install -d -m 755 "$SRC"
install -m 644 "$work/driver"/{apple-ib-als.c,apple-ib-tb.c,apple-ibridge.c,Makefile} "$SRC/"
cp -a "$work/driver/linux" "$SRC/linux"
install -m 644 "$HERE/dkms.conf" "$SRC/dkms.conf"
cat > "$SRC/.source" <<EOF
upstream=$UPSTREAM
commit=$COMMIT
patch=apple-t1-touchbar-s2idle-resume.patch
EOF
if $need_linux73; then
	echo 'patch=apple-t1-touchbar-linux73.patch' >> "$SRC/.source"
fi
dkms add -m "$NAME" -v "$VERSION"
dkms build -m "$NAME" -v "$VERSION"
dkms install -m "$NAME" -v "$VERSION"

echo '== Reserving iBridge interfaces for the Touch Bar driver =='
cat > /etc/modprobe.d/blacklist-hid-sensor-ibridge.conf <<'EOF'
blacklist hid_sensor_hub
blacklist hid_sensor_als
blacklist hid_sensor_trigger
blacklist hid_sensor_iio_common
EOF
cat > /etc/modules-load.d/apple-t1-touchbar.conf <<'EOF'
apple-ib-tb
apple-ib-als
EOF
cat > /etc/udev/rules.d/99-apple-t1-touchbar.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="8600", RUN+="/bin/sh -c 'echo -n %k > /sys/bus/usb/drivers/usb/unbind; echo -n %k > /sys/bus/usb/drivers_probe'"
EOF

usbmux_src=/lib/udev/rules.d/39-usbmuxd.rules
usbmux_dst=/etc/udev/rules.d/39-usbmuxd.rules
if [[ -f $usbmux_src ]]; then
	grep -q '5ac/8600/\*' "$usbmux_src" || die 'usbmuxd rule format changed; exclude 05ac:8600 manually'
	if [[ -e $usbmux_dst && ! -e ${usbmux_dst}.pre-mbp132 ]]; then
		cp -a "$usbmux_dst" "${usbmux_dst}.pre-mbp132"
	fi
	cp "$usbmux_src" "$usbmux_dst"
	sed -i 's#|5ac/8600/\*##g' "$usbmux_dst"
	grep -q '5ac/8600' "$usbmux_dst" && die 'failed to exclude iBridge from usbmuxd'
fi

udevadm control --reload-rules
update-initramfs -u

echo
echo 'Installation complete.'
echo 'Do not live-reload the Touch Bar modules. Reboot, then run:'
echo "  sudo bash $HERE/verify.sh"
