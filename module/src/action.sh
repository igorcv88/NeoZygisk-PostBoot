#!/system/bin/sh

MODDIR=${0%/*}
VERIFY="$MODDIR/postboot-activate.sh"

printf "NeoZygisk PostBoot live verification\n\n"
echo "This action never restarts zygote, Android userspace, or the device."
echo "After a NeoZygisk binary update, do not use Soft Reboot in the same kernel boot."
echo "Required update lifecycle: full reboot -> simple exploit -> one KernelSU Manager Soft Reboot -> verify."
echo

if [ -r "$VERIFY" ]; then
  /system/bin/sh "$VERIFY" status
  VERIFY_RC=$?
else
  echo "Verification helper is unavailable"
  VERIFY_RC=1
fi

echo
echo "=== Phase 2 bootstrap status ==="
cat /data/local/tmp/neozygisk-postboot.status 2>/dev/null || echo "No bootstrap status recorded"

echo
echo "=== Runtime status ==="
cat @WORK_DIRECTORY@/module.prop 2>/dev/null || echo "Runtime module.prop is unavailable"

echo
echo "=== Recent Phase 2 bootstrap log ==="
tail -n 80 /data/local/tmp/neozygisk-postboot.log 2>/dev/null || echo "No bootstrap log recorded"

echo
echo "verification_rc=$VERIFY_RC"

if [ -z "${MMRL:-}" ] && { [ -n "${KSU:-}" ] || [ -n "${APATCH:-}" ]; }; then
  sleep 5
fi

exit "$VERIFY_RC"
