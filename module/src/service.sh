#!/system/bin/sh

DEBUG=@DEBUG@

MODDIR=${0%/*}
if [ "$ZYGISK_ENABLED" ]; then
  exit 0
fi

cd "$MODDIR" || exit 1

if [ "$(which magisk)" ]; then
  for file in ../*; do
    if [ -d "$file" ] && [ -d "$file/zygisk" ] && ! [ -f "$file/disable" ]; then
      if [ -f "$file/service.sh" ]; then
        cd "$file" || continue
        log -p i -t "zygisk-sh" "Manually trigger service.sh for $file"
        sh "$(realpath ./service.sh)" &
        cd "$MODDIR" || exit 1
      fi
    fi
  done
fi

/system/bin/sh "$MODDIR/postboot-bootstrap.sh" ensure
