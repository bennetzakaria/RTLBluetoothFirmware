#!/bin/zsh
# install_to_efi.sh — mount the OpenCore EFI, install the freshly built
# RTLBluetoothFirmware.kext (overwriting any old copy), verify, and unmount.
#
#   Run from the project folder:  sudo ./install_to_efi.sh
#
# config.plist already has the kext entry + the Bluetooth NVRAM deletes from
# the earlier session, so this script only swaps the kext binary.

set -e

EFI_DISK="disk0s1"                       # OpenCore EFI (NVRAM boot-path UUID FB66CC0D…)
PROJ="${0:A:h}"                          # directory this script lives in
KEXT="$PROJ/RTLBluetoothFirmware.kext"
EXPECT_SHA="052ca51266caa8e34cd05d4dd53fed9acbf2b5a6d922ce2490b06f108cd86814"

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo:  sudo ./install_to_efi.sh"
  exit 1
fi

echo ">>> Verifying the local build…"
GOT_SHA=$(shasum -a 256 "$KEXT/Contents/MacOS/RTLBluetoothFirmware" | awk '{print $1}')
if [[ "$GOT_SHA" != "$EXPECT_SHA" ]]; then
  echo "WARNING: local binary sha256 ($GOT_SHA) != expected ($EXPECT_SHA)."
  echo "         Did you rebuild? Continuing anyway in 3s…"; sleep 3
else
  echo "    binary sha256 OK"
fi

echo ">>> Mounting $EFI_DISK…"
diskutil mount "$EFI_DISK"
MP=$(diskutil info "$EFI_DISK" | awk -F': *' '/Mount Point/{print $2}')
OC="$MP/EFI/OC"
if [[ ! -d "$OC/Kexts" ]]; then
  echo "ERROR: $OC/Kexts not found — wrong EFI? Aborting."; exit 1
fi

echo ">>> DIAGNOSTICS — current EFI state (why the old kext may not have injected):"
if [[ -d "$OC/Kexts/RTLBluetoothFirmware.kext" ]]; then
  echo "    existing kext on EFI:"
  ls -la "$OC/Kexts/RTLBluetoothFirmware.kext/Contents/MacOS/" 2>/dev/null | sed 's/^/      /'
  echo "      OSBundleRequired in EFI copy: $(/usr/libexec/PlistBuddy -c 'Print :OSBundleRequired' "$OC/Kexts/RTLBluetoothFirmware.kext/Contents/Info.plist" 2>/dev/null || echo '(MISSING — this is why it never injected)')"
else
  echo "    no RTLBluetoothFirmware.kext currently on the EFI"
fi
echo "    config.plist Kernel->Add entry:"
/usr/bin/python3 - "$OC/config.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
ke = [k for k in d["Kernel"]["Add"] if k.get("BundlePath") == "RTLBluetoothFirmware.kext"]
if not ke:
    print("      !!! NO config entry for RTLBluetoothFirmware.kext — OC can't inject it")
else:
    for k in ke:
        print("      ", {kk: k.get(kk) for kk in ("BundlePath","Enabled","ExecutablePath","PlistPath","MinKernel","MaxKernel","Arch")})
PY

echo ">>> Backing up config.plist…"
cp "$OC/config.plist" "$OC/config.plist.bak-$(date +%Y%m%d-%H%M%S)"

echo ">>> Installing kext to $OC/Kexts/…"
rm -rf "$OC/Kexts/RTLBluetoothFirmware.kext"
cp -R "$KEXT" "$OC/Kexts/"

echo ">>> Verifying installed copy…"
if diff -q "$KEXT/Contents/MacOS/RTLBluetoothFirmware" \
           "$OC/Kexts/RTLBluetoothFirmware.kext/Contents/MacOS/RTLBluetoothFirmware" >/dev/null; then
  echo "    installed binary matches build ✓"
else
  echo "    ERROR: installed binary differs!"; exit 1
fi

echo ">>> Ensuring config.plist Kernel->Add entry is present and correct…"
/usr/bin/python3 - "$OC/config.plist" <<'PY'
import plistlib, sys, copy
path = sys.argv[1]
d = plistlib.load(open(path, "rb"))
adds = d["Kernel"]["Add"]
want = {
    "BundlePath": "RTLBluetoothFirmware.kext",
    "ExecutablePath": "Contents/MacOS/RTLBluetoothFirmware",
    "PlistPath": "Contents/Info.plist",
    "Enabled": True, "MinKernel": "21.0.0", "MaxKernel": "", "Arch": "x86_64",
    "Comment": "TP-Link UB500 RTL8761BU Bluetooth firmware loader",
}
ke = [k for k in adds if k.get("BundlePath") == "RTLBluetoothFirmware.kext"]
changed = False
if not ke:
    adds.append(dict(want)); changed = True; print("    entry was MISSING — added")
else:
    for k in ke:
        for key, val in want.items():
            if k.get(key) != val:
                k[key] = val; changed = True
    if changed: print("    entry corrected")
    else: print("    entry already correct")
# make sure it loads after Lilu (move to just before nothing critical — keep order, fine)
if changed:
    plistlib.dump(d, open(path, "wb"))
ke = [k for k in adds if k.get("BundlePath") == "RTLBluetoothFirmware.kext"][0]
print("    final:", {kk: ke.get(kk) for kk in ("Enabled","ExecutablePath","MinKernel","Arch")})
dele = d["NVRAM"]["Delete"].get("7C436110-AB2A-4BBB-A880-FE41995C9F82", [])
print("    BT NVRAM deletes:", [x for x in dele if "bluetooth" in x.lower()])
PY
echo ">>> Re-validating config.plist…"
plutil -lint "$OC/config.plist"

echo ">>> Unmounting EFI…"
diskutil unmount "$EFI_DISK" || true

echo
echo "Done. Now: make sure the UB500 is plugged into a USB-2 port, then reboot."
echo "After reboot, check:  sudo dmesg | grep RTLBluetooth"
