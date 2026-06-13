# RTLBluetoothFirmware

**Realtek RTL8761B / RTL8761BU Bluetooth firmware loader for macOS (OpenCore Hackintosh).**

Makes the **TP-Link UB500** (and other RTL8761BU USB dongles) work as a real
Bluetooth controller on macOS 12 – 26, by uploading the Realtek firmware at boot
— exactly the way Linux's `btrtl` driver does, reimplemented as an IOKit kext.

> The RTL8761BU ships with **no firmware**. Linux uploads `rtl8761bu_fw.bin` via
> HCI vendor commands before the generic Bluetooth stack takes over. macOS has no
> driver that does this, which is why every guide says *"Realtek is unsupported on
> macOS — buy a Broadcom dongle."* This kext does the firmware upload, then hands
> the controller to macOS's own `bluetoothd` (patched by **BlueToolFixup**).

Confirmed working on **macOS 26 (Tahoe)**, OpenCore 1.0.7, Intel — phone + audio
(A2DP/HFP/AVRCP) connected, battery reporting, HID.

---

## Status / what works

| | |
|---|---|
| Firmware upload at boot | ✅ automatic, every boot |
| Controller adopted by macOS | ✅ `THIRD_PARTY_DONGLE`, real BD_ADDR |
| Pairing / connecting | ✅ |
| Audio (A2DP / HFP / AVRCP) + battery | ✅ |
| HID (mice/keyboards) | ✅ |
| Discovering *brand-new* devices | ⚠️ finicky — macOS runs only a short inquiry on this chip; put a device in pairing mode and click it promptly |
| Apple Continuity (Handoff / AirDrop-to-Apple / Universal Clipboard) | ❌ needs genuine Apple BT+Wi-Fi hardware — not a dongle limitation we can fix |

## Download

