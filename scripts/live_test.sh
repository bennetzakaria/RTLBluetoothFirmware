#!/bin/zsh
# live_test.sh — load the kext into the RUNNING kernel and upload firmware to
# the UB500 without rebooting. Proves the binary works before committing to a
# permanent OpenCore install. Requires sudo (SIP kext-signing is disabled).
#
#   sudo ./live_test.sh
#
# Why the unplug/replug: bluetoothd already holds the dongle open in ROM mode.
# Loading the kext, then replugging, lets our driver claim the freshly
# enumerated device FIRST, upload firmware, and release it for bluetoothd.

set -e
PROJ="${0:A:h}"
KEXT="$PROJ/RTLBluetoothFirmware.kext"
BUNDLE_ID="com.opendev.RTLBluetoothFirmware"

if [[ $EUID -ne 0 ]]; then echo "Run with sudo:  sudo ./live_test.sh"; exit 1; fi

echo ">>> 1. Unplug the UB500 dongle now."
echo "       Then press Enter."
read _

echo ">>> 2. Loading the kext into the kernel…"
# kmutil requires the bundle to be owned by root:wheel. The project folder is
# owned by the user, so stage a root-owned copy and load that.
STAGE="/private/tmp/rtlbt-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$KEXT" "$STAGE/"
chown -R root:wheel "$STAGE/RTLBluetoothFirmware.kext"
chmod -R 755 "$STAGE/RTLBluetoothFirmware.kext"

# Unload a previous live copy if present (ignore errors)
kmutil unload -b "$BUNDLE_ID" 2>/dev/null || true
echo "    --- kmutil load output (verbatim) ---"
kmutil load -p "$STAGE/RTLBluetoothFirmware.kext" 2>&1 | sed 's/^/    /'
LOAD_RC=${pipestatus[1]}
echo "    --- kmutil load exit code: $LOAD_RC ---"
if [[ $LOAD_RC -ne 0 ]]; then
  echo "    >>> kmutil REFUSED to load the kext. The message above is the"
  echo "        same reason OpenCore silently drops it. Copy it back to Claude."
  exit 1
fi
echo "    confirming it is resident:"
kmutil showloaded 2>/dev/null | grep -iE "opendev|RTLBluetooth" | sed 's/^/      /' || echo "      (NOT resident despite exit 0 — unexpected)"

echo ">>> 3. Plug the UB500 back in. Wait ~5 seconds, then press Enter."
read _
sleep 3

echo "\n>>> 4. Firmware-upload log:"
/usr/bin/log show --last 2m --predicate 'eventMessage CONTAINS "RTLBluetoothFirmware"' --style compact 2>/dev/null \
  | tail -30 | sed 's/^/    /'

echo "\n>>> 5. Is our driver attached to the dongle?"
ioreg -rn RTLBluetoothFirmware 2>/dev/null | grep -E "RTLBluetoothFirmware|RTL-Status" | sed 's/^/    /' \
  || echo "    (not attached — see log above)"

echo "\n>>> 6. Controller state (want: real Address, firmware != 0x8761/0x0B):"
system_profiler SPBluetoothDataType 2>/dev/null \
  | grep -iE "Address|State|Chipset|Firmware|Transport" | sed 's/^/    /'

echo "\n────────────────────────────────────────────────────────────"
echo "If the log shows 'download complete', the upload worked. Now make it"
echo "permanent so it happens every boot:   sudo ./install_to_efi.sh   then reboot."
echo "(The live-loaded kext does NOT survive reboot.)"
