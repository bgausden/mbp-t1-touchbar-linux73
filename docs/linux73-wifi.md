# BCM43602 Wi-Fi on Linux 7.3

This is a kernel regression, separate from both the Touch Bar build break and
the old suspend problem. It was observed on a MacBookPro13,2 with BCM43602 PCIe
`14e4:43ba`, firmware `7.35.177.61`, on kernel `7.3.0-11-generic`. The same
calibrated NVRAM and firmware worked on `7.0.0-44-generic`.

## Symptoms

Kernel log:

```text
DMAR: DRHD: handling fault status reg 2
DMAR: [DMA Read NO_PASID] Request device [0000:02:00.0] fault addr ... [fault reason 0x06] PTE Read access is not set
brcmf_msgbuf_tx_ioctl: Failed to reserve space in commonring
brcmf_run_escan: error (-12)
brcmf_cfg80211_scan: scan error (-12)
Timeout on response for query command
```

The interface stays down, scans return nothing, and association never
completes. Upstream report:
https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2169339

## Workaround

Disable the Intel IOMMU for DMA translation:

```bash
sudo mkdir -p /etc/default/grub.d
printf '%s\n' 'GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} intel_iommu=off"' |
  sudo tee /etc/default/grub.d/99-intel-iommu-off.cfg
sudo update-grub
sudo reboot
```

After reboot:

```bash
grep -o intel_iommu=off /proc/cmdline
nmcli device status
journalctl -b -k --no-pager | grep -E 'DMAR|commonring|scan error|Timeout on response'
```

On the tested machine the interface came up normally, scanned, associated to
WPA2, and the current boot's journal had zero DMAR faults, query timeouts or
scan errors.

## Tradeoffs

- `intel_iommu=off` disables Intel IOMMU DMA isolation for all devices, not just
  Wi-Fi. Do not use it if that isolation is a security requirement.
- If you need IOMMU enabled, boot the last working 7.0 kernel until the upstream
  bug is fixed.
- Do not replace the machine's NVRAM with a generic file, and do not add
  `sup_wpa=0`, `roamoff` or `feature_disable` overrides. None of those fix this
  regression.
- Module reloads and PCI remove/rescan make BCM43602 state worse on this
  hardware. Reboot after changing boot parameters.
