# Phase 2 — Idempotent post-boot bootstrap

Phase 2 adds a single shell bootstrap that is invoked from both `post-fs-data.sh` and `service.sh`. Repeated lifecycle calls must converge on one healthy NeoZygisk monitor instead of spawning duplicate tracers.

## Safety contract

The bootstrap is deliberately non-destructive:

- it never calls `ksud soft-reboot`;
- it never restarts zygote or Android userspace;
- it never kills a monitor, daemon, zygote, system_server, or init;
- it refuses to start when init is traced by an unknown process;
- it refuses to start when more than one NeoZygisk monitor is detected;
- it stages the DEFEX-safe runtime atomically under `/debug_ramdisk/neozygisk`;
- it reuses a healthy monitor and sends `ctl start` only to a single recognized stopped monitor;
- it records persistent diagnostics under `/data/local/tmp`.

## Runtime states

The status file `/data/local/tmp/neozygisk-postboot.status` reports one of these results:

- `HEALTHY_STARTED`: a new monitor was started and verified as init's tracer;
- `HEALTHY_REUSED`: an already healthy monitor was reused;
- `HEALTHY_RESUMED`: one recognized stopped monitor accepted `ctl start` and reattached;
- `FAILED`: the bootstrap failed closed and did not perform destructive cleanup;
- `BUSY`: another bootstrap invocation owns the lock.

A monitor is considered healthy only when all conditions match:

1. exactly one monitor process executes the installed tracer binary with the `monitor` argument;
2. `/proc/1/status` reports that monitor PID as `TracerPid`;
3. `/debug_ramdisk/neozygisk/init_monitor` exists as a UNIX socket.

## Scope boundary

This build does not restart an already-running zygote. Therefore, Phase 2 validates staging and monitor lifecycle, not guaranteed injection into a zygote that predates late-loaded KernelSU. Controlled activation and persistence across the target KernelSU soft-reboot lifecycle remain Phase 3 work.

## Hardware test order

1. Disable every other Zygisk provider before installing this ZIP.
2. Install the release ZIP through KernelSU.
3. Use a clean full boot before the first activation test so no previous tracer remains alive.
4. Run the Root My Galaxy exploit with the normal KernelSU path.
5. Do not manually invoke `ksud soft-reboot`, restart zygote, or use NeoZygisk `ctl stop/exit` during the Phase 2 test.
6. Collect the bootstrap status/log, runtime directory contexts, monitor PID, init `TracerPid`, NeoZygisk runtime `module.prop`, logcat, and dmesg.
