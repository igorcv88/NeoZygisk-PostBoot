#!/system/bin/sh

DEBUG=@DEBUG@
WORK=@WORK_DIRECTORY@
MODDIR=${0%/*}
STATUS=/data/local/tmp/neozygisk-postboot.status
RUNLOG=/data/local/tmp/neozygisk-postboot.log
LOCK=/data/local/tmp/neozygisk-postboot.lock
UPDATE_MARKER="$MODDIR/update_requires_full_reboot"
STAGE_ERROR=
MONITOR_PID=
MONITOR_LIST=
MONITOR_COUNT=0
MONITOR_EXE=
MONITOR_EXE_DELETED=0
MONITOR_BINARY_MATCH=0
RUNTIME_LIBRARY_MATCH=0
RUNTIME_MONITOR_CRASHED=0
COLD_BOOT_REQUIRED=0
INIT_TRACER=0

log_line() {
  now=$(/system/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || /system/bin/date)
  echo "$now $*" >> "$RUNLOG"
  /system/bin/log -p i -t neozygisk-postboot "$*" 2>/dev/null || true
}

write_status() {
  tmp="${STATUS}.tmp.$$"
  {
    echo "PHASE=2"
    echo "RESULT=$1"
    echo "DETAIL=${2:-}"
    echo "WORK=$WORK"
    echo "STAGE_ERROR=${STAGE_ERROR:-}"
    echo "MONITOR_PID=${MONITOR_PID:-}"
    echo "MONITOR_COUNT=${MONITOR_COUNT:-0}"
    echo "MONITOR_EXE=${MONITOR_EXE:-}"
    echo "MONITOR_EXE_DELETED=${MONITOR_EXE_DELETED:-0}"
    echo "MONITOR_BINARY_MATCH=${MONITOR_BINARY_MATCH:-0}"
    echo "RUNTIME_LIBRARY_MATCH=${RUNTIME_LIBRARY_MATCH:-0}"
    echo "RUNTIME_MONITOR_CRASHED=${RUNTIME_MONITOR_CRASHED:-0}"
    echo "COLD_BOOT_REQUIRED=${COLD_BOOT_REQUIRED:-0}"
    echo "INIT_TRACER=${INIT_TRACER:-0}"
    echo "TIMESTAMP=$(/system/bin/date +%s 2>/dev/null || echo 0)"
  } > "$tmp"
  /system/bin/chmod 0644 "$tmp" 2>/dev/null || true
  /system/bin/mv -f "$tmp" "$STATUS"
}

acquire_lock() {
  if /system/bin/mkdir "$LOCK" 2>/dev/null; then
    echo $$ > "$LOCK/pid"
    return 0
  fi

  owner=$(/system/bin/cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$owner" ] && [ -d "/proc/$owner" ]; then
    write_status BUSY "bootstrap already running as pid $owner"
    return 1
  fi

  /system/bin/rm -rf "$LOCK" 2>/dev/null || return 1
  /system/bin/mkdir "$LOCK" 2>/dev/null || return 1
  echo $$ > "$LOCK/pid"
}

release_lock() {
  /system/bin/rm -rf "$LOCK" 2>/dev/null || true
}

current_boot_id() {
  /system/bin/cat /proc/sys/kernel/random/boot_id 2>/dev/null || true
}

marker_boot_id() {
  [ -r "$UPDATE_MARKER" ] || return 1
  while IFS='=' read -r key value; do
    [ "$key" = "boot_id" ] || continue
    printf '%s\n' "$value"
    return 0
  done < "$UPDATE_MARKER"
  return 1
}

marker_requires_full_reboot() {
  [ -r "$UPDATE_MARKER" ] || return 1
  marked=$(marker_boot_id 2>/dev/null || true)
  current=$(current_boot_id)
  [ -n "$marked" ] && [ "$marked" = "$current" ]
}

clear_marker_after_cold_boot() {
  [ -r "$UPDATE_MARKER" ] || return 0
  if marker_requires_full_reboot; then
    return 1
  fi
  /system/bin/rm -f "$UPDATE_MARKER" 2>/dev/null || return 1
  log_line "cleared update marker after a full kernel reboot"
  return 0
}

select_tracer() {
  if [ -x "$MODDIR/bin/zygisk-ptrace64" ]; then
    TRACER="$MODDIR/bin/zygisk-ptrace64"
    MODULE_LIB="$MODDIR/lib64/libzygisk.so"
    RUNTIME_LIB="$WORK/lib64/libzygisk.so"
  elif [ -x "$MODDIR/bin/zygisk-ptrace32" ]; then
    TRACER="$MODDIR/bin/zygisk-ptrace32"
    MODULE_LIB="$MODDIR/lib/libzygisk.so"
    RUNTIME_LIB="$WORK/lib/libzygisk.so"
  else
    return 1
  fi
}

file_hash() {
  target=$1
  [ -r "$target" ] || return 1
  line=$(/system/bin/toybox sha256sum "$target" 2>/dev/null || /system/bin/sha256sum "$target" 2>/dev/null || true)
  set -- $line
  hash=${1:-}
  case "$hash" in
    ''|*[!0-9a-fA-F]*) return 1 ;;
  esac
  printf '%s\n' "$hash"
}

get_init_tracer() {
  while IFS= read -r line; do
    case "$line" in
      TracerPid:*)
        value=${line#TracerPid:}
        value=$(printf '%s' "$value" | /system/bin/tr -cd '0-9')
        [ -n "$value" ] || value=0
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done < /proc/1/status
  printf '0\n'
}

monitor_pids() {
  for proc in /proc/[0-9]*; do
    [ -d "$proc" ] || continue
    pid=${proc#/proc/}
    exe=$(/system/bin/readlink "$proc/exe" 2>/dev/null || true)
    case "$exe" in
      "$TRACER"|"$TRACER (deleted)") ;;
      *) continue ;;
    esac
    cmd=$(/system/bin/tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case " $cmd " in
      *" monitor "*) echo "$pid" ;;
    esac
  done
}

runtime_reports_crash() {
  [ -r "$WORK/module.prop" ] || return 1
  line=$(/system/bin/toybox grep -F 'monitor:' "$WORK/module.prop" 2>/dev/null | /system/bin/toybox head -n 1)
  case "$line" in
    *'stopped(zygote crashed)'*) return 0 ;;
  esac
  return 1
}

inspect_monitor() {
  MONITOR_LIST=$(monitor_pids)
  MONITOR_COUNT=0
  MONITOR_PID=
  MONITOR_EXE=
  MONITOR_EXE_DELETED=0
  MONITOR_BINARY_MATCH=0
  RUNTIME_LIBRARY_MATCH=0
  RUNTIME_MONITOR_CRASHED=0
  COLD_BOOT_REQUIRED=0

  for pid in $MONITOR_LIST; do
    MONITOR_COUNT=$((MONITOR_COUNT + 1))
    [ -n "$MONITOR_PID" ] || MONITOR_PID=$pid
  done

  INIT_TRACER=$(get_init_tracer 2>/dev/null || true)
  case "$INIT_TRACER" in
    ''|*[!0-9]*) INIT_TRACER=0 ;;
  esac

  if [ "$MONITOR_COUNT" -eq 1 ] && [ -n "$MONITOR_PID" ]; then
    MONITOR_EXE=$(/system/bin/readlink "/proc/$MONITOR_PID/exe" 2>/dev/null || true)
    case "$MONITOR_EXE" in
      *' (deleted)') MONITOR_EXE_DELETED=1 ;;
    esac

    installed_hash=$(file_hash "$TRACER" 2>/dev/null || true)
    running_hash=$(file_hash "/proc/$MONITOR_PID/exe" 2>/dev/null || true)
    if [ -n "$installed_hash" ] && [ "$installed_hash" = "$running_hash" ]; then
      MONITOR_BINARY_MATCH=1
    fi

    module_lib_hash=$(file_hash "$MODULE_LIB" 2>/dev/null || true)
    runtime_lib_hash=$(file_hash "$RUNTIME_LIB" 2>/dev/null || true)
    if [ -n "$module_lib_hash" ] && [ "$module_lib_hash" = "$runtime_lib_hash" ]; then
      RUNTIME_LIBRARY_MATCH=1
    fi
  fi

  if runtime_reports_crash; then
    RUNTIME_MONITOR_CRASHED=1
  fi
}

is_healthy() {
  [ "$MONITOR_COUNT" -eq 1 ] || return 1
  [ "$INIT_TRACER" = "$MONITOR_PID" ] || return 1
  [ -S "$WORK/init_monitor" ] || return 1
  [ "$MONITOR_EXE_DELETED" -eq 0 ] || return 1
  [ "$MONITOR_BINARY_MATCH" -eq 1 ] || return 1
  [ "$RUNTIME_LIBRARY_MATCH" -eq 1 ] || return 1
  [ "$RUNTIME_MONITOR_CRASHED" -eq 0 ] || return 1
  return 0
}

generation_mismatch() {
  [ "$MONITOR_COUNT" -eq 1 ] || return 1
  [ "$MONITOR_EXE_DELETED" -eq 1 ] && return 0
  [ "$MONITOR_BINARY_MATCH" -ne 1 ] && return 0
  [ "$RUNTIME_LIBRARY_MATCH" -ne 1 ] && return 0
  return 1
}

stage_error() {
  STAGE_ERROR=$1
  log_line "runtime staging failed at $STAGE_ERROR"
}

stage_runtime() {
  parent=${WORK%/*}
  tmp="${WORK}.new.$$"
  old="${WORK}.old.$$"
  STAGE_ERROR=

  [ -d "$parent" ] || {
    stage_error "parent directory missing: $parent"
    return 1
  }
  [ -w "$parent" ] || {
    stage_error "parent directory not writable: $parent"
    return 1
  }
  /system/bin/rm -rf "$tmp" "$old" 2>/dev/null || {
    stage_error "remove stale staging paths"
    return 1
  }
  /system/bin/mkdir "$tmp" 2>/dev/null || {
    stage_error "create temporary runtime directory"
    return 1
  }
  /system/bin/chmod 0755 "$tmp" 2>/dev/null || {
    stage_error "chmod temporary runtime directory"
    return 1
  }
  /system/bin/chcon u:object_r:system_file:s0 "$tmp" 2>/dev/null || {
    stage_error "label temporary runtime directory"
    return 1
  }

  staged=0
  if [ -r "$MODDIR/lib64/libzygisk.so" ]; then
    /system/bin/mkdir "$tmp/lib64" 2>/dev/null || {
      stage_error "create lib64 directory"
      return 1
    }
    /system/bin/cp -f "$MODDIR/lib64/libzygisk.so" "$tmp/lib64/libzygisk.so" 2>/dev/null || {
      stage_error "copy 64-bit libzygisk.so"
      return 1
    }
    /system/bin/chmod 0644 "$tmp/lib64/libzygisk.so" 2>/dev/null || {
      stage_error "chmod 64-bit libzygisk.so"
      return 1
    }
    /system/bin/chcon u:object_r:system_file:s0 "$tmp/lib64" "$tmp/lib64/libzygisk.so" 2>/dev/null || {
      stage_error "label 64-bit runtime"
      return 1
    }
    /system/bin/chmod 0555 "$tmp/lib64" 2>/dev/null || {
      stage_error "seal lib64 directory"
      return 1
    }
    staged=1
  fi

  if [ -r "$MODDIR/lib/libzygisk.so" ]; then
    /system/bin/mkdir "$tmp/lib" 2>/dev/null || {
      stage_error "create lib directory"
      return 1
    }
    /system/bin/cp -f "$MODDIR/lib/libzygisk.so" "$tmp/lib/libzygisk.so" 2>/dev/null || {
      stage_error "copy 32-bit libzygisk.so"
      return 1
    }
    /system/bin/chmod 0644 "$tmp/lib/libzygisk.so" 2>/dev/null || {
      stage_error "chmod 32-bit libzygisk.so"
      return 1
    }
    /system/bin/chcon u:object_r:system_file:s0 "$tmp/lib" "$tmp/lib/libzygisk.so" 2>/dev/null || {
      stage_error "label 32-bit runtime"
      return 1
    }
    /system/bin/chmod 0555 "$tmp/lib" 2>/dev/null || {
      stage_error "seal lib directory"
      return 1
    }
    staged=1
  fi

  [ "$staged" -eq 1 ] || {
    stage_error "no libzygisk.so was available"
    return 1
  }

  /system/bin/chmod 0555 "$tmp" 2>/dev/null || {
    stage_error "seal temporary runtime directory"
    return 1
  }

  if [ -e "$WORK" ]; then
    /system/bin/mv "$WORK" "$old" 2>/dev/null || {
      stage_error "move previous runtime aside"
      return 1
    }
  fi
  if ! /system/bin/mv "$tmp" "$WORK" 2>/dev/null; then
    [ -e "$old" ] && /system/bin/mv "$old" "$WORK" 2>/dev/null || true
    stage_error "publish staged runtime"
    return 1
  fi
  /system/bin/rm -rf "$old" 2>/dev/null || true
  log_line "runtime staged successfully at $WORK"
  return 0
}

start_monitor() {
  log_line "starting NeoZygisk monitor with runtime $WORK"
  (
    cd "$MODDIR" || exit 1
    [ "$DEBUG" = true ] && export RUST_BACKTRACE=1
    exec /system/bin/toybox setsid "$TRACER" monitor
  ) >> "$RUNLOG" 2>&1 </dev/null &

  n=0
  while [ "$n" -lt 15 ]; do
    /system/bin/sleep 1
    inspect_monitor
    if is_healthy; then
      return 0
    fi
    [ "$MONITOR_COUNT" -gt 1 ] && return 1
    n=$((n + 1))
  done
  return 1
}

ensure_runtime() {
  select_tracer || {
    write_status FAILED "tracer binary is unavailable"
    log_line "tracer binary is unavailable"
    return 1
  }

  inspect_monitor

  if marker_requires_full_reboot; then
    COLD_BOOT_REQUIRED=1
    write_status UPDATE_REQUIRES_FULL_REBOOT "this provider was updated while the previous kernel session was still active"
    log_line "update marker matches the current boot_id; refusing same-boot activation"
    return 3
  fi
  clear_marker_after_cold_boot || true

  if [ "$MONITOR_COUNT" -gt 1 ]; then
    COLD_BOOT_REQUIRED=1
    write_status FULL_REBOOT_REQUIRED "multiple NeoZygisk monitors detected"
    log_line "refusing to continue: multiple monitors detected: $MONITOR_LIST"
    return 3
  fi

  if generation_mismatch; then
    COLD_BOOT_REQUIRED=1
    write_status UPDATE_REQUIRES_FULL_REBOOT "the running monitor/runtime belongs to a different module generation"
    log_line "module update detected while an older monitor is alive: pid=$MONITOR_PID exe=$MONITOR_EXE binary_match=$MONITOR_BINARY_MATCH runtime_match=$RUNTIME_LIBRARY_MATCH"
    return 3
  fi

  if [ "$RUNTIME_MONITOR_CRASHED" -eq 1 ]; then
    COLD_BOOT_REQUIRED=1
    write_status ZYGOTE_CRASH_REQUIRES_FULL_REBOOT "runtime reports that zygote crashed"
    log_line "runtime reports stopped(zygote crashed); refusing in-session recovery"
    return 3
  fi

  if is_healthy; then
    write_status HEALTHY_REUSED "existing monitor is attached to init and matches the installed native generation"
    log_line "healthy same-generation monitor reused: pid=$MONITOR_PID"
    return 0
  fi

  if [ "$MONITOR_COUNT" -eq 1 ]; then
    COLD_BOOT_REQUIRED=1
    write_status UNHEALTHY_REQUIRES_FULL_REBOOT "an existing monitor is unhealthy; automatic resume is disabled"
    log_line "existing monitor is unhealthy: pid=$MONITOR_PID init_tracer=$INIT_TRACER socket=$WORK/init_monitor"
    return 3
  fi

  if [ "$INIT_TRACER" != 0 ]; then
    COLD_BOOT_REQUIRED=1
    write_status FULL_REBOOT_REQUIRED "init is already traced by unknown pid $INIT_TRACER"
    log_line "refusing to start monitor because init is traced by $INIT_TRACER"
    return 3
  fi

  stage_runtime || {
    write_status FAILED "unable to stage DEFEX-safe runtime"
    return 1
  }

  start_monitor || {
    inspect_monitor
    COLD_BOOT_REQUIRED=1
    write_status FULL_REBOOT_REQUIRED "monitor failed health verification"
    log_line "monitor failed verification: count=$MONITOR_COUNT pid=$MONITOR_PID init_tracer=$INIT_TRACER"
    return 3
  }

  write_status HEALTHY_STARTED "new same-generation monitor attached to init"
  log_line "monitor healthy: pid=$MONITOR_PID init_tracer=$INIT_TRACER"
  return 0
}

status_runtime() {
  select_tracer || {
    write_status FAILED "tracer binary is unavailable"
    return 1
  }
  inspect_monitor

  if marker_requires_full_reboot; then
    COLD_BOOT_REQUIRED=1
    write_status UPDATE_REQUIRES_FULL_REBOOT "this provider was updated while the previous kernel session was still active"
    return 3
  fi
  clear_marker_after_cold_boot || true

  if is_healthy; then
    write_status HEALTHY "monitor is attached to init and matches the installed native generation"
    return 0
  fi
  if generation_mismatch; then
    COLD_BOOT_REQUIRED=1
    write_status UPDATE_REQUIRES_FULL_REBOOT "the running monitor/runtime belongs to a different module generation"
    return 3
  fi
  if [ "$RUNTIME_MONITOR_CRASHED" -eq 1 ]; then
    COLD_BOOT_REQUIRED=1
    write_status ZYGOTE_CRASH_REQUIRES_FULL_REBOOT "runtime reports that zygote crashed"
    return 3
  fi
  if [ "$MONITOR_COUNT" -gt 0 ] || [ "$INIT_TRACER" != 0 ]; then
    COLD_BOOT_REQUIRED=1
    write_status UNHEALTHY_REQUIRES_FULL_REBOOT "monitor state is not safe for an in-session restart"
    return 3
  fi

  write_status NOT_RUNNING "no NeoZygisk monitor is attached"
  return 1
}

case "${1:-ensure}" in
  ensure)
    acquire_lock || exit 1
    trap release_lock EXIT INT TERM
    ensure_runtime
    exit $?
    ;;
  status)
    status_runtime
    exit $?
    ;;
  *)
    echo "usage: $0 [ensure|status]" >&2
    exit 2
    ;;
esac
