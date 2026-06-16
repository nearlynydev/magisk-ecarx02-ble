#!/system/bin/sh
# Bring up the MTK STP Bluetooth transport and start Bluetooth once it exists.
(
  LOG=/data/adb/ecarx-bt-mtk.log
  echo "$(date) service start" >> "$LOG"

  resetprop ro.ecarx.bt_ismtk true 2>/dev/null || /sbin/resetprop ro.ecarx.bt_ismtk true 2>/dev/null || true
  echo "$(date) prop ro.ecarx.bt_ismtk=$(getprop ro.ecarx.bt_ismtk)" >> "$LOG"

  for i in $(seq 1 90); do
    [ "$(getprop vendor.connsys.driver.ready)" = "yes" ] && break
    sleep 1
  done
  echo "$(date) connsys.ready=$(getprop vendor.connsys.driver.ready)" >> "$LOG"

  if ! grep -q '^bt_drv ' /proc/modules 2>/dev/null; then
    echo "$(date) insmod bt_drv.ko" >> "$LOG"
    insmod /vendor/lib/modules/bt_drv.ko >> "$LOG" 2>&1 || true
  else
    echo "$(date) bt_drv already loaded" >> "$LOG"
  fi

  for i in $(seq 1 20); do
    [ -e /dev/stpbt ] && break
    sleep 1
  done

  if [ -e /dev/stpbt ]; then
    chown bluetooth:bluetooth /dev/stpbt 2>/dev/null || true
    chmod 0660 /dev/stpbt 2>/dev/null || true
    restorecon /dev/stpbt 2>/dev/null || true
  fi
  ls -lZ /dev/stpbt /dev/btif >> "$LOG" 2>&1 || true
  grep -E '^(bt_drv|wmt_drv) ' /proc/modules >> "$LOG" 2>&1 || true

  for i in $(seq 1 90); do
    [ "$(getprop sys.boot_completed)" = "1" ] && break
    sleep 1
  done

  echo "$(date) hidden_api=$(settings get global hidden_api_policy 2>/dev/null),$(settings get global hidden_api_policy_p_apps 2>/dev/null),$(settings get global hidden_api_policy_pre_p_apps 2>/dev/null)" >> "$LOG"

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
    pm grant com.android.bluetooth "$perm" >> "$LOG" 2>&1 || true
  done
  for op in \
    COARSE_LOCATION \
    GET_ACCOUNTS \
    READ_CONTACTS \
    WRITE_CONTACTS \
    READ_CALL_LOG \
    WRITE_CALL_LOG \
    READ_EXTERNAL_STORAGE \
    WRITE_EXTERNAL_STORAGE \
    READ_SMS \
    RECEIVE_SMS \
    SEND_SMS \
    WRITE_SMS \
    WRITE_SETTINGS \
    SYSTEM_ALERT_WINDOW \
    PACKAGE_USAGE_STATS; do
    cmd appops set com.android.bluetooth "$op" allow >> "$LOG" 2>&1 || true
  done

  bt_state="$(dumpsys bluetooth_manager 2>/dev/null | grep -m1 'state:' | sed 's/^ *//')"
  if [ -e /dev/stpbt ] && echo "$bt_state" | grep -q 'state: ON'; then
    echo "$(date) bluetooth already ON, not restarting" >> "$LOG"
  elif [ -e /dev/stpbt ]; then
    echo "$(date) starting bluetooth services, current=$bt_state" >> "$LOG"
    start bluetooth-1-0 >/dev/null 2>&1 || setprop ctl.start bluetooth-1-0
    sleep 3
    service call bluetooth_manager 6 >> "$LOG" 2>&1 || cmd bluetooth_manager enable >> "$LOG" 2>&1 || true
  else
    echo "$(date) /dev/stpbt missing, not restarting bluetooth" >> "$LOG"
  fi

  sleep 8
  if dumpsys bluetooth_manager 2>/dev/null | grep -q 'state: ON'; then
    am kill com.ecarx.btphone >> "$LOG" 2>&1 || true
  fi
  echo "$(date) final bt=$(dumpsys bluetooth_manager 2>/dev/null | grep -m1 'state:' | sed 's/^ *//') prop=$(getprop ro.ecarx.bt_ismtk) stpbt=$(ls /dev/stpbt 2>/dev/null)" >> "$LOG"
) &
