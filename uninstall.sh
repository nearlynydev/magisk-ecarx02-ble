#!/system/bin/sh
LOG=/data/adb/ecarx-bt-mtk.log
{
  echo "$(date) module uninstall"
  MODDIR="${0%/*}"
  if [ -x "$MODDIR/rollback.sh" ]; then
    "$MODDIR/rollback.sh" --from-uninstall
  else
    resetprop ro.ecarx.bt_ismtk false 2>/dev/null || true
  fi
} >> "$LOG" 2>&1
