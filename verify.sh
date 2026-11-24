#!/usr/bin/env bash
# Post-install checks for the patched T1 Touch Bar driver. See README.md.
set -u

failures=0
warnings=0

pass() { printf 'PASS: %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

kernel_release=$(uname -r)
kernel_version=${kernel_release%%-*}
IFS=. read -r kernel_major kernel_minor _ <<<"$kernel_version"
kernel_minor=${kernel_minor:-0}
need_linux73=false
if (( kernel_major > 7 || (kernel_major == 7 && kernel_minor >= 3) )); then
	need_linux73=true
fi

src=/usr/src/apple-t1-touchbar-0.1

if lsusb 2>/dev/null | grep -q '05ac:8600'; then
	pass 'T1 iBridge 05ac:8600 is present'
else
	fail 'T1 iBridge 05ac:8600 is missing (check for 05ac:1281 recovery mode)'
fi

for module in apple_ibridge apple_ib_tb apple_ib_als; do
	if grep -q "^${module}" /proc/modules 2>/dev/null; then
		pass "$module is loaded"
	else
		fail "$module is not loaded"
	fi
done

if dkms status 2>/dev/null | grep -q "^apple-t1-touchbar/0.1, ${kernel_release},.*installed"; then
	pass "DKMS module is installed for $kernel_release"
else
	fail "DKMS module is not installed for $kernel_release"
fi

if grep -q '^commit=6d62f38c6b2c27da1becd311ad7b15826e58ed41$' "$src/.source" 2>/dev/null; then
	pass 'upstream source commit is pinned'
else
	fail 'upstream source marker is missing or changed'
fi

if grep -q '^\s*\.resume = appletb_reset_resume,' "$src/apple-ib-tb.c" 2>/dev/null; then
	pass 's2idle ordinary-resume patch is present'
else
	fail 's2idle ordinary-resume patch is missing'
fi

bindings=$(find /sys/bus/hid/drivers/apple-ib-touchbar -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | grep -cE '^[0-9A-Fa-f]{4}:' || true)
[[ $bindings -eq 2 ]] && pass 'both virtual Touch Bar HID devices are bound' || fail "virtual Touch Bar HID binding count is $bindings, expected 2"

physical=$(find /sys/bus/hid/drivers/apple-ibridge-hid -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | grep -cE '^[0-9A-Fa-f]{4}:' || true)
[[ $physical -eq 2 ]] && pass 'both physical iBridge HID interfaces are bound' || fail "physical iBridge HID binding count is $physical, expected 2"

if $need_linux73; then
	if grep -q '^static struct platform_driver appleib_driver' "$src/apple-ibridge.c" 2>/dev/null; then
		pass 'Linux 7.3 platform-driver patch is present'
	else
		fail 'Linux 7.3 platform-driver patch is missing'
	fi
	platform_driver=$(readlink /sys/bus/platform/devices/APP7777:00/driver 2>/dev/null || true)
	[[ $platform_driver == *apple-ibridge* ]] && pass 'APP7777:00 is bound to apple-ibridge' || fail "APP7777:00 driver is ${platform_driver:-none}"
	virtual_count=$(find /sys/bus/hid/devices -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | grep -cE '^0003:1D6B:030[12]' || true)
	[[ $virtual_count -eq 4 ]] && pass 'four virtual Touch Bar/ALS HID devices exist' || fail "virtual HID device count is $virtual_count, expected 4"
	grep -qw intel_iommu=off /proc/cmdline || warn 'intel_iommu=off is not active; see docs/linux73-wifi.md if BCM43602 Wi-Fi fails'
else
	if grep -q '^static struct acpi_driver appleib_driver' "$src/apple-ibridge.c" 2>/dev/null; then
		pass 'ACPI driver source is in its expected pre-7.3 form'
	else
		warn 'unexpected apple-ibridge.c driver form for a pre-7.3 kernel'
	fi
fi

if journalctl -b -k --no-pager 2>/dev/null | grep -q 'Touchbar resumed'; then
	pass 'Touch Bar resume callback has run this boot'
else
	warn 'no Touchbar resumed message yet (normal before first suspend)'
fi

printf '\nSummary: %d failure(s), %d warning(s)\n' "$failures" "$warnings"
(( failures == 0 ))
