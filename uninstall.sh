#!/system/bin/sh
LOG=/data/adb/ecarx-bt-mtk.log
{
  echo "$(date) module uninstall"
  resetprop ro.ecarx.bt_ismtk false 2>/dev/null || true
} >> "$LOG" 2>&1
