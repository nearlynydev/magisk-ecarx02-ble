#!/system/bin/sh
# Best-effort runtime rollback for the ECARX Bluetooth Magisk module.
# File overlays are reverted by Magisk only after the module is disabled/removed
# and the head unit is rebooted.

LOG=/data/adb/ecarx-bt-mtk-rollback.log
PKG=com.android.bluetooth
MODID=ecarx_e02_ihu717p_bt
MODDIR=/data/adb/modules/$MODID

run() {
  echo "+ $*" >> "$LOG"
  "$@" >> "$LOG" 2>&1
}

{
  echo "=== $(date) rollback start args=$* ==="

  resetprop ro.ecarx.bt_ismtk false 2>/dev/null || /sbin/resetprop ro.ecarx.bt_ismtk false 2>/dev/null || true
  echo "ro.ecarx.bt_ismtk=$(getprop ro.ecarx.bt_ismtk)"

  # Undo persistent runtime grants/appops added by service.sh. Some permissions
  # are signature/privileged and cannot be revoked through pm; failures are OK.
  for perm in \
    android.permission.ACCESS_COARSE_LOCATION \
    android.permission.GET_ACCOUNTS \
    android.permission.READ_CONTACTS \
    android.permission.WRITE_CONTACTS \
    android.permission.READ_CALL_LOG \
    android.permission.WRITE_CALL_LOG \
    android.permission.READ_EXTERNAL_STORAGE \
    android.permission.WRITE_EXTERNAL_STORAGE \
    android.permission.READ_SMS \
    android.permission.RECEIVE_SMS \
    android.permission.SEND_SMS \
    android.permission.WRITE_SMS; do
    pm revoke "$PKG" "$perm" >/dev/null 2>&1 || true
  done

  cmd appops reset "$PKG" >/dev/null 2>&1 || true

  # Return Bluetooth to a clean boot-time state. The stock ECARX/GOC path is
  # selected only after reboot because Magisk overlays and init properties are
  # evaluated during boot.
  run am force-stop "$PKG"
  run am force-stop com.ecarx.btphone
  setprop ctl.stop bluetooth-1-0 2>/dev/null || true

  if [ -d "$MODDIR" ] && [ "$1" != "--from-uninstall" ]; then
    touch "$MODDIR/disable" 2>/dev/null || true
    echo "module_disabled=$MODDIR/disable"
  fi

  echo "rollback done; reboot is required to remove systemless overlays"
} >> "$LOG" 2>&1

