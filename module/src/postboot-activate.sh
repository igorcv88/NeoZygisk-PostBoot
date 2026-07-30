#!/system/bin/sh

WORK=@WORK_DIRECTORY@
MODDIR=${0%/*}
BOOTSTRAP="$MODDIR/postboot-bootstrap.sh"
BOOTSTRAP_STATUS=/data/local/tmp/neozygisk-postboot.status
STATUS=/data/local/tmp/neozygisk-postboot-phase3.status
RUNLOG=/data/local/tmp/neozygisk-postboot-phase3.log
RUNTIME_PROP="$WORK/module.prop"

MONITOR_PID=
INIT_TRACER=
ZYGOTE_PID=
SYSTEM_SERVER_PID=
DAEMON_PID=
MONITOR_HEALTHY=0
RUNTIME_PROP_INJECTED=0
RUNTIME_PROP_DAEMON_RUNNING=0
ACTIVITY_READY=0
CP64_SOCKET_READY=0
LIBRARY_MAPPED_IN_ZYGOTE=0

log_line() {
  now=$(/system/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || /system/bin/date)
  echo "$now $*" >> "$RUNLOG"
  /system/bin/log -p i -t neozygisk-postboot-phase3 "$*" 2>/dev/null || true
}

write_status() {
  result=$1
  detail=${2:-}
  tmp="${STATUS}.tmp.$$"
  {
    echo "PHASE=3.1"
    echo "RESULT=$result"
    echo "DETAIL=$detail"
    echo "WORK=$WORK"
    echo "RESTART_TRIGGERED_BY_MODULE=0"
    echo "TARGETED_ZYGOTE_RESTART_USED=0"
    echo "GLOBAL_SOFT_REBOOT_USED_BY_MODULE=0"
    echo "MANUAL_KERNELSU_SOFT_REBOOT_REQUIRED=1"
    echo "MONITOR_HEALTHY=$MONITOR_HEALTHY"
    echo "MONITOR_PID=${MONITOR_PID:-}"
    echo "INIT_TRACER=${INIT_TRACER:-}"
    echo "ZYGOTE_PID=${ZYGOTE_PID:-}"
    echo "SYSTEM_SERVER_PID=${SYSTEM_SERVER_PID:-}"
    echo "DAEMON_PID=${DAEMON_PID:-}"
    echo "RUNTIME_PROP_INJECTED=$RUNTIME_PROP_INJECTED"
    echo "RUNTIME_PROP_DAEMON_RUNNING=$RUNTIME_PROP_DAEMON_RUNNING"
    echo "ACTIVITY_READY=$ACTIVITY_READY"
    echo "CP64_SOCKET_READY=$CP64_SOCKET_READY"
    echo "LIBRARY_MAPPED_IN_ZYGOTE=$LIBRARY_MAPPED_IN_ZYGOTE"
    echo "TIMESTAMP=$(/system/bin/date +%s 2>/dev/null || echo 0)"
  } > "$tmp"
  /system/bin/chmod 0644 "$tmp" 2>/dev/null || true
  /system/bin/mv -f "$tmp" "$STATUS"
}

read_bootstrap_value() {
  wanted=$1
  [ -r "$BOOTSTRAP_STATUS" ] || return 1
  while IFS='=' read -r key value; do
    [ "$key" = "$wanted" ] || continue
    echo "$value"
    return 0
  done < "$BOOTSTRAP_STATUS"
  return 1
}

pid_for() {
  for name in "$@"; do
    found=$(/system/bin/toybox pidof "$name" 2>/dev/null || true)
    for pid in $found; do
      case "$pid" in
        ''|*[!0-9]*) ;;
        *) echo "$pid"; return 0 ;;
      esac
    done
  done
  return 1
}

zygote_pid() {
  pid=$(pid_for zygote64 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    cmd=$(/system/bin/toybox tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *app_process64*--zygote*|*zygote64*)
        echo "${proc#/proc/}"
        return 0
        ;;
    esac
  done
  return 1
}

system_server_pid() {
  pid=$(pid_for system_server 2>/dev/null || true)
  if [ -n "$pid" ]; then
    echo "$pid"
    return 0
  fi

  for proc in /proc/[0-9]*; do
    [ -r "$proc/cmdline" ] || continue
    cmd=$(/system/bin/toybox tr '\000' ' ' < "$proc/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *system_server*) echo "${proc#/proc/}"; return 0 ;;
    esac
  done
  return 1
}

runtime_line() {
  label=$1
  [ -r "$RUNTIME_PROP" ] || return 1
  /system/bin/toybox grep -F "$label" "$RUNTIME_PROP" 2>/dev/null | /system/bin/toybox head -n 1
}

zygote_injected() {
  line=$(runtime_line 'zygote64:' 2>/dev/null || true)
  case "$line" in
    *'not injected'*) return 1 ;;
    *'injected'*) return 0 ;;
  esac
  return 1
}

daemon_running() {
  line=$(runtime_line 'daemon64:' 2>/dev/null || true)
  case "$line" in
    *'running'*) return 0 ;;
  esac
  return 1
}

activity_ready() {
  /system/bin/service check activity >/dev/null 2>&1
}

library_mapped() {
  [ -n "$ZYGOTE_PID" ] || return 1
  [ -r "/proc/$ZYGOTE_PID/maps" ] || return 1
  /system/bin/toybox grep -F "$WORK/lib64/libzygisk.so" "/proc/$ZYGOTE_PID/maps" >/dev/null 2>&1
}

refresh_health() {
  if [ -r "$BOOTSTRAP" ] && /system/bin/sh "$BOOTSTRAP" status >/dev/null 2>&1; then
    MONITOR_HEALTHY=1
  else
    MONITOR_HEALTHY=0
  fi

  MONITOR_PID=$(read_bootstrap_value MONITOR_PID 2>/dev/null || true)
  INIT_TRACER=$(read_bootstrap_value INIT_TRACER 2>/dev/null || true)
  ZYGOTE_PID=$(zygote_pid 2>/dev/null || true)
  SYSTEM_SERVER_PID=$(system_server_pid 2>/dev/null || true)
  DAEMON_PID=$(pid_for zygiskd64 zygiskd 2>/dev/null || true)

  if zygote_injected; then RUNTIME_PROP_INJECTED=1; else RUNTIME_PROP_INJECTED=0; fi
  if daemon_running; then RUNTIME_PROP_DAEMON_RUNNING=1; else RUNTIME_PROP_DAEMON_RUNNING=0; fi
  if activity_ready; then ACTIVITY_READY=1; else ACTIVITY_READY=0; fi
  if [ -S "$WORK/cp64.sock" ]; then CP64_SOCKET_READY=1; else CP64_SOCKET_READY=0; fi
  if library_mapped; then LIBRARY_MAPPED_IN_ZYGOTE=1; else LIBRARY_MAPPED_IN_ZYGOTE=0; fi
}

snapshot() {
  {
    echo
    echo "=== Phase 3.1 snapshot ==="
    echo "time=$(/system/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || /system/bin/date)"
    echo "build=$(/system/bin/getprop ro.build.display.id 2>/dev/null)"
    echo "kernel=$(/system/bin/uname -r 2>/dev/null)"
    echo "zygote64=${ZYGOTE_PID:-}"
    echo "system_server=${SYSTEM_SERVER_PID:-}"
    echo "zygiskd=${DAEMON_PID:-}"
    echo "init_tracer=${INIT_TRACER:-}"
    echo
    echo "=== Runtime module.prop ==="
    /system/bin/cat "$RUNTIME_PROP" 2>/dev/null || true
    echo
    echo "=== Runtime files ==="
    /system/bin/ls -laZ "$WORK" 2>/dev/null || true
  } >> "$RUNLOG"
}

verify_state() {
  [ "$(/system/bin/id -u 2>/dev/null)" = 0 ] || {
    write_status FAILED "root privileges are required"
    exit 1
  }

  : > "$RUNLOG"
  log_line "Phase 3.1 read-only verification started"

  n=0
  while [ "$n" -lt 30 ]; do
    refresh_health

    if [ "$MONITOR_HEALTHY" -eq 1 ] && \
       [ -n "$MONITOR_PID" ] && \
       [ "$INIT_TRACER" = "$MONITOR_PID" ] && \
       [ -n "$ZYGOTE_PID" ] && \
       [ -n "$SYSTEM_SERVER_PID" ] && \
       [ -n "$DAEMON_PID" ] && \
       [ "$RUNTIME_PROP_INJECTED" -eq 1 ] && \
       [ "$RUNTIME_PROP_DAEMON_RUNNING" -eq 1 ] && \
       [ "$ACTIVITY_READY" -eq 1 ] && \
       [ "$CP64_SOCKET_READY" -eq 1 ] && \
       [ "$LIBRARY_MAPPED_IN_ZYGOTE" -eq 1 ]; then
      snapshot
      write_status INJECTION_VERIFIED "healthy NeoZygisk state verified after an external KernelSU module lifecycle"
      log_line "Phase 3.1 succeeded without initiating any restart"
      exit 0
    fi

    /system/bin/sleep 1
    n=$((n + 1))
  done

  snapshot
  if [ "$MONITOR_HEALTHY" -eq 1 ] && [ "$INIT_TRACER" = "$MONITOR_PID" ] && \
     { [ "$RUNTIME_PROP_INJECTED" -eq 0 ] || [ "$RUNTIME_PROP_DAEMON_RUNNING" -eq 0 ]; }; then
    write_status WAITING_FOR_KERNELSU_SOFT_REBOOT "monitor is healthy, but zygote injection is not active; use KernelSU Manager Soft Reboot from a clean post-exploit session and verify again"
    log_line "Phase 3.1 is waiting for the external KernelSU module lifecycle"
    exit 2
  fi

  write_status NOT_HEALTHY "NeoZygisk post-reboot state did not satisfy all verification checks"
  log_line "Phase 3.1 verification failed without initiating recovery"
  exit 1
}

show_status() {
  echo "=== Phase 3.1 verification status ==="
  /system/bin/cat "$STATUS" 2>/dev/null || echo "No Phase 3.1 status recorded"
  echo
  echo "=== Runtime module.prop ==="
  /system/bin/cat "$RUNTIME_PROP" 2>/dev/null || echo "Runtime module.prop is unavailable"
  echo
  echo "=== Recent Phase 3.1 log ==="
  /system/bin/toybox tail -n 120 "$RUNLOG" 2>/dev/null || echo "No Phase 3.1 log recorded"
}

case "${1:-status}" in
  verify|start|activate) verify_state ;;
  status) show_status ;;
  *) echo "usage: $0 [verify|status]" >&2; exit 2 ;;
esac
