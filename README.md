# NeoZygisk PostBoot

NeoZygisk PostBoot is a hardware-validated fork of NeoZygisk for temporary
KernelSU sessions on the Samsung Galaxy S25 Ultra `SM-S938B` running
`S938BXXSBCZG3`.

[Download the latest installable module ZIP](https://github.com/igorcv88/NeoZygisk-PostBoot/releases/latest)

The release asset is the raw KernelSU/APatch/Magisk module ZIP itself. The
workflow does not wrap it inside a GitHub Actions artifact archive.

## Supported architecture

This stable fork is intentionally **arm64-only**. Installation aborts on `arm`,
`x86`, and `x64` instead of claiming support that the Phase 3.1 verifier and
hardware validation do not cover. Use upstream NeoZygisk for other
architectures.

## Validated device

```text
Build:  BP4A.251205.006.S938BXXSBCZG3
Kernel: 6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSBCZG3-4k
Root:   temporary KernelSU loaded by Root My Galaxy
ABI:    arm64-v8a
```

Hardware validation confirmed:

- one NeoZygisk monitor attached to PID 1;
- init's `TracerPid` matching the monitor PID;
- an injected `zygote64` and running `zygiskd64`;
- Zygisk Assistant and LSPosed modules loaded;
- `/dev/.neozygisk/cp64.sock` available;
- `/dev/.neozygisk/lib64/libzygisk.so` mapped in the live zygote;
- the Android activity service healthy.

## Installation and activation

1. Run the simple exploit from
   [Root My Galaxy S938B](https://github.com/igorcv88/Root-My-Galaxy-S938B)
   and confirm that KernelSU is active.
2. Install this module from KernelSU Manager.
3. Install or enable dependent modules such as Zygisk Assistant and LSPosed.
4. Use **Soft Reboot** from KernelSU Manager exactly once.
5. After Android returns, open the NeoZygisk module Action page or run:

```sh
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh verify'
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh status'
```

The helper name is retained for compatibility, but Phase 3.1 is read-only. The
module itself does not restart zygote, Android userspace, the kernel or the
device.

A healthy verification reports:

```text
PHASE=3.1
RESULT=INJECTION_VERIFIED
RESTART_TRIGGERED_BY_MODULE=0
TARGETED_ZYGOTE_RESTART_USED=0
GLOBAL_SOFT_REBOOT_USED_BY_MODULE=0
MONITOR_HEALTHY=1
RUNTIME_PROP_INJECTED=1
RUNTIME_PROP_DAEMON_RUNNING=1
CP64_SOCKET_READY=1
LIBRARY_MAPPED_IN_ZYGOTE=1
```

When the monitor is healthy but a fresh zygote has not yet been created, the
verifier reports `WAITING_FOR_KERNELSU_SOFT_REBOOT` instead of initiating any
restart.

## Why the runtime lives under `/dev`

Samsung DEFEX rejected the live zygote opening `libzygisk.so` from the
persistent `/data/adb` module path. This fork stages the runtime atomically at:

```text
/dev/.neozygisk
```

The location is an existing kernel-backed tmpfs and was validated on the target
firmware. The persistent module remains under `/data/adb/modules/zygisksu`; only
the live runtime library and sockets are placed under `/dev`.

## Important safety boundary

A targeted `setprop ctl.restart zygote` experiment reproduced Samsung's
**Device Services Uninstalled** failure state and required a full reboot. That
activation path was withdrawn and is rejected by the release workflow.

Packaged scripts are checked to contain none of the following:

- `ksud soft-reboot`;
- `ctl.restart` or `setprop ctl.restart`;
- device reboot commands;
- `SIGKILL`, `kill -9` or destructive recovery;
- automatic verification from `post-fs-data.sh` or `service.sh`.

Use the KernelSU Manager Soft Reboot button only after the simple exploit has
established a clean KernelSU session.

## Zygisk provider compatibility

Do not install this module beside Zygisk Next, ReZygisk or another Zygisk
provider. Providers compete for the same zygote lifecycle and may share module
IDs or tracing resources.

This fork preserves NeoZygisk's Zygisk API, module loading, namespace handling,
trace cleaning and DenyList behavior. It changes only the runtime location,
post-boot monitor bootstrap and read-only health verification needed by the
temporary-KernelSU environment.

## Release integrity

The release workflow builds only the release module, validates the packaged
scripts and native paths, rejects restart/destructive commands, verifies the ZIP
with `unzip -t`, and publishes the raw installable ZIP plus a checksum whose
recorded filename is the release basename. No Actions artifact wrapper is
published.

## Related repositories

- [Root My Galaxy S938B](https://github.com/igorcv88/Root-My-Galaxy-S938B)
- [Root My Galaxy Payloads S938B](https://github.com/igorcv88/Root-My-Galaxy-Payloads-S938B)
- [Upstream NeoZygisk](https://github.com/JingMatrix/NeoZygisk)

## Upstream NeoZygisk overview

NeoZygisk is a Zygote injection module implemented with `ptrace`. It provides
Zygisk API support for KernelSU and APatch and can replace Magisk's built-in
Zygisk. Its primary features include API compatibility, trace cleaning,
DenyList-aware mount namespace handling and module loading through the zygote
lifecycle.

For KernelSU or APatch, configure per-application unmounting through the root
manager's **Umount modules** option. Do not combine multiple independent
DenyList implementations without testing their namespace behavior.

Use this software only on devices you own or are explicitly authorized to test.
