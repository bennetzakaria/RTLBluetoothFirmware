#!/bin/zsh
# capture_scan.sh — records the Bluetooth daemon log across the "devices appear
# then vanish after ~4s" window so we can see exactly which command the Realtek
# controller rejects. Read-only, zero risk. Does NOT need sudo.
#
#   ./capture_scan.sh
#
# Then paste the "KEY EVENTS" block back to Claude.

OUT=/tmp/scan_capture.txt

echo "════════════════════════════════════════════════════════════"
echo " Bluetooth scan-death capture"
echo "════════════════════════════════════════════════════════════"
echo "1. In System Settings → Bluetooth, turn Bluetooth OFF."
echo "2. Wait 3 seconds."
echo "3. Turn Bluetooth ON and keep the Bluetooth settings window OPEN"
echo "   (watch 'Nearby Devices')."
echo
echo "Press Enter the MOMENT you've turned it back ON…"
read _

echo ">>> Capturing 30 seconds (let the devices appear and then vanish)…"
/usr/bin/log stream --predicate 'process == "bluetoothd"' --info --debug --style compact > "$OUT" 2>&1 &
LPID=$!
# wait without a foreground sleep loop
for i in $(seq 1 30); do sleep 1; printf '.'; done
echo
kill "$LPID" 2>/dev/null

echo "\n════════════════════ KEY EVENTS (paste this) ════════════════════"
grep -iE "scan ?enable|inquiry|discoverab|page scan|0x0c1a|0x2042|0x2041|0x0405|reset|powered|controller|fail|error|status 0x0[1-9a-f]|invalidat|timeout" "$OUT" \
  | grep -ivE "WiFiManager|xpc:connection|rescan timer|AdvertisingRules|kCBAdvData" \
  | tail -50
echo "════════════════════════════════════════════════════════════════"
echo "(Full log saved at $OUT — $(wc -l < "$OUT") lines.)"
