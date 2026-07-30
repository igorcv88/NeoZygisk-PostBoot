# NeoZygisk PostBoot 3.2 hardware validation

## Target

```text
Device:  Samsung Galaxy S25 Ultra SM-S938B
Build:   BP4A.251205.006.S938BXXSBCZG3
Kernel:  6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSBCZG3-4k
Root:    temporary KernelSU loaded by Root My Galaxy
Date:    2026-07-30
```

## Regression reproduced before recovery

A provider package was installed while an older monitor was still attached to
init. A manual KernelSU Manager Soft Reboot in the same kernel session produced:

```text
monitor: stopped(zygote crashed)
zygote64: unknown
daemon64: running
```

The older status implementation also printed a stale `INJECTION_VERIFIED` result.
The device was recovered with a complete reboot, the simple exploit, the 3.2
recovery package and one KernelSU Manager Soft Reboot.

## Successful recovery result

```text
PHASE=3.2
RESULT=INJECTION_VERIFIED
DETAIL=healthy same-generation NeoZygisk state verified
WORK=/dev/.neozygisk
RESTART_TRIGGERED_BY_MODULE=0
TARGETED_ZYGOTE_RESTART_USED=0
GLOBAL_SOFT_REBOOT_USED_BY_MODULE=0
MANUAL_KERNELSU_SOFT_REBOOT_REQUIRED=0
FULL_REBOOT_REQUIRED=0
BOOTSTRAP_RESULT=HEALTHY
MONITOR_HEALTHY=1
MONITOR_PID=13835
INIT_TRACER=13835
MONITOR_EXE_DELETED=0
MONITOR_BINARY_MATCH=1
RUNTIME_LIBRARY_MATCH=1
RUNTIME_MONITOR_CRASHED=0
ZYGOTE_PID=24563
SYSTEM_SERVER_PID=24853
DAEMON_PID=24565
RUNTIME_PROP_INJECTED=1
RUNTIME_PROP_DAEMON_RUNNING=1
ACTIVITY_READY=1
CP64_SOCKET_READY=1
LIBRARY_MAPPED_IN_ZYGOTE=1
```

The runtime also reported:

```text
monitor: tracing
zygote64: injected
daemon64: running
Root: KernelSU
Modules (2):
  zygisk-assistant
  zygisk_lsposed
```

## Acceptance criteria

The stable 3.2 release requires all of the following:

- exactly one monitor attached to init;
- monitor executable not marked deleted;
- live monitor binary matching the installed tracer;
- `/dev` runtime library matching the installed library;
- no recorded zygote crash;
- injected `zygote64` and running `zygiskd64`;
- healthy Android activity service;
- `cp64.sock` present;
- `libzygisk.so` mapped in the live zygote;
- no module-initiated reboot, Soft Reboot, targeted restart, process kill or
  in-session recovery.

## Mandatory update rule

Installing a provider update while a monitor exists requires:

1. install the update without Soft Reboot;
2. full device reboot;
3. run the simple Root My Galaxy exploit;
4. one user-initiated Soft Reboot from KernelSU Manager;
5. live verification.

Any crash, deleted monitor, generation mismatch or `FULL_REBOOT_REQUIRED` result
must be resolved by a full device reboot, not another Soft Reboot.

## Release approval

The complete result above satisfies the stable 3.2 acceptance criteria. The raw
installable module ZIP and its portable SHA-256 file are approved for publication
under GitHub Releases. No Actions artifact wrapper is approved or required.
