// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

/*
 * RTLBluetoothFirmware.hpp
 *
 * Firmware loader for the TP-Link UB500 (Realtek RTL8761BU) Bluetooth
 * USB adapter on macOS 12+ (OpenCore hackintosh).
 *
 * Protocol mirrors the Linux kernel driver drivers/bluetooth/btrtl.c.
 * Handoff model mirrors OpenIntelWireless/IntelBluetoothFirmware:
 * upload firmware early in boot, then release the device so the
 * BlueToolFixup-patched bluetoothd can claim it from userspace.
 *
 * HCI events are read from the interrupt-IN pipe asynchronously and
 * bounded by IOCommandGate::commandSleep — the synchronous io() overload
 * MUST NOT carry a timeout on an interrupt endpoint (SDK requirement),
 * so we cannot use it here.
 */

#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOCommandGate.h>
#include <IOKit/IOBufferMemoryDescriptor.h>
#include <IOKit/usb/IOUSBHostDevice.h>
#include <IOKit/usb/IOUSBHostInterface.h>
#include <IOKit/usb/IOUSBHostPipe.h>
#include <libkern/OSByteOrder.h>

#define DRV "RTLBluetoothFirmware"

// ─── Standard HCI opcodes ─────────────────────────────────────────────────────
#define HCI_OP_READ_LOCAL_VERSION   0x1001

// ─── Realtek vendor HCI opcodes (from btrtl.c) ────────────────────────────────
#define RTL_OP_READ_ROM_VERSION     0xFC6D
#define RTL_OP_DOWNLOAD_FW          0xFC20
#define RTL_OP_DROP_FW              0xFC66  // reset a patched chip back to ROM

// ─── HCI event codes ──────────────────────────────────────────────────────────
#define HCI_EVT_COMMAND_COMPLETE    0x0E
#define HCI_EVT_COMMAND_STATUS      0x0F

// ─── Realtek firmware constants (from btrtl.c) ────────────────────────────────
#define RTL_FRAG_LEN                252     // bytes per 0xFC20 fragment
#define RTL_EPATCH_HEADER_LEN       14      // "Realtech"[8] + fw_version[4] + num_patches[2]
#define RTL_EXT_SIG_LEN             4       // extension-section signature length
#define RTL8761B_PROJECT_ID         14      // project id stored in the fw extension section

// ROM-mode identity of the RTL8761BU as reported by HCI Read Local Version.
// Matches the 8761BU row of btrtl.c's ic_id_table: IC_INFO(0x8761, 0xb, 0xa, HCI_USB)
#define RTL8761BU_ROM_LMP_SUBVER    0x8761
#define RTL8761BU_ROM_HCI_REV       0x000B
#define RTL8761BU_ROM_HCI_VER       0x0A

// ─── USB HCI command channel (Bluetooth Core spec Vol 4 Part B) ───────────────
// bmRequestType 0x20 (class, host->device), bRequest 0, wValue 0, wIndex 0
#define HCI_CTRL_REQ_TYPE           0x20
#define HCI_CTRL_REQ                0x00
#define HCI_CTRL_TIMEOUT_MS         2000    // control endpoints may carry a timeout

// ─── Event-read tuning ────────────────────────────────────────────────────────
#define EVT_BUF_CAP                 64      // ≥ any HCI event we read here
#define EVT_TIMEOUT_MS              1500    // per interrupt-IN read (gated)
#define EVT_MAX_ATTEMPTS            6       // events scanned per command-complete

#pragma pack(push, 1)

// HCI Read Local Version command-complete payload (after the status byte)
struct RtlLocalVersion {
    uint8_t  hciVer;
    uint16_t hciRev;
    uint8_t  lmpVer;
    uint16_t manufacturer;
    uint16_t lmpSubver;
};

#pragma pack(pop)

class RTLBluetoothFirmware : public IOService {
    OSDeclareDefaultStructors(RTLBluetoothFirmware)

public:
    bool    start(IOService *provider)  override;
    void    stop(IOService *provider)   override;
    void    free()                      override;

private:
    IOUSBHostDevice          *m_device     = nullptr;
    IOUSBHostInterface       *m_interface  = nullptr;
    IOUSBHostPipe            *m_intInPipe  = nullptr;  // interrupt IN — HCI events
    IOBufferMemoryDescriptor *m_evtBuf     = nullptr;
    bool                      m_evtBufPrepared = false;
    uint32_t                  m_evtMaxPacket   = 16;

    // Event-read synchronization (async io + commandSleep)
    IOWorkLoop               *m_workLoop   = nullptr;
    IOCommandGate            *m_cmdGate    = nullptr;
    bool                      m_evtInFlight = false;   // gated sleep token
    IOReturn                  m_evtStatus   = kIOReturnSuccess;
    uint32_t                  m_evtActualLen = 0;

    // ── High-level flow ──────────────────────────────────────────────────────
    IOReturn    runFirmwareUpload();
    bool        isRomMode(const RtlLocalVersion &v) const;

    // ── USB setup / teardown ─────────────────────────────────────────────────
    IOReturn    openUSB(IOService *provider);
    bool        findHCIInterface();
    bool        findInterruptInPipe();
    void        closeUSB();

    // ── HCI transport primitives ─────────────────────────────────────────────
    // Send an HCI command via the control endpoint (no response wait)
    IOReturn    hciCmd(uint16_t opcode, const void *params, uint8_t paramLen);

    // Read one HCI event transfer from the interrupt-IN pipe (async + gated wait)
    IOReturn    hciEvt(uint8_t *buf, uint32_t bufCap, uint32_t *outLen);
    IOReturn    gatedEvtRead(void *, void *, void *, void *);          // runs on the gate
    static void evtCompletion(void *owner, void *parameter,
                              IOReturn status, uint32_t bytesTransferred);

    // Send command, wait for its command-complete event, verify status byte.
    // On success the full raw event is in evtBuf:
    //   [0]=0x0E [1]=plen [2]=numCmds [3..4]=opcode LE [5]=status [6...]=params
    IOReturn    hciCmdSync(uint16_t opcode, const void *params, uint8_t paramLen,
                           uint8_t *evtBuf, uint32_t evtCap, uint32_t *evtLen);

    // ── Realtek protocol (mirrors btrtl.c) ───────────────────────────────────
    IOReturn    readLocalVersion(RtlLocalVersion *out);
    IOReturn    rtlReadRomVersion(uint8_t *outVersion);
    IOReturn    buildDownloadImage(uint8_t romVersion, uint8_t **outBuf, uint32_t *outLen);
    IOReturn    rtlDownload(const uint8_t *data, uint32_t len);
};
