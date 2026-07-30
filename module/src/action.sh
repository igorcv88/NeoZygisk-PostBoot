printf "Status of NeoZygisk PostBoot\n\n"

echo "=== Bootstrap status ==="
cat /data/local/tmp/neozygisk-postboot.status 2>/dev/null || echo "No bootstrap status recorded"

echo
echo "=== Runtime status ==="
cat @WORK_DIRECTORY@/module.prop 2>/dev/null || echo "Runtime module.prop is unavailable"

echo
echo "=== Recent bootstrap log ==="
tail -n 80 /data/local/tmp/neozygisk-postboot.log 2>/dev/null || echo "No bootstrap log recorded"

if [[ -z "$MMRL" ]] && ([[ -n "$KSU" ]] || [[ -n "$APATCH" ]]); then
  sleep 5
fi
