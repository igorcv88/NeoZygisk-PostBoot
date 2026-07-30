printf "Status of NeoZygisk PostBoot\n\n"

echo "=== Phase 2 bootstrap status ==="
cat /data/local/tmp/neozygisk-postboot.status 2>/dev/null || echo "No bootstrap status recorded"

echo
echo "=== Phase 3 activation status ==="
cat /data/local/tmp/neozygisk-postboot-phase3.status 2>/dev/null || echo "No Phase 3 activation status recorded"

echo
echo "=== Runtime status ==="
cat @WORK_DIRECTORY@/module.prop 2>/dev/null || echo "Runtime module.prop is unavailable"

echo
echo "=== Recent Phase 2 bootstrap log ==="
tail -n 60 /data/local/tmp/neozygisk-postboot.log 2>/dev/null || echo "No bootstrap log recorded"

echo
echo "=== Recent Phase 3 activation log ==="
tail -n 100 /data/local/tmp/neozygisk-postboot-phase3.log 2>/dev/null || echo "No Phase 3 activation log recorded"

if [ -z "${MMRL:-}" ] && { [ -n "${KSU:-}" ] || [ -n "${APATCH:-}" ]; }; then
  sleep 5
fi