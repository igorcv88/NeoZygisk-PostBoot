# Phase 1 — DEFEX-safe tmpfs runtime relocation

## Goal

Relocate NeoZygisk's runtime from `/data/adb/neozygisk` to a kernel-backed tmpfs path without changing the upstream ptrace monitor, injector, daemon protocol, Zygisk API implementation, or restart lifecycle.

The target device is a Samsung Galaxy S25 Ultra (SM-S938B) running S938BXXSBCZG3 with temporary KernelSU root. Kernel logs from this device showed Samsung DEFEX rejecting `app_process64` access to Zygisk libraries under `/data/adb`.

The first hardware build used `/debug_ramdisk/neozygisk`, following the last GPL Zygisk Next layout. On the target temporary-KernelSU boot, runtime staging failed before monitor startup and `/debug_ramdisk` was not available as a usable runtime parent. The path was therefore adapted to `/dev/.neozygisk`.

`/dev` is an existing kernel-backed tmpfs on this device. A previous ReZygisk experiment already proved that a library staged under `/dev` can be opened by the Samsung zygote without triggering the `/data/adb` DEFEX denial. This keeps the relevant technique—loading from tmpfs outside `/data/adb`—without assuming a Magisk-style `/debug_ramdisk` mount exists.

## Scope

Phase 1 changes only the compile-time work directory and build metadata:

- native `WORK_DIRECTORY` becomes `/dev/.neozygisk`;
- generated shell scripts receive the same path through `@WORK_DIRECTORY@` substitution;
- the experimental version is marked as a PostBoot fork build;
- the upstream update channel is disabled for fork builds;
- CI verifies the generated scripts and native ptracer binaries contain the selected tmpfs path and no legacy `/data/adb/neozygisk` or unavailable `/debug_ramdisk/neozygisk` path.

## Explicit non-goals

Phase 1 does not:

- add a post-boot bootstrap;
- change monitor ownership or process classification;
- restart zygote or Android userspace;
- call `ksud soft-reboot`;
- add watchdog behavior;
- alter module loading, memfd loading, map spoofing, namespace handling, or trace cleanup;
- import code from the current closed-source Zygisk Next releases.

Those behaviors belong to later phases and must be tested separately.

## Zygisk Next control build

A downgrade to the last GPL Zygisk Next build is not required before Phase 1. Its source establishes the important behavior: staging outside `/data/adb`. A hardware test of that old binary would not isolate the path variable cleanly because it may lack newer Android 16, BTI, linker, or kernel compatibility work present in current providers.

The old GPL build should therefore be used only as a secondary control if the modern NeoZygisk injector fails before injection after a usable tmpfs runtime has been staged.

## Build acceptance criteria

A release and debug ZIP must build successfully. In each release ZIP:

1. `postboot-bootstrap.sh`, `action.sh`, and `uninstall.sh` must reference `/dev/.neozygisk`.
2. Every `libzygisk_ptrace.so` architecture must contain `/dev/.neozygisk` as its compiled work directory.
3. No packaged file may contain `/data/adb/neozygisk` or `/debug_ramdisk/neozygisk`.
4. The module ID remains `zygisksu` for Zygisk provider compatibility.

## Hardware test order

The first hardware test should be a cold-boot test after removing or disabling every other Zygisk provider. No manual soft reboot should be used during the first run. The test must collect:

- KernelSU module log;
- NeoZygisk monitor and injector log;
- `dmesg` lines containing `DEFEX`, `app_process`, `zygote`, or `neozygisk`;
- monitor, injector, daemon, zygote, and system_server PIDs;
- `/proc/1/status` `TracerPid`;
- the runtime directory metadata and SELinux contexts.

Soft-reboot persistence remains a later-phase criterion.
