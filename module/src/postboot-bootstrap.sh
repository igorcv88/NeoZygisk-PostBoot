#!/system/bin/sh

DEBUG=@DEBUG@
WORK=@WORK_DIRECTORY@
MODDIR=${0%/*}
STATUS=/data/local/tmp/neozygisk-postboot.status
RUNLOG=/data/local/tmp/neozygisk-postboot.log
LOCK=/data/local/tmp/neozygisk-postboot.lock
STAGE_ERROR=

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
    echo "INIT_TRACER=${INIT_TRACER:-}"
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

select_tracer() {
  if [ -x "$MODDIR/bin/zygisk-ptrace64" ]; then
    TRACER="$MODDIR/bin/zygisk-ptrace64"
  elif [ -x "$MODDIR/bin/zygisk-ptrace32" ]; then
    TRACER="$MODDIR/bin/zygisk-ptrace32"
  else
    return 1
  fi
}

get_init_tracer() {
  while IFS=' :' read -r key value rest; do
    [ "$key" = "TracerPid" ] || continue
    echo "$value"
    return 0
  done < /proc/1/status
  return 1
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

inspect_monitor() {
  MONITOR_LIST=$(monitor_pids)
  MONITOR_COUNT=0
  MONITOR_PID=
  for pid in $MONITOR_LIST; do
    MONITOR_COUNT=$((MONITOR_COUNT + 1))
    [ -n "$MONITOR_PID" ] || MONITOR_PID=$pid
  done
  INIT_TRACER=$(get_init_tracer 2>/dev/null || true)
  [ -n "$INIT_TRACER" ] || INIT_TRACER=0
}

is_healthy() {
  [ "$MONITOR_COUNT" -eq 1 ] || return 1
  [ "$INIT_TRACER" = "$MONITOR_PID" ] || return 1
  [ -S "$WORK/init_monitor" ] || return 1
  return 0
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
  /system/bin/chmod 0555 "$tmp" 2>/dev/null || {
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
    /system/bin/chmod 0555 "$tmp/lib64" 2>/dev/null || {
      stage_error "chmod lib64 directory"
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
    /system/bin/chmod 0555 "$tmp/lib" 2>/dev/null || {
      stage_error "chmod lib directory"
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
    staged=1
  fi

  [ "$staged" -eq 1 ] || {
    stage_error "no libzygisk.so was available"
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

  if [ "$MONITOR_COUNT" -gt 1 ]; then
    write_status FAILED "multiple NeoZygisk monitors detected"
    log_line "refusing to continue: multiple monitors detected: $MONITOR_LIST"
    return 1
  fi

  if is_healthy; then
    write_status HEALTHY_REUSED "existing monitor is attached to init"
    log_line "healthy monitor reused: pid=$MONITOR_PID"
    return 0
  fi

  if [ "$MONITOR_COUNT" -eq 1 ]; then
    if [ "$INIT_TRACER" != 0 ] && [ "$INIT_TRACER" != "$MONITOR_PID" ]; then
      write_status FAILED "init is traced by unknown pid $INIT_TRACER"
      log_line "refusing ctl start: init tracer $INIT_TRACER does not match monitor $MONITOR_PID"
      return 1
    fi

    if [ -S "$WORK/init_monitor" ]; then
      log_line "requesting existing monitor to resume tracing"
      "$TRACER" ctl start >> "$RUNLOG" 2>&1 || true
      n=0
      while [ "$n" -lt 8 ]; do
        /system/bin/sleep 1
        inspect_monitor
        if is_healthy; then
          write_status HEALTHY_RESUMED "existing monitor resumed tracing"
          return 0
        fi
        n=$((n + 1))
      done
    fi

    write_status FAILED "existing monitor is unhealthy; no destructive cleanup was attempted"
    log_line "existing monitor is unhealthy: pid=$MONITOR_PID init_tracer=$INIT_TRACER socket=$WORK/init_monitor"
    return 1
  fi

  if [ "$INIT_TRACER" != 0 ]; then
    write_status FAILED "init is already traced by unknown pid $INIT_TRACER"
    log_line "refusing to start monitor because init is traced by $INIT_TRACER"
    return 1
  fi

  stage_runtime || {
    write_status FAILED "unable to stage DEFEX-safe runtime"
    return 1
  }

  start_monitor || {
    inspect_monitor
    write_status FAILED "monitor failed health verification"
    log_line "monitor failed verification: count=$MONITOR_COUNT pid=$MONITOR_PID init_tracer=$INIT_TRACER"
    return 1
  }

  write_status HEALTHY_STARTED "new monitor attached to init"
  log_line "monitor healthy: pid=$MONITOR_PID init_tracer=$INIT_TRACER"
  return 0
}

case "${1:-ensure}" in
  ensure)
    acquire_lock || exit 1
    trap release_lock EXIT INT TERM
    ensure_runtime
    exit $?
    ;;
  status)
    select_tracer || exit 1
    inspect_monitor
    if is_healthy; then
      write_status HEALTHY "monitor is attached to init"
      exit 0
    fi
    write_status NOT_HEALTHY "count=$MONITOR_COUNT init_tracer=$INIT_TRACER"
    exit 1
    ;;
  *)
    echo "usage: $0 [ensure|status]" >&2
    exit 2
    ;;
esac
