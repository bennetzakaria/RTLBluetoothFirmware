#!/bin/zsh
# load_test.sh — non-interactive. Force-loads the kext with kmutil and reports
# exactly what the kernel does with it. Decisive diagnostic for "is the binary
# good / does it match the dongle / why does OpenCore drop it".
#
#   sudo ./load_test.sh
#
# Leave the UB500 plugged in. (kmutil needs the bundle owned root:wheel, so we
# stage a root-owned copy first.)

PROJ="${0:A:h}"
KEXT="$PROJ/RTLBluetoothFirmware.kext"
BUNDLE_ID="com.opendev.RTLBluetoothFirmware"

if [[ $EUID -ne 0 ]]; then echo "Run with sudo:  sudo ./load_test.sh"; exit 1; fi

echo "=== 0. SIP / kext-signing state ==="
csrutil status 2>/dev/null | sed 's/^/    /'

echo "\n=== 1. Stage a root-owned copy ==="
STAGE="/private/tmp/rtlbt-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$KEXT" "$STAGE/"
chown -R root:wheel "$STAGE/RTLBluetoothFirmware.kext"
chmod -R 755 "$STAGE/RTLBluetoothFirmware.kext"
echo "    staged at $STAGE"

echo "\n=== 2. kmutil load (verbatim output + exit code) ==="
kmutil unload -b "$BUNDLE_ID" 2>/dev/null || true
kmutil load -p "$STAGE/RTLBluetoothFirmware.kext" 2>&1 | sed 's/^/    /'
echo "    >>> exit code: ${pipestatus[1]}"

echo "\n=== 3. Is it resident now? ==="
kmutil showloaded 2>/dev/null | grep -iE "opendev|RTLBluetooth" | sed 's/^/    /' || echo "    NOT resident"

sleep 3
echo "\n=== 4. Did it match the dongle and run? (look for 'start —') ==="
/usr/bin/log show --last 3m --predicate 'eventMessage CONTAINS "RTLBluetoothFirmware"' --style compact 2>/dev/null | tail -30 | sed 's/^/    /'
echo "    --- (end) ---"

echo "\n=== 5. Attached in IORegistry? ==="
ioreg -rn RTLBluetoothFirmware 2>/dev/null | grep -iE "RTLBluetoothFirmware|RTL-Status" | sed 's/^/    /' || echo "    not attached"

echo "\n────────────────────────────────────────────────────────────"
echo "READING THE RESULT:"
echo " • step 2 exit != 0  → the error text IS why OpenCore drops it. Send it to Claude."
echo " • step 2 exit 0 but step 4 empty → binary OK, personality didn't match. Send all output."
echo " • step 4 shows 'start —' and 'download complete' → IT WORKS; just needs to run at boot."
echo "────────────────────────────────────────────────────────────"
