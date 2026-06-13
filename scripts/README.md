# scripts/

Helper scripts used while developing/installing this kext. **Read each one before
running** — several mount and write to your OpenCore EFI and use `sudo`. They were
written for the author's machine; **adjust the EFI disk identifier** (e.g.
`disk0s1`) and any checksums for yours.

| Script | What it does |
|---|---|
| `install_to_efi.sh` | Mount EFI, install the built kext, ensure the `config.plist` entry, unmount. Pass your EFI disk as `$1` (defaults to `disk0s1`). |
| `check_after_reboot.sh` | Post-reboot diagnostics: was the kext loaded, did firmware upload, controller state. |
| `capture_scan.sh` | Records the `bluetoothd` log across a Bluetooth off→on toggle (for debugging discovery). Read-only. |
| `load_test.sh` | Force-load the kext live with `kmutil` (root-owned staging) — useful to see link/collection errors without a reboot. |
| `live_test.sh` | Unplug → load kext → replug, to test a firmware upload without rebooting. |

None of these are required to use the kext — the README's manual build + install
steps are the supported path.
