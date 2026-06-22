#!/system/bin/sh
# Best-effort runtime rollback for the ECARX Bluetooth Magisk module.
# File overlays are reverted by Magisk only after the module is disabled/removed
# and the head unit is rebooted.

LOG=/data/adb/ecarx-bt-mtk-rollback.log
PKG=com.android.bluetooth
CONTACTS_PROVIDER=com.android.providers.contacts
MODID=ecarx_e02_ihu717p_bt
MODDIR=/data/adb/modules/$MODID
CONTACTS_DB_DIR=/data/data/$CONTACTS_PROVIDER/databases
BT_CE_DIR=/data/user/0/$PKG
BT_DE_DIR=/data/user_de/0/$PKG

run() {
  echo "+ $*" >> "$LOG"
  "$@" >> "$LOG" 2>&1
}

cleanup_btphone_cache() {
  run am force-stop com.ecarx.btphone
  rm -rf \
    /data/data/com.ecarx.btphone/cache \
    /data/data/com.ecarx.btphone/code_cache \
    >/dev/null 2>&1 || true
  echo "btphone_cache_cleared"
}

cleanup_bluetooth_app_data() {
  echo "bluetooth_app_data_cleanup_start"

  # The module Bluetooth.apk creates a newer OPP database than the stock ECARX
  # Bluetooth.apk expects. If this database survives rollback, stock Bluetooth
  # crashes in a loop with "Can't downgrade database from version 2 to 1".
  for dir in "$BT_CE_DIR" "$BT_DE_DIR"; do
    [ -d "$dir" ] || continue
    rm -rf \
      "$dir/databases" \
      "$dir/shared_prefs" \
      "$dir/cache" \
      "$dir/code_cache" \
      >/dev/null 2>&1 || true
    mkdir -p "$dir/cache" "$dir/code_cache" >/dev/null 2>&1 || true
    chown -R bluetooth:bluetooth "$dir" >/dev/null 2>&1 || true
    restorecon -R "$dir" >/dev/null 2>&1 || true
    echo "bluetooth_app_data_cleared=$dir"
  done
}

cleanup_provider_data() {
  echo "provider_cleanup_start"

  # First try the public providers. On some ECARX Android 9 builds the `content`
  # command aborts, so this is best-effort only.
  content delete --uri content://com.android.contacts/raw_contacts \
    --where "account_type='com.android.bluetooth.pbapsink' OR account_type='com.android.bluetooth' OR account_name='com.android.bluetooth'" \
    >/dev/null 2>&1 || true
  content delete --uri content://call_log/calls \
    --where "subscription_id='-290325860' OR subscription_component_name='com.android.bluetooth/com.android.bluetooth.hfpclient.connserv.HfpClientConnectionService'" \
    >/dev/null 2>&1 || true

  # Rollback should leave the head unit as close to stock as possible. The module
  # imports phonebook/call-log data into ContactsProvider, and those rows are not
  # owned by com.android.bluetooth anymore. Since this head-unit use case has no
  # local address book outside the Bluetooth import path, clear the provider DBs
  # when direct provider deletion is unavailable or incomplete.
  run am force-stop "$CONTACTS_PROVIDER"
  if [ -d "$CONTACTS_DB_DIR" ]; then
    rm -f \
      "$CONTACTS_DB_DIR/contacts2.db" \
      "$CONTACTS_DB_DIR/contacts2.db-shm" \
      "$CONTACTS_DB_DIR/contacts2.db-wal" \
      "$CONTACTS_DB_DIR/contacts2.db-journal" \
      "$CONTACTS_DB_DIR/calllog.db" \
      "$CONTACTS_DB_DIR/calllog.db-shm" \
      "$CONTACTS_DB_DIR/calllog.db-wal" \
      "$CONTACTS_DB_DIR/calllog.db-journal" \
      >/dev/null 2>&1 || true
    echo "provider_dbs_removed=$CONTACTS_DB_DIR"
  else
    echo "provider_db_dir_missing=$CONTACTS_DB_DIR"
  fi
}

cleanup_bluetooth_data() {
  echo "bluetooth_data_cleanup_start"

  # Clear pairing/profile/GATT cache and snoop/firmware logs left by the
  # experimental stack. These files are recreated by the stock Bluetooth service
  # after reboot.
  rm -f \
    /data/misc/bluedroid/bt_config.conf \
    /data/misc/bluedroid/bt_config.bak \
    /data/misc/bluedroid/btsnoop_hci.log \
    /data/misc/bluetooth/btsnoop_hci.log \
    /data/misc/bluetooth/logs/firmware_events.log \
    /data/misc/bluetooth/logs/firmware_events.log.last \
    /sdcard/btsnoop_hci.log \
    >/dev/null 2>&1 || true
  rm -rf \
    /data/misc/bluetooth/cache \
    /data/misc/bluetooth/logs \
    >/dev/null 2>&1 || true

  echo "bluetooth_data_cleanup_done"
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
  cleanup_btphone_cache
  setprop ctl.stop bluetooth-1-0 2>/dev/null || true
  cleanup_bluetooth_app_data
  cleanup_bluetooth_data
  cleanup_provider_data

  if [ -d "$MODDIR" ] && [ "$1" != "--from-uninstall" ]; then
    touch "$MODDIR/disable" 2>/dev/null || true
    echo "module_disabled=$MODDIR/disable"
  fi

  echo "rollback done; reboot is required to remove systemless overlays"
} >> "$LOG" 2>&1
