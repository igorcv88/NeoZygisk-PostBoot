# NeoZygisk PostBoot

NeoZygisk PostBoot is an arm64-only fork for temporary KernelSU sessions on the
Samsung Galaxy S25 Ultra `SM-S938B` running `S938BXXSBCZG3`.

> [!CAUTION]
> Automatic release publishing is frozen while the 3.2 fail-closed update path
> is hardware tested. Do not activate a newly installed NeoZygisk provider with
> KernelSU Soft Reboot while an older monitor is still alive in the same kernel
> boot.

## Confirmed update regression

A 30 July 2026 hardware test installed a newer provider package while the
previous v3.0 monitor remained attached to init. The next manual KernelSU Soft
Reboot left the runtime reporting:

```text
monitor: stopped(zygote crashed)
zygote64: unknown
daemon64: running
```

The previous verifier also printed an old `INJECTION_VERIFIED` snapshot because
its `status` command did not refresh the live state.

The bootstrap had accepted a monitor whose executable path ended in
`(deleted)` after module files were replaced. That allowed an old running
monitor and `/dev` runtime to coexist with a newer installed native generation.
The 3.2 RC now fails closed instead:

- a deleted monitor executable is never considered healthy;
- the running tracer hash must match the installed tracer hash;
- the staged runtime library hash must match the installed library hash;
- `stopped(zygote crashed)` requires a full device reboot;
- automatic monitor resume is disabled;
- `status` performs a live check and overwrites stale success results;
- installation over a live monitor records the current kernel `boot_id` and
  requires a full reboot before activation.

## Required lifecycle

### First installation in a clean session

1. Full device reboot.
2. Run the simple Root My Galaxy exploit and confirm KernelSU is active.
3. Install NeoZygisk PostBoot and dependent modules.
4. Use **Soft Reboot** from KernelSU Manager once.
5. Run the module Action or the live verifier.

### Updating NeoZygisk while a monitor already exists

1. Install the update, but **do not use Soft Reboot in that kernel session**.
2. Perform a full device reboot.
3. Run the simple Root My Galaxy exploit again.
4. Open KernelSU Manager and use **Soft Reboot once**.
5. Verify the live state.

Do not attempt another Soft Reboot after any `zygote crashed`, deleted-monitor,
generation-mismatch, or `FULL_REBOOT_REQUIRED` result.

## Live verification

```sh
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh status'
su -c '/system/bin/sh /data/adb/modules/zygisksu/postboot-activate.sh verify'
```

A healthy 3.2 result includes:

```text
PHASE=3.2
RESULT=INJECTION_VERIFIED
FULL_REBOOT_REQUIRED=0
MONITOR_HEALTHY=1
MONITOR_EXE_DELETED=0
MONITOR_BINARY_MATCH=1
RUNTIME_LIBRARY_MATCH=1
RUNTIME_MONITOR_CRASHED=0
RUNTIME_PROP_INJECTED=1
RUNTIME_PROP_DAEMON_RUNNING=1
CP64_SOCKET_READY=1
LIBRARY_MAPPED_IN_ZYGOTE=1
```

A provider update in the same kernel session, an unhealthy monitor, or a zygote
crash produces `FULL_REBOOT_REQUIRED` and performs no recovery action.

## Validated target

```text
Build:  BP4A.251205.006.S938BXXSBCZG3
Kernel: 6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSBCZG3-4k
Root:   temporary KernelSU loaded by Root My Galaxy
ABI:    arm64-v8a
```

The original clean-session validation confirmed one monitor attached to init,
an injected `zygote64`, a running `zygiskd64`, Zygisk Assistant and LSPosed,
`/dev/.neozygisk/cp64.sock`, and the live `/dev/.neozygisk/lib64/libzygisk.so`
mapping.

## DEFEX-safe runtime

Samsung DEFEX rejected the live zygote opening `libzygisk.so` from the persistent
`/data/adb` module path. The runtime library and sockets are staged atomically
under the kernel-backed tmpfs path:

```text
/dev/.neozygisk
```

The persistent module remains under `/data/adb/modules/zygisksu`.

## Safety boundary

The module does not initiate:

- KernelSU Soft Reboot;
- targeted zygote or Android userspace restart;
- device reboot;
- `ctl start` recovery of an existing unhealthy monitor;
- process killing or destructive cleanup.

A prior targeted `setprop ctl.restart zygote` experiment reproduced Samsung's
**Device Services Uninstalled** failure state and remains permanently withdrawn.

## Provider compatibility

Install exactly one provider. Do not install this module beside Zygisk Next,
ReZygisk, or another Zygisk provider.

## Releases

Push and pull-request workflows build and validate without uploading an Actions
artifact and without publishing a release. Publishing the raw installable module
ZIP and portable SHA-256 file requires an explicit manually approved workflow
dispatch after hardware validation.

## Related repositories

- [Root My Galaxy S938B](https://github.com/igorcv88/Root-My-Galaxy-S938B)
- [Root My Galaxy Payloads S938B](https://github.com/igorcv88/Root-My-Galaxy-Payloads-S938B)
- [Upstream NeoZygisk](https://github.com/JingMatrix/NeoZygisk)

Use this software only on devices you own or are explicitly authorized to test.
