# NeoZygisk PostBoot

NeoZygisk PostBoot is an arm64-only fork for temporary KernelSU sessions on the
Samsung Galaxy S25 Ultra `SM-S938B` running `S938BXXSBCZG3`.

[Download the latest installable module ZIP](https://github.com/igorcv88/NeoZygisk-PostBoot/releases/latest)

The release asset is the raw KernelSU module ZIP itself, accompanied by a
portable SHA-256 file. No GitHub Actions artifact wrapper is used.

## Stable hardware result

The 3.2 recovery lifecycle was validated on 30 July 2026 after a complete reboot,
the simple Root My Galaxy exploit and one user-initiated **Soft Reboot** from
KernelSU Manager.

```text
Build:  BP4A.251205.006.S938BXXSBCZG3
Kernel: 6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSBCZG3-4k
Root:   temporary KernelSU loaded by Root My Galaxy
ABI:    arm64-v8a

PHASE=3.2
RESULT=INJECTION_VERIFIED
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

Zygisk Assistant and LSPosed were loaded in the successful state. The module did
not initiate any restart.

## Why 3.2 was necessary

Installing a newer provider package over a live v3.0 monitor and then using
KernelSU Soft Reboot in the same kernel boot reproduced:

```text
monitor: stopped(zygote crashed)
zygote64: unknown
daemon64: running
```

The previous verifier also displayed an old `INJECTION_VERIFIED` snapshot because
its `status` command did not refresh the live state. The stable 3.2 path fixes
both problems:

- a monitor whose executable is marked `(deleted)` is never reused;
- the running tracer hash must match the installed tracer hash;
- the staged runtime library hash must match the installed library hash;
- `stopped(zygote crashed)` fails closed;
- `status` performs a fresh live verification;
- installing over a live monitor records the current kernel `boot_id` and requires
  a full device reboot before activation;
- the module never resumes, kills or restarts an unhealthy monitor in-session.

The native implementation remains the same code generation used by the working
v3.0 hardware build; 3.2 adds the update-generation and live-status guards around
that implementation.

## Required lifecycle

### First installation in a clean kernel session

1. Run the simple exploit from
   [Root My Galaxy S938B](https://github.com/igorcv88/Root-My-Galaxy-S938B).
2. Confirm that KernelSU is active.
3. Install NeoZygisk PostBoot and the dependent Zygisk modules.
4. Use **Soft Reboot** from KernelSU Manager once.
5. Run the module Action or the live verifier.

### Updating NeoZygisk while a monitor already exists

1. Install the update, but **do not use Soft Reboot in that kernel session**.
2. Perform a full device reboot.
3. Run the simple Root My Galaxy exploit again.
4. Use KernelSU Manager **Soft Reboot once**.
5. Verify the live state.

Do not attempt another Soft Reboot after `zygote crashed`, a deleted monitor, a
native-generation mismatch or `FULL_REBOOT_REQUIRED`.

## Live verification

```sh
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh verify'
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh status'
```

The `status` command is live; it does not merely print a previous success file.
A provider update or unhealthy state returns `FULL_REBOOT_REQUIRED` and performs
no recovery action.

## DEFEX-safe runtime

Samsung DEFEX rejected the live zygote opening `libzygisk.so` from the persistent
`/data/adb` module path. The library and sockets are staged atomically under the
kernel-backed tmpfs path:

```text
/dev/.neozygisk
```

The persistent module remains under `/data/adb/modules/zygisksu`.

## Safety boundary

The packaged scripts do not initiate:

- KernelSU Soft Reboot;
- targeted zygote or Android userspace restart;
- device reboot;
- `ctl start` recovery of an unhealthy monitor;
- process killing or destructive cleanup.

A targeted `setprop ctl.restart zygote` experiment reproduced Samsung's
**Device Services Uninstalled** failure state and remains permanently withdrawn.

## Provider compatibility

Install exactly one provider. Do not install this module beside Zygisk Next,
ReZygisk or another Zygisk provider.

## Release process

Every build verifies shell syntax, the `/dev/.neozygisk` runtime, arm64-only
installation, live generation guards, the absence of restart/recovery commands,
and the portable release checksum. The raw installable ZIP is published directly
to GitHub Releases only after explicit approval or a release-marked commit.

## Related repositories

- [Root My Galaxy S938B](https://github.com/igorcv88/Root-My-Galaxy-S938B)
- [Root My Galaxy Payloads S938B](https://github.com/igorcv88/Root-My-Galaxy-Payloads-S938B)
- [Upstream NeoZygisk](https://github.com/JingMatrix/NeoZygisk)

Use this software only on devices you own or are explicitly authorized to test.
