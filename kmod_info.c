// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * kmod_info.c — defines the _kmod_info structure every kext must export so the
 * kernel can register it and place it in a kernel collection. Apple's Xcode
 * kext target generates this automatically; this hand-built kext supplies it
 * explicitly.
 *
 * _start / _stop come from libkmod.a (c_start.o / c_stop.o). They invoke
 * _realmain / _antimain, which we leave NULL — on macOS 11+ the kernel's
 * collection loader runs the C++ static constructors (OSDefineMetaClass…)
 * from __mod_init_func itself, so no custom module main is needed.
 */

#include <mach/mach_types.h>

extern kern_return_t _start(kmod_info_t *ki, void *data);
extern kern_return_t _stop(kmod_info_t *ki, void *data);

__attribute__((visibility("default")))
KMOD_EXPLICIT_DECL(com.opendev.RTLBluetoothFirmware, "1.2.0", _start, _stop)

__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t  *_antimain = 0;