- **Prebuilt kext** — grab the latest `.kext` from the **[Releases page](https://github.com/bennetzakaria/RTLBluetoothFirmware/releases)**.
- **Build from source** — run `make` (see [Build](#build); the firmware is fetched automatically).

> 🛒 **Don't have the adapter yet?**
> This kext is for the **TP-Link UB500 (Realtek RTL8761BU)** → **[get it on Amazon](https://www.amazon.com/s?k=TP-Link+UB500&tag=bennzo-20)** *(verify it's the RTL8761BU revision — see [Get the hardware](#get-the-hardware))*.
> Want Bluetooth with **zero setup**? A **[CSR8510 dongle](https://www.amazon.com/s?k=csr8510+a10+bluetooth&tag=bennzo-20)** works on macOS with **no kext at all**.
> *(Affiliate links — buying through them supports the project at no extra cost. Full disclosure below.)*

## Supported hardware

- **TP-Link UB500** — Realtek **RTL8761BU**, USB `VID 0x2357 / PID 0x0604`
- Other RTL8761BU dongles: add your `VID/PID` to `Info.plist` (`IOKitPersonalities`).
- RTL8761B (UART) and other Realtek BT chips are **not** covered by this build,
  though the approach generalizes (different firmware file + ID).

## Get the hardware

> **Affiliate disclosure:** As an Amazon Associate I earn from qualifying
> purchases. Some links below are Amazon affiliate links — buying through them
> supports this project at no extra cost to you.

<!-- Links carry the maintainer's Amazon Associate tag (bennzo-20). For
     product-specific links with images, regenerate via Associates Central →
     SiteStripe → "Get Link"; the tag is embedded automatically. -->

| Goal | Where | Read this first |
|---|---|---|
| **Make *this project* work** | [TP-Link UB500](https://www.amazon.com/s?k=TP-Link+UB500&tag=bennzo-20) | **Verify the chip is RTL8761BU** — the BT 5.0/5.1 *nano* version that reports `VID 0x2357 / PID 0x0604`. Newer **"UB500 Plus" / BT 5.3 / 5.4** revisions may use a different chip and are **not guaranteed** to work with this firmware. |
| **Bluetooth with zero hassle** | [CSR8510 A10 dongle](https://www.amazon.com/s?k=csr8510+a10+bluetooth&tag=bennzo-20) | `bluetoothd` supports **CSR** natively — works out of the box on macOS, **no kext at all**. The easiest path if you just want it to work. |
| **Broadcom (well-supported)** | [BCM20702 USB Bluetooth](https://www.amazon.com/s?k=BCM20702+USB+Bluetooth&tag=bennzo-20) | Needs `BrcmPatchRAM3` + `BrcmFirmwareData` (standard, low-risk kexts). |
| **Better placement / range** | [USB 2.0 extension cable](https://www.amazon.com/s?k=USB+2.0+extension+cable&tag=bennzo-20) | Keeps the dongle off a crowded or USB-3 port — often improves stability. |

## Requirements

- macOS 12 (Monterey) – 26 (Tahoe), Intel `x86_64`
- **OpenCore** with kext injection
- **[Lilu](https://github.com/acidanthera/Lilu)** + **[BlueToolFixup](https://github.com/acidanthera/BrcmPatchRAM)** (BlueToolFixup is what lets `bluetoothd` accept a non-Apple controller — required)
- `SecureBootModel = Disabled` in your OpenCore config (this kext is ad-hoc signed), which is standard for kext-injection hackintoshes
- **Xcode Command Line Tools** (or full Xcode) to build

---

## Build

```sh
git clone https://github.com/<you>/RTLBluetoothFirmware.git
cd RTLBluetoothFirmware
make
```

`make` automatically downloads the Realtek firmware (`rtl8761bu_fw.bin` +
`rtl8761bu_config.bin`) from kernel.org's `linux-firmware`, embeds it into the
kext, compiles, and ad-hoc signs. The firmware blobs are **not** redistributed in
this repo (Realtek's license) — they're fetched at build time.

Result: `RTLBluetoothFirmware.kext`.

## Install (OpenCore)

1. Mount your OpenCore EFI:
   ```sh
   sudo diskutil mount diskXsY        # your EFI partition
   ```
2. Copy the kext:
   ```sh
   cp -R RTLBluetoothFirmware.kext /Volumes/EFI/EFI/OC/Kexts/
   ```
3. Add it to `config.plist → Kernel → Add` (ProperTree OC Snapshot, or by hand):
   - `BundlePath` = `RTLBluetoothFirmware.kext`
   - `ExecutablePath` = `Contents/MacOS/RTLBluetoothFirmware`
   - `PlistPath` = `Contents/Info.plist`
   - `MinKernel` = `21.0.0`, `Enabled` = `true`, `Arch` = `x86_64`
   - Load order: after `Lilu` and `BlueToolFixup`.
4. **First-time only — clear the stale Bluetooth blacklist.** If you previously
   ran the firmware-less dongle, macOS set `bluetoothExternalDongleFailed`. Add
   these to `config.plist → NVRAM → Delete` under GUID
   `7C436110-AB2A-4BBB-A880-FE41995C9F82`:
   `bluetoothExternalDongleFailed`, `bluetoothInternalControllerInfo`,
   `bluetoothHostControllerSwitchBehavior`.
5. Reboot **with the dongle plugged in** (a USB-2 port is ideal).

The `scripts/` helpers automate install + verification — read them before running;
they touch your EFI.

## Verify

```sh
log show --last boot --predicate 'eventMessage CONTAINS "RTLBluetoothFirmware"'
system_profiler SPBluetoothDataType | grep -iE "Firmware|Chipset|Address|State"
```
Good = the log shows `download complete`, and **Firmware Version is NOT** the ROM
identity `0x8761 / 0x000B` (it becomes the patch version, e.g. `0xDFC6D922`).

---

## How it works

1. Matches the UB500 `IOUSBHostDevice` early in boot (own `IOMatchCategory`,
   before `bluetoothd`).
2. Sets configuration, opens the HCI interface + interrupt-IN pipe.
3. `HCI Read Local Version` → detects ROM mode; on a warm reboot, sends the Realtek
   vendor reset (`0xFC66`) to drop back to ROM.
4. Parses the `Realtech` epatch container, picks the patch for this ROM version,
   appends the config blob (mirrors `rtlbt_parse_firmware` in `btrtl.c`).
5. Uploads it in 252-byte fragments via `0xFC20`, then `HCI Reset`.
6. Closes all USB handles and releases the device — `bluetoothd` (via BlueToolFixup)
   then drives it as a standard USB HCI controller.

## Known limitations

- **Discovering new devices** is finicky (see table). Paired devices reconnect fine.
- **Sleep/wake**: if USB power is cut, the volatile firmware is lost — replug or
  reboot re-patches it.
- **Continuity** features need real Apple hardware; not fixable here.

## Credits

- Linux kernel `drivers/bluetooth/btrtl.c` & `btusb.c` — the protocol reference (GPL-2.0).
- [`linux-firmware`](https://gitlab.com/kernel-firmware/linux-firmware) `rtl_bt/` — the firmware blobs.
- [OpenIntelWireless/IntelBluetoothFirmware](https://github.com/OpenIntelWireless/IntelBluetoothFirmware) — the "upload-then-handoff" IOKit pattern.
- [acidanthera](https://github.com/acidanthera) — Lilu & BlueToolFixup.

## License

**GPL-2.0-or-later.** The firmware-upload protocol is derived from the GPL-2.0
Linux `btrtl` driver; this kext is an independent IOKit implementation of it.
See [LICENSE](LICENSE).

## Disclaimer

Experimental, community-built, provided as-is. Kernel extensions can crash or
prevent boot. The kext only matches the UB500's `VID/PID`, so if anything misbehaves
at boot, **unplug the dongle** and it's inert. Use at your own risk.
