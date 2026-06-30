#!/system/bin/sh
SKIPUNZIP=0

ui_print "- ECARX E02 IHU717P Geely/Knewstar Bluetooth"
ui_print "- Overlaying Bluetooth app at stock /system/app/Bluetooth path, ECARX E02 Bluetooth libs, permissions, and hidden API whitelist"
ui_print "- Setting file permissions"

set_perm_recursive "$MODPATH/system" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
[ -f "$MODPATH/rollback.sh" ] && set_perm "$MODPATH/rollback.sh" 0 0 0755

# Back up the stock bluedroid pairing/config once, before the module's MTK stack
# overwrites it on the next boot. rollback.sh restores this on removal so the
# head unit returns to its original pairings instead of a wiped config. The
# backup lives outside the module (survives uninstall) and is only taken when it
# does not already exist, so the very first install captures the true stock
# state and later updates keep it.
STOCK_BK=/data/adb/ecarx-bt-stock-backup
if [ ! -f "$STOCK_BK/bt_config.conf" ] && [ -f /data/misc/bluedroid/bt_config.conf ]; then
  mkdir -p "$STOCK_BK" 2>/dev/null
  cp -af /data/misc/bluedroid/bt_config.conf "$STOCK_BK/bt_config.conf" 2>/dev/null && \
    ui_print "- Saved stock bluedroid config backup to $STOCK_BK"
  cp -af /data/misc/bluedroid/bt_config.bak  "$STOCK_BK/bt_config.bak"  2>/dev/null || true
else
  ui_print "- Stock bluedroid backup already present or no config to back up"
fi

ui_print "- Done. Reboot after installation."
