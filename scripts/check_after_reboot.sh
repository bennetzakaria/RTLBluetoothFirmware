#!/bin/zsh
# check_after_reboot.sh — run AFTER rebooting with the UB500 plugged in.
# Summarizes whether the firmware upload ran and whether Bluetooth came up.

echo "════════════════════════════════════════════════════════════"
echo " RTLBluetoothFirmware — post-reboot diagnostics"
echo "════════════════════════════════════════════════════════════"

echo "\n[1] Kext firmware-upload log (kernel):"
/usr/bin/log show --last boot --predicate 'eventMessage CONTAINS "RTLBluetoothFirmware"' --style compact 2>/dev/null \
  | sed 's/^/    /' | tail -40
echo "    (if this section is empty: the kext did not run — see [2]/[3])"

echo "\n[2] Is the kext present in the IORegistry?"
ioreg -rn RTLBluetoothFirmware -l 2>/dev/null | grep -E "RTLBluetoothFirmware|RTL-Status" | sed 's/^/    /' \
  || echo "    not attached"

echo "\n[3] UB500 USB device present?"
ioreg -p IOUSB -l -w0 2>/dev/null | grep -A1 "UB500" | grep -iE "UB500|idVendor" | sed 's/^/    /' \
  || echo "    UB500 not enumerated — try a different USB-2 port"

echo "\n[4] Bluetooth NVRAM flags (should NOT show dongle-failed = 01):"
nvram bluetoothExternalDongleFailed 2>/dev/null | sed 's/^/    /' || echo "    (cleared / not set)"

echo "\n[5] Bluetooth controller as macOS sees it:"
system_profiler SPBluetoothDataType 2>/dev/null \
  | grep -iE "Address|State|Chipset|Transport|Vendor ID|Firmware" | sed 's/^/    /'

echo "\n[6] bluetoothd recent transport/controller lines:"
/usr/bin/log show --last 5m --predicate 'process == "bluetoothd"' --style compact 2>/dev/null \
  | grep -iE "transport|controller|usb|reset|fail" | tail -15 | sed 's/^/    /' \
  || echo "    (none)"

echo "\n════════════════════════════════════════════════════════════"
echo " WHAT GOOD LOOKS LIKE:"
echo "   [1] shows 'download complete' then 'device released'"
echo "   [5] Transport: USB  with a real Address (not NULL)"
echo "════════════════════════════════════════════════════════════"
