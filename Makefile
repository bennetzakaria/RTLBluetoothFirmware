# RTLBluetoothFirmware — build with Xcode Command Line Tools (no .xcodeproj)
#   make            build RTLBluetoothFirmware.kext
#   make clean
#
# Two translation units:
#   RTLBluetoothFirmware.cpp  — the IOKit driver (C++)
#   kmod_info.c               — the mandatory _kmod_info symbol (C)
# Both are required: without kmod_info.o the kext has no _kmod_info symbol and
# cannot be placed in a kernel collection (OpenCore/kmutil reject it).

SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
CXX     := $(shell xcrun --find clang++)
CC      := $(shell xcrun --find clang)

KEXT    = RTLBluetoothFirmware.kext
BUNDLE  = $(KEXT)/Contents
BINARY  = $(BUNDLE)/MacOS/RTLBluetoothFirmware
GEN     = RTLFirmwareData.hpp
OBJS    = RTLBluetoothFirmware.o kmod_info.o

COMMON  = -arch x86_64 \
          -isysroot $(SDKROOT) \
          -mmacosx-version-min=12.0 \
          -mkernel \
          -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
          -I$(SDKROOT)/System/Library/Frameworks/Kernel.framework/Headers \
          -O2 -Wall

CXXFLAGS = $(COMMON) -std=gnu++14 -fno-exceptions -fno-rtti -fapple-kext
CFLAGS   = $(COMMON)

LDFLAGS  = -arch x86_64 \
           -isysroot $(SDKROOT) \
           -mmacosx-version-min=12.0 \
           -fapple-kext \
           -Xlinker -kext \
           -nostdlib \
           -lkmodc++ \
           -lkmod \
           -lcc_kext

.PHONY: all clean install

all: $(BINARY)
	@codesign --force --sign - $(KEXT) 2>/dev/null || true
	@echo ">>> Built $(KEXT)"

$(GEN): embed_firmware.py
	python3 embed_firmware.py   # fetches firmware from linux-firmware if missing

RTLBluetoothFirmware.o: RTLBluetoothFirmware.cpp RTLBluetoothFirmware.hpp $(GEN)
	$(CXX) $(CXXFLAGS) -c -o $@ RTLBluetoothFirmware.cpp

kmod_info.o: kmod_info.c
	$(CC) $(CFLAGS) -c -o $@ kmod_info.c

$(BINARY): $(OBJS) Info.plist
	@mkdir -p $(BUNDLE)/MacOS
	cp Info.plist $(BUNDLE)/Info.plist
	$(CXX) $(LDFLAGS) -o $@ $(OBJS)
	@file $@
	@echo ">>> _kmod_info check:" && nm -arch x86_64 $@ | grep -E "_kmod_info|__realmain|__antimain" || echo "   !!! _kmod_info MISSING"

clean:
	rm -rf $(KEXT) $(GEN) $(OBJS)

# Mount your EFI first, e.g.:  sudo diskutil mount disk0s1
MOUNT_POINT ?= /Volumes/EFI
OC_KEXTS    = $(MOUNT_POINT)/EFI/OC/Kexts

install: all
	cp -r $(KEXT) $(OC_KEXTS)/
	@echo ">>> Copied to $(OC_KEXTS)/ — now add it to config.plist (OC Snapshot)"
