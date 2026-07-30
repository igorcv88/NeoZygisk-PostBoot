# Phase 3.1 — external KernelSU lifecycle verification

## Hardware conclusion

The original Phase 3 experiment used an explicitly gated `setprop ctl.restart zygote` request. On the target Galaxy S25 Ultra SM-S938B running S938BXXSBCZG3, that path restarted Android userspace into Samsung's `Device Services Uninstalled` failure state and required a full device reboot for recovery.

That activation model is withdrawn. The module must not restart zygote, Android userspace, or the device by itself.

A clean hardware sequence was then validated successfully:

1. perform a full reboot to clear the broken userspace state;
2. run the simple Root-My-Galaxy exploit to restore temporary KernelSU root;
3. open KernelSU Manager and use its **Soft Reboot** action;
4. allow KernelSU to execute the normal module lifecycle;
5. verify the resulting NeoZygisk state without initiating another restart.

## Validated target state

The successful run on `BP4A.251205.006.S938BXXSBCZG3` with kernel `6.6.98-android15-8-pd6ff1cd-abogkiS938BXXSBCZG3-4k` reported:

```text
PHASE=2
RESULT=HEALTHY_STARTED
WORK=/dev/.neozygisk
MONITOR_PID=20323
INIT_TRACER=20323

monitor: tracing
zygote64: injected
daemon64: running
Root: KernelSU
Modules (2):
  zygisk-assistant
  zygisk_lsposed
```

The same snapshot also confirmed:

- one `zygisk-ptrace64` monitor reparented to PID 1;
- `/proc/1/status` `TracerPid` matched the monitor PID;
- a fresh `zygote64`, `system_server`, and `zygiskd64` were running;
- `/dev/.neozygisk/cp64.sock` and `/dev/.neozygisk/init_monitor` existed;
- `/dev/.neozygisk/lib64/libzygisk.so` was mapped directly in the live zygote;
- NeoZygisk, Zygisk Assistant, and LSPosed were operational.

## Phase 3.1 behavior

`postboot-activate.sh` is retained for compatibility, but it is now a read-only verifier. The accepted commands are:

```text
postboot-activate.sh verify
postboot-activate.sh status
```

The legacy aliases `start` and `activate` also perform verification only. They do not initiate any lifecycle action.

The verifier checks:

1. the Phase 2 monitor is healthy;
2. the monitor PID matches init's `TracerPid`;
3. `zygote64`, `system_server`, and `zygiskd64` are present;
4. the runtime `module.prop` reports zygote injection and a running daemon;
5. the activity service is available;
6. `/dev/.neozygisk/cp64.sock` exists;
7. the DEFEX-safe library is mapped in the live zygote.

A successful result is written to:

```text
/data/local/tmp/neozygisk-postboot-phase3.status
```

with the core fields:

```text
PHASE=3.1
RESULT=INJECTION_VERIFIED
RESTART_TRIGGERED_BY_MODULE=0
TARGETED_ZYGOTE_RESTART_USED=0
GLOBAL_SOFT_REBOOT_USED_BY_MODULE=0
MANUAL_KERNELSU_SOFT_REBOOT_REQUIRED=1
MONITOR_HEALTHY=1
RUNTIME_PROP_INJECTED=1
RUNTIME_PROP_DAEMON_RUNNING=1
CP64_SOCKET_READY=1
LIBRARY_MAPPED_IN_ZYGOTE=1
```

If the monitor is healthy but injection is not active, the verifier reports:

```text
RESULT=WAITING_FOR_KERNELSU_SOFT_REBOOT
```

and performs no recovery action.

## Safety boundary

The packaged module must contain none of the following:

- `ksud soft-reboot`;
- `ctl.restart` or `setprop ctl.restart`;
- kernel or device reboot commands;
- zygote, system_server, monitor, or daemon killing;
- automatic recovery or watchdog behavior.

The known-good lifecycle is external and user initiated through KernelSU Manager from a clean post-exploit session. Phase 3.1 only verifies the resulting state.
