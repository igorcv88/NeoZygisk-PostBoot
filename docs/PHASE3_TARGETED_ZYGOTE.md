# Phase 3 — one-shot targeted zygote activation

## Goal

Activate a fresh 64-bit zygote under the already healthy NeoZygisk init monitor without invoking KernelSU's global soft reboot.

Phase 2 proved that the monitor can be staged under `/dev/.neozygisk`, reparented to PID 1, and attached to init on the target Galaxy S25 Ultra. Phase 3 adds one explicitly gated activation step that asks Android init to restart only the `zygote` service and then verifies that the replacement zygote was injected.

## Activation model

`postboot-activate.sh start` launches a detached native shell so the verifier survives the temporary Android UI and `system_server` restart. The worker performs the following sequence:

1. run the Phase 2 bootstrap idempotently;
2. require exactly one healthy NeoZygisk monitor attached to PID 1;
3. record the current `zygote64` and `system_server` PIDs;
4. skip the restart if the current runtime already reports an injected zygote and a running daemon;
5. start best-effort absolute-path logcat capture;
6. issue exactly one `/system/bin/setprop ctl.restart zygote` request;
7. observe the replacement zygote and `system_server` PIDs;
8. require the monitor to remain attached to init;
9. require the generated runtime `module.prop` to report `zygote64` injected and `daemon64` running;
10. require the Android activity service to become available again;
11. persist a machine-readable success or failure record under `/data/local/tmp`.

## Verification output

The activation status is written to:

```text
/data/local/tmp/neozygisk-postboot-phase3.status
```

A successful run reports:

```text
PHASE=3
RESULT=INJECTION_VERIFIED
GLOBAL_SOFT_REBOOT_USED=0
TARGETED_RESTART_REQUESTED=1
MONITOR_HEALTHY=1
ZYGOTE_OLD_PID=<old>
ZYGOTE_NEW_PID=<new>
SYSTEM_SERVER_OLD_PID=<old>
SYSTEM_SERVER_NEW_PID=<new>
RUNTIME_PROP_INJECTED=1
RUNTIME_PROP_DAEMON_RUNNING=1
ACTIVITY_READY=1
```

Detailed logs are written to:

```text
/data/local/tmp/neozygisk-postboot-phase3.log
/data/local/tmp/neozygisk-postboot-phase3-logcat.txt
```

## Safety boundaries

Phase 3 deliberately does not:

- call `ksud soft-reboot`;
- reboot the kernel or device;
- automatically run from `post-fs-data.sh` or `service.sh`;
- retry the targeted restart;
- kill zygote, `system_server`, the monitor, or the daemon;
- add recovery or watchdog behavior;
- alter NeoZygisk's injector, daemon protocol, module loading, map spoofing, namespace handling, or trace cleaning.

The upstream monitor's own injection and crash-loop behavior remains unchanged. The Phase 3 shell verifier only observes and records the result.

## Hardware acceptance criteria

On the target SM-S938B / S938BXXSBCZG3 temporary-KernelSU session:

1. Phase 2 is healthy before activation.
2. Android userspace visibly restarts once, but KernelSU root remains active.
3. `zygote64` and `system_server` receive new PIDs.
4. The same single monitor remains attached to PID 1.
5. `/dev/.neozygisk/module.prop` reports the 64-bit zygote as injected and daemon as running.
6. the activity service returns.
7. the Phase 3 status reports `INJECTION_VERIFIED`.
8. no KernelSU global soft reboot is executed.

Only after these criteria pass should a later phase add automatic recovery, watchdog behavior, or integration into the Root-My-Galaxy advanced flow.
