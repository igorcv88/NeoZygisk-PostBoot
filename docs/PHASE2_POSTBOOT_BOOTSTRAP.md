# Phase 2 — Idempotent post-boot bootstrap

This phase adds an idempotent shell bootstrap that may be invoked by both `post-fs-data.sh` and `service.sh` without creating duplicate NeoZygisk monitors.

The bootstrap is intentionally non-destructive:

- it never calls `ksud soft-reboot`;
- it never restarts zygote or Android userspace;
- it never kills a monitor, daemon, zygote, system_server, or init;
- it refuses to start when init is traced by an unknown process;
- it refuses to start when more than one NeoZygisk monitor is detected;
- it stages the DEFEX-safe runtime atomically under `/debug_ramdisk/neozygisk`;
- it reuses a healthy monitor and sends `ctl start` only when an existing monitor is stopped;
- it records a persistent status and log under `/data/local/tmp` for hardware diagnostics.

Phase 2 acceptance requires a successful release/debug build and a cold-boot hardware test. Soft-reboot recovery remains a later acceptance criterion because it depends on the exact KernelSU userspace restart lifecycle on the target firmware.
