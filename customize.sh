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

ui_print "- Done. Reboot after installation."
