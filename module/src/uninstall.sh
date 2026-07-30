#!/system/bin/sh

WORK=@WORK_DIRECTORY@

rm -rf "$WORK"
rm -rf /data/local/tmp/neozygisk-postboot.lock
rm -f /data/local/tmp/neozygisk-postboot.status
rm -f /data/local/tmp/neozygisk-postboot.log
