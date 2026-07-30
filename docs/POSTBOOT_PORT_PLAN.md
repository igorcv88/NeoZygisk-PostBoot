# NeoZygisk PostBoot port plan

## Target

Primary hardware target:

- Samsung Galaxy S25 Ultra (`SM-S938B`)
- One UI / Android 16 firmware family tested on `S938BXXSBCZG3`
- KernelSU loaded after Android has already booted by Root My Galaxy
- Root is temporary and is lost after a full reboot

## Problem statement

The upstream NeoZygisk lifecycle assumes the root implementation and module hooks are already present during the normal Android boot sequence. Root My Galaxy loads KernelSU after that sequence has passed, so the module must support a second, explicit bootstrap path.

Samsung DEFEX also rejects Zygote-side opens of shared libraries stored below `/data/adb`. The runtime library and IPC directory therefore must live outside `/data`, while persistent module files remain in `/data/adb/modules`.

## Design principles

1. Keep the upstream ptrace monitor, injector, daemon, memfd module loading, mount namespace handling, and trace-cleaning implementation unchanged unless hardware evidence requires otherwise.
2. Use a volatile DEFEX-safe runtime directory under `/debug_ramdisk`.
3. Separate runtime preparation from Zygote restart orchestration.
4. Make runtime preparation idempotent and safe to invoke after normal boot, after late-loaded KernelSU, and after a KernelSU userspace restart.
5. Never launch a second monitor when a healthy monitor is already attached to `init`.
6. Never delete live sockets or staged libraries belonging to a healthy monitor/daemon stack.
7. Fail closed before restarting Zygote when runtime preparation or health checks are inconclusive.
8. Do not use a global KernelSU soft reboot as the NeoZygisk activation primitive.
9. Preserve upstream GPL-3.0 attribution and keep proprietary Zygisk Next code out of this fork.

## Runtime layout

Persistent module files:

```text
/data/adb/modules/zygisksu/
```

Volatile runtime files:

```text
/debug_ramdisk/neozygisk/
├── lib64/libzygisk.so
├── lib/libzygisk.so            # only on builds that ship 32-bit support
├── init_monitor
├── cp64.sock
├── cp32.sock                   # architecture dependent
├── module.prop                 # generated status copy
├── monitor.pid                 # fork addition
├── monitor.log                 # fork addition
└── bootstrap.state             # fork addition
```

## Implementation phases

### Phase 1 — DEFEX-safe runtime staging

- Change the compiled and packaged work directory from `/data/adb/neozygisk` to `/debug_ramdisk/neozygisk`.
- Preserve `system_file` SELinux labels on the runtime directory and staged libraries.
- Verify the staged `libzygisk.so` is byte-identical to the module copy.
- Keep the module ID `zygisksu` for Zygisk module ecosystem compatibility and drop-in replacement behavior.

Acceptance criteria:

- The generated ZIP contains scripts and binaries referencing `/debug_ramdisk/neozygisk`.
- No injector-side library open references `/data/adb/neozygisk`.
- CI builds release and debug variants.

### Phase 2 — Idempotent post-boot bootstrap

Add a single bootstrap entry point used by both `post-fs-data.sh` and Root My Galaxy.

The bootstrap must:

1. Validate root, module files, architecture, and runtime parent availability.
2. Classify existing NeoZygisk monitor, transient injector, and daemon processes by PID, command line, parent PID, and `TracerPid`.
3. Return success without mutation when one healthy monitor is already tracing PID 1.
4. Refuse destructive cleanup while an injector is active.
5. Remove only stale runtime files when no healthy stack exists.
6. Stage libraries atomically using temporary files plus `cmp` verification.
7. Start exactly one monitor and wait for it to attach to `init`.
8. Emit machine-readable status for Root My Galaxy.

### Phase 3 — Controlled Zygote activation

After Phase 2 reports a healthy monitor:

- Capture current Zygote and `system_server` PIDs.
- Request only the minimum restart required for a fresh Zygote fork.
- Detect repeated Zygote death before it becomes a restart loop.
- Stop tracing and return a diagnostic failure if the injector fails.
- Mark success only after:
  - replacement Zygote exists;
  - replacement `system_server` exists;
  - exactly one monitor is attached to `init`;
  - exactly one architecture daemon is alive;
  - daemon socket exists;
  - Zygote injection heartbeat is confirmed.

Global `ksud soft-reboot` is explicitly excluded from this phase.

### Phase 4 — Userspace-restart recovery

- Detect when KernelSU performs a userspace restart and the NeoZygisk monitor disappears.
- Re-run the same idempotent bootstrap rather than implementing a separate recovery path.
- Ensure recovery never creates duplicate monitors or replays module `post-fs-data.sh` scripts unnecessarily.

### Phase 5 — Root My Galaxy integration

Root My Galaxy advanced mode will:

1. Late-load KernelSU.
2. Verify the `zygisksu` module is installed and enabled.
3. Invoke the NeoZygisk PostBoot bootstrap entry point.
4. Perform controlled Zygote activation only after bootstrap success.
5. Display precise activation and verification states.
6. Keep the KernelSU-only path unchanged when advanced mode is disabled.

## Hardware test matrix

Each build must be tested in this order:

1. Full boot → late-load KernelSU → bootstrap only.
2. Bootstrap repeated without restart.
3. Controlled Zygote activation.
4. Confirm Zygisk modules remain disabled during provider validation.
5. Enable one harmless diagnostic Zygisk module.
6. KernelSU userspace restart → automatic recovery.
7. Repeat the userspace restart at least twice.
8. Validate Device Services, System UI, telephony, storage, and lock-screen behavior after each cycle.

## Current branch scope

`feature/postboot-bootstrap` starts Phase 1 only. It changes the fork identity and moves the generated runtime work directory to `/debug_ramdisk/neozygisk`. No Zygote restart behavior is changed in this first checkpoint.
