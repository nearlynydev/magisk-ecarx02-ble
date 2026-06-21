#!/system/bin/sh
# Select the ECARX/MTK Bluetooth path before late userspace starts.
LOG=/data/adb/ecarx-bt-mtk.log
{
  echo "$(date) post-fs-data start"
  /sbin/resetprop ro.ecarx.bt_ismtk true 2>/dev/null || resetprop ro.ecarx.bt_ismtk true 2>/dev/null || true
  echo "$(date) ro.ecarx.bt_ismtk=$(getprop ro.ecarx.bt_ismtk)"
  setprop ctl.stop gocsdk 2>/dev/null || true
  echo "$(date) requested gocsdk stop, init.svc.gocsdk=$(getprop init.svc.gocsdk)"
} >> "$LOG" 2>&1
