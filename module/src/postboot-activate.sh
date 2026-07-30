#!/system/bin/sh

WORK=@WORK_DIRECTORY@
MODDIR=${0%/*}
SELF="$MODDIR/postboot-activate.sh"
BOOTSTRAP="$MODDIR/postboot-bootstrap.sh"
BOOTSTRAP_STATUS=/data/local/tmp/neozygisk-postboot.status
STATUS=/data/local/tmp/neozygisk-postboot-phase3.status
RUNLOG=/data/local/tmp/neozygisk-postboot-phase3.log
LOGCAT_FILE=/data/local/tmp/neozygisk-postboot-phase3-logcat.txt
LOCK=/data/local/tmp/neozygisk-postboot-phase3.lock
PIDFILE=/data/local/tmp/neozygisk-postboot-phase3.pid
RUNTIME_PROP="$WORK/module.prop"

MONITOR_PID=
INIT_TRACER=
OLD_ZYGOTE=
NEW_ZYGOTE=
OLD_SYSTEM_SERVER=
NEW_SYSTEM_SERVER=
DAEMON_PID=
ZYGOTE_RESTART_COUNT=0
TARGETED_RESTART_REQUESTED=0
MONITOR_HEALTHY=0
RUNTIME_PROP_INJECTED=0
RUNTIME_PROP_DAEMON_RUNNING=0
ACTIVITY_READY=0
LOGCAT_PID=
LOGCAT_CAPTURE=0

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
    echo "PHASE=3"
    echo "RESULT=$result"
    echo "DETAIL=$detail"
    echo "WORK=$WORK"
    echo "GLOBAL_SOFT_REBOOT_USED=0"
    echo "TARGETED_RESTART_REQUESTED=$TARGETED_RESTART_REQUESTED"
    echo "MONITOR_HEALTHY=$MONITOR_HEALTHY"
    echo "MONITOR_PID=${MONITOR_PID:-}"
    echo "INIT_TRACER=${INIT_TRACER:-}"
    echo "ZYGOTE_OLD_PID=${OLD_ZYGOTE:-}"
    echo "ZYGOTE_NEW_PID=${NEW_ZYGOTE:-}"
    echo "SYSTEM_SERVER_OLD_PID=${OLD_SYSTEM_SERVER:-}"
    echo "SYSTEM_SERVER_NEW_PID=${NEW_SYSTEM_SERVER:-}"
    echo "ZYGOTE_RESTART_COUNT=$ZYGOTE_RESTART_COUNT"
    echo "DAEMON_PID=${DAEMON_PID:-}"
    echo "RUNTIME_PROP_INJECTED=$RUNTIME_PROP_INJECTED"
    echo "RUNTIME_PROP_DAEMON_RUNNING=$RUNTIME_PROP_DAEMON_RUNNING"
    echo "ACTIVITY_READY=$ACTIVITY_READY"
    echo "LOGCAT_CAPTURE=$LOGCAT_CAPTURE"
    echo "LOGCAT_FILE=$LOGCAT_FILE"
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
    write_status BUSY "Phase 3 activation already running as pid $owner"
    return 1
  fi

  /system/bin/rm -rf "$LOCK" 2>/dev/null || return 1
  /system/bin/mkdir "$LOCK" 2>/dev/null || return 1
  echo $$ > "$LOCK/pid"
}

release_lock() {
  /system/bin/rm -rf "$LOCK" 2>/dev/null || true
  /system/bin/rm -f "$PIDFILE" 2>/dev/null || true
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

refresh_health() {
  if /system/bin/sh "$BOOTSTRAP" status >/dev/null 2>&1; then
    MONITOR_HEALTHY=1
  else
    MONITOR_HEALTHY=0
  fi
  MONITOR_PID=$(read_bootstrap_value MONITOR_PID 2>/dev/null || true)
  INIT_TRACER=$(read_bootstrap_value INIT_TRACER 2>/dev/null || true)

  if zygote_injected; then
    RUNTIME_PROP_INJECTED=1
  else
    RUNTIME_PROP_INJECTED=0
  fi
  if daemon_running; then
    RUNTIME_PROP_DAEMON_RUNNING=1
  else
    RUNTIME_PROP_DAEMON_RUNNING=0
  fi
  if activity_ready; then
    ACTIVITY_READY=1
  else
    ACTIVITY_READY=0
  fi
  DAEMON_PID=$(pid_for zygiskd64 zygiskd 2>/dev/null || true)
}

start_logcat() {
  /system/bin/rm -f "$LOGCAT_FILE" 2>/dev/null || true
  /system/bin/toybox setsid /system/bin/logcat -b all -v threadtime > "$LOGCAT_FILE" 2>&1 </dev/null &
  LOGCAT_PID=$!
  /system/bin/sleep 1
  if /system/bin/toybox kill -0 "$LOGCAT_PID" 2>/dev/null; then
    LOGCAT_CAPTURE=1
    log_line "logcat capture started as pid $LOGCAT_PID"
  else
    LOGCAT_PID=
    LOGCAT_CAPTURE=0
    log_line "logcat capture unavailable; continuing without it"
  fi
}

stop_logcat() {
  if [ -n "${LOGCAT_PID:-}" ]; then
    /system/bin/toybox kill "$LOGCAT_PID" 2>/dev/null || true
    wait "$LOGCAT_PID" 2>/dev/null || true
    LOGCAT_PID=
  fi
}

snapshot() {
  {
    echo
    echo "=== Phase 3 snapshot ==="
    echo "time=$(/system/bin/date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || /system/bin/date)"
    echo "init.svc.zygote=$(/system/bin/getprop init.svc.zygote 2>/dev/null)"
    echo "init.svc.zygote_secondary=$(/system/bin/getprop init.svc.zygote_secondary 2>/dev/null)"
    echo "zygote64=$(zygote_pid 2>/dev/null || true)"
    echo "system_server=$(system_server_pid 2>/dev/null || true)"
    echo "zygiskd=$(pid_for zygiskd64 zygiskd 2>/dev/null || true)"
    echo "init_tracer=$(while IFS=' :' read -r key value rest; do [ "$key" = TracerPid ] && { echo "$value"; break; }; done < /proc/1/status)"
    echo
    echo "=== Runtime module.prop ==="
    /system/bin/cat "$RUNTIME_PROP" 2>/dev/null || true
    echo
    echo "=== Process list matches ==="
    /system/bin/ps -A 2>/dev/null | /system/bin/toybox grep -E 'zygote|system_server|zygisk' 2>/dev/null || true
  } >> "$RUNLOG"
}

fail_activation() {
  detail=$1
  refresh_health
  snapshot
  write_status FAILED "$detail"
  log_line "Phase 3 failed: $detail"
  exit 1
}

finish_success() {
  detail=$1
  refresh_health
  snapshot
  write_status INJECTION_VERIFIED "$detail"
  log_line "Phase 3 succeeded: $detail"
  exit 0
}

run_activation() {
  [ "$(/system/bin/id -u 2>/dev/null)" = 0 ] || {
    write_status FAILED "root privileges are required"
    exit 1
  }

  acquire_lock || exit 1
  trap 'stop_logcat; release_lock' EXIT INT TERM
  : > "$RUNLOG"
  write_status STARTING "validating the Phase 2 monitor"
  log_line "Phase 3 activation started"

  [ -r "$BOOTSTRAP" ] || fail_activation "Phase 2 bootstrap is unavailable"
  if ! /system/bin/sh "$BOOTSTRAP" ensure >> "$RUNLOG" 2>&1; then
    fail_activation "Phase 2 monitor bootstrap is not healthy"
  fi

  refresh_health
  [ "$MONITOR_HEALTHY" -eq 1 ] || fail_activation "monitor is not attached to init"
  [ -n "$MONITOR_PID" ] || fail_activation "monitor pid is unavailable"
  [ "$INIT_TRACER" = "$MONITOR_PID" ] || fail_activation "init tracer does not match the NeoZygisk monitor"

  OLD_ZYGOTE=$(zygote_pid 2>/dev/null || true)
  OLD_SYSTEM_SERVER=$(system_server_pid 2>/dev/null || true)
  [ -n "$OLD_ZYGOTE" ] || fail_activation "current zygote64 pid is unavailable"
  [ -n "$OLD_SYSTEM_SERVER" ] || fail_activation "current system_server pid is unavailable"

  log_line "preflight healthy: monitor=$MONITOR_PID zygote=$OLD_ZYGOTE system_server=$OLD_SYSTEM_SERVER"

  if [ "$RUNTIME_PROP_INJECTED" -eq 1 ] && [ "$RUNTIME_PROP_DAEMON_RUNNING" -eq 1 ]; then
    NEW_ZYGOTE=$OLD_ZYGOTE
    NEW_SYSTEM_SERVER=$OLD_SYSTEM_SERVER
    ZYGOTE_RESTART_COUNT=0
    finish_success "current zygote is already reported as injected"
  fi

  start_logcat
  TARGETED_RESTART_REQUESTED=1
  write_status RESTART_REQUESTED "requesting one targeted zygote restart"
  log_line "requesting targeted init restart of zygote"

  if ! /system/bin/setprop ctl.restart zygote; then
    fail_activation "init rejected the targeted zygote restart command"
  fi

  last_zygote=$OLD_ZYGOTE
  n=0
  while [ "$n" -lt 90 ]; do
    current_zygote=$(zygote_pid 2>/dev/null || true)
    current_system_server=$(system_server_pid 2>/dev/null || true)

    if [ -n "$current_zygote" ] && [ "$current_zygote" != "$last_zygote" ]; then
      ZYGOTE_RESTART_COUNT=$((ZYGOTE_RESTART_COUNT + 1))
      last_zygote=$current_zygote
      log_line "observed zygote generation $ZYGOTE_RESTART_COUNT at pid $current_zygote"
    fi
    if [ -n "$current_zygote" ] && [ "$current_zygote" != "$OLD_ZYGOTE" ]; then
      NEW_ZYGOTE=$current_zygote
    fi
    if [ -n "$current_system_server" ] && [ "$current_system_server" != "$OLD_SYSTEM_SERVER" ]; then
      NEW_SYSTEM_SERVER=$current_system_server
    fi

    refresh_health

    if [ -n "$NEW_ZYGOTE" ] && [ -n "$NEW_SYSTEM_SERVER" ] && \
       [ "$MONITOR_HEALTHY" -eq 1 ] && \
       [ "$RUNTIME_PROP_INJECTED" -eq 1 ] && \
       [ "$RUNTIME_PROP_DAEMON_RUNNING" -eq 1 ] && \
       [ "$ACTIVITY_READY" -eq 1 ]; then
      finish_success "fresh zygote injection verified after one targeted restart"
    fi

    if [ "$ZYGOTE_RESTART_COUNT" -ge 3 ]; then
      fail_activation "multiple zygote generations were observed before injection verified"
    fi

    if [ "$n" -eq 15 ] && [ -z "$NEW_ZYGOTE" ]; then
      fail_activation "targeted zygote restart was not accepted within 15 seconds"
    fi

    /system/bin/sleep 1
    n=$((n + 1))
  done

  fail_activation "fresh zygote injection did not verify within 90 seconds"
}

start_detached() {
  [ "$(/system/bin/id -u 2>/dev/null)" = 0 ] || {
    echo "root privileges are required" >&2
    exit 1
  }

  owner=$(/system/bin/cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$owner" ] && [ -d "/proc/$owner" ]; then
    echo "Phase 3 activation is already running as pid $owner"
    exit 1
  fi

  /system/bin/toybox setsid /system/bin/sh "$SELF" run >> "$RUNLOG" 2>&1 </dev/null &
  launcher=$!
  echo "$launcher" > "$PIDFILE"
  echo "Phase 3 activation started as pid $launcher. Android userspace will restart once if preflight succeeds."
}

show_status() {
  echo "=== Phase 3 status ==="
  /system/bin/cat "$STATUS" 2>/dev/null || echo "No Phase 3 status recorded"
  echo
  echo "=== Runtime module.prop ==="
  /system/bin/cat "$RUNTIME_PROP" 2>/dev/null || echo "Runtime module.prop is unavailable"
  echo
  echo "=== Recent Phase 3 log ==="
  /system/bin/toybox tail -n 120 "$RUNLOG" 2>/dev/null || echo "No Phase 3 log recorded"
}

case "${1:-status}" in
  start|activate) start_detached ;;
  run) run_activation ;;
  status) show_status ;;
  *) echo "usage: $0 [start|status]" >&2; exit 2 ;;
esac
