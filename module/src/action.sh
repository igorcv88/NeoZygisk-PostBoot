#!/system/bin/sh

MODDIR=${0%/*}
VERIFY="$MODDIR/postboot-activate.sh"

printf "NeoZygisk PostBoot verification\n\n"
echo "This action never restarts zygote, Android userspace, or the device."
echo "Expected lifecycle: simple exploit -> KernelSU Manager Soft Reboot -> verify."
echo

if [ -r "$VERIFY" ]; then
  /system/bin/sh "$VERIFY" verify
  VERIFY_RC=$?
else
  echo "Verification helper is unavailable"
  VERIFY_RC=1
fi

echo
echo "=== Phase 2 bootstrap status ==="
cat /data/local/tmp/neozygisk-postboot.status 2>/dev/null || echo "No bootstrap status recorded"

echo
echo "=== Phase 3.1 verification status ==="
cat /data/local/tmp/neozygisk-postboot-phase3.status 2>/dev/null || echo "No Phase 3.1 verification status recorded"

echo
echo "=== Runtime status ==="
cat @WORK_DIRECTORY@/module.prop 2>/dev/null || echo "Runtime module.prop is unavailable"

echo
echo "=== Recent Phase 2 bootstrap log ==="
tail -n 60 /data/local/tmp/neozygisk-postboot.log 2>/dev/null || echo "No bootstrap log recorded"

echo
echo "=== Recent Phase 3.1 verification log ==="
tail -n 100 /data/local/tmp/neozygisk-postboot-phase3.log 2>/dev/null || echo "No Phase 3.1 verification log recorded"

echo
echo "verification_rc=$VERIFY_RC"

if [ -z "${MMRL:-}" ] && { [ -n "${KSU:-}" ] || [ -n "${APATCH:-}" ]; }; then
  sleep 5
fi

exit "$VERIFY_RC"
