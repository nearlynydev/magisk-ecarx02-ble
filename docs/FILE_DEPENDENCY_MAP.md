# Bluetooth Module File Dependency Map

This document maps the module payload by call path, native dependency, and
current necessity. It reflects the current local module tree after the
2026-06-21 live tests.

Status legend:

- Required: needed by the currently confirmed A2DP/HFP/PBAP/BLE path.
- Likely required: required by dependency shape or boot path, but not yet
  isolated by a removal test.
- Candidate: can be tested for removal as a group.
- Cleanup: should not be shipped in release archives.
- Metadata: useful for repo/release hygiene, not loaded on the head unit.

## Runtime Flow

```text
Magisk
  -> customize.sh
       sets install-time permissions
  -> post-fs-data.sh
       resetprop ro.ecarx.bt_ismtk=true
       stops gocsdk early
  -> service.sh
       keeps gocsdk stopped
       waits for connsys
       loads /vendor/lib/modules/bt_drv.ko
       fixes /dev/stpbt permissions
       grants Bluetooth runtime permissions/appops
       resets stale -1 profile priorities to 100
       starts bluetooth-1-0 and enables Bluetooth

Android package manager
  -> system/app/Bluetooth/.replace
       replaces the stock Bluetooth app directory
  -> system/app/Bluetooth/Bluetooth.apk
       starts AdapterService, A2dpSinkService, HeadsetClientService,
       PbapClientService, AvrcpControllerService, OPP, GATT
  -> system/app/Bluetooth/lib/arm64/*
       app-local support libraries for the Bluetooth APK

Bluetooth native stack
  -> system/lib64/libmtkbluetooth_jni.so
       JNI bridge loaded by com.android.bluetooth
  -> system/lib64/libbluetooth-binder.so
       binder bridge used by JNI
  -> system/lib64/libbluetooth.so
       patched classic Bluetooth stack; creates local A2DP Sink SEPs
  -> system/lib64/libchrome.so
       Android 9 BT support library
  -> system/lib64/libbase.so
       dependency of libchrome
  -> android.hardware.bluetooth@1.0.so
  -> android.hardware.bluetooth.a2dp@1.0.so

Vendor Bluetooth HAL path
  -> system/vendor/etc/init/android.hardware.bluetooth@1.0-service-mediatek.rc
  -> system/vendor/bin/hw/android.hardware.bluetooth@1.0-service-mediatek
  -> system/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl-mediatek.so
  -> system/vendor/lib64/libbluetooth_mtk*.so / libbluetooth_relayer.so

Audio path
  -> system/vendor/lib/hw/audio.primary.ecarxp.so
       patched HFP call volume site; current live patch is:
       mov r4, r1, lsl #6
  -> system/lib64/hw/audio.a2dp.default.so
       donor A2DP HAL experiment
  -> system/lib64/android.hardware.audio*.so and libfmq/libprocessgroup
       support libraries for the donor audio HAL experiment
```

## Top-Level Files

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `.gitignore` | Metadata | Git/release hygiene | Excludes macOS metadata such as `.DS_Store` and `._*`. Keep. |
| `LICENSE` | Metadata | Repository users | MIT license for module glue/scripts/docs only. Keep. |
| `README.md` | Metadata | Humans/release notes | Primary runbook and current status. Keep. |
| `docs/FILE_DEPENDENCY_MAP.md` | Metadata | Humans | This dependency map. Keep while auditing payload. |
| `manifest.sha256` | Metadata | Release verification | Hash inventory for intended release payload. Keep updated after every file change. |
| `module.prop` | Required | Magisk | Module identity/version/description. Required for install. |
| `customize.sh` | Required | Magisk installer | Sets permissions on module tree and scripts. Required. |
| `post-fs-data.sh` | Required | Magisk boot stage | Selects MTK path before late userspace and stops `gocsdk`. Required for the current MTK/STP path. |
| `service.sh` | Required | Magisk late boot | Brings up STP/BT, grants permissions/appops, starts Bluetooth, keeps `gocsdk` stopped. Required. |
| `rollback.sh` | Required | Manual rollback and uninstall | Resets runtime state, clears imported Bluetooth contacts/call-log provider data, and disables the module. Keep. |
| `uninstall.sh` | Required | Magisk uninstall | Calls rollback during uninstall. Keep. |

## Bluetooth APK Directory

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `system/app/Bluetooth/.replace` | Required | Magisk overlay | Replaces stock `/system/app/Bluetooth` so stale stock files do not mix with the module payload. Required. |
| `system/app/Bluetooth/Bluetooth.apk` | Required | PackageManager / Bluetooth services | Patched APK. Enables sink-only A2DP, HFP Client audio request on active call, PBAP Client priority init, PBAP/HFP/AVRCP/GATT services. Required. |
| `system/app/Bluetooth/lib/arm64/libbase.so` | Required | App-local `libchrome.so` | Dependency of app-local `libchrome.so`. Contacts/PBAP recovered after app-local `libchrome/libbase` payload was added. Required until a live removal test proves otherwise. |
| `system/app/Bluetooth/lib/arm64/libchrome.so` | Required | APK native stack and app-local binder | Required by Bluetooth native pieces; earlier PBAP/AVRCP path needed this app-local copy. Required. |
| `system/app/Bluetooth/lib/arm64/libbluetooth-binder.so` | Likely required | `libmtkbluetooth_jni.so` if loaded app-locally or by namespace | Depends on `libchrome.so`; kept with app-local MTK library set. Test only with PBAP/HFP/A2DP regression coverage. |

Native dependency notes from ELF `DT_NEEDED`:

```text
libchrome.so -> libbase.so, libevent.so, libcutils.so
libbluetooth-binder.so -> libandroid_runtime.so, libbinder.so,
                          libchrome.so, libnativehelper.so
```

## Bluetooth Framework and Stack Libraries

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `system/lib64/libbluetooth.so` | Required | `com.android.bluetooth` native stack | Patched MTK stack. Fixes `bta_av_co_audio_init` so A2DP Sink local SEP registration happens. Required for current A2DP audio. |
| `system/lib64/libmtkbluetooth_jni.so` | Required | Bluetooth APK JNI | MTK JNI bridge; current stack was built around it. Required unless we fully move to a different JNI/library set. |
| `system/lib64/libbluetooth-binder.so` | Required | `libmtkbluetooth_jni.so` | JNI dependency. Required with current JNI. |
| `system/lib64/libchrome.so` | Required | `libbluetooth.so`, `libbluetooth-binder.so`, `audio.a2dp.default.so` | Global copy used by native stack/HAL namespace. Required for current stack. |
| `system/lib64/libbase.so` | Required | `libchrome.so`, `libfmq.so`, `libprocessgroup.so` | Global dependency. Required while global `libchrome` and donor HAL support files stay. |
| `system/lib64/android.hardware.bluetooth@1.0.so` | Required | `libbluetooth.so`, vendor BT service/impl | Bluetooth HAL interface library. Required. |
| `system/lib64/android.hardware.bluetooth.a2dp@1.0.so` | Required | `libbluetooth.so` | A2DP HAL interface dependency of patched stack. Required. |

Native dependency notes:

```text
libmtkbluetooth_jni.so -> libbluetooth-binder.so, libchrome.so
libbluetooth.so -> libchrome.so,
                   android.hardware.bluetooth@1.0.so,
                   android.hardware.bluetooth.a2dp@1.0.so,
                   libaudioclient.so, libprotobuf-cpp-lite.so,
                   libtinyxml2.so, keymaster/keystore libs
```

## Bluetooth Configuration and Permissions

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `system/etc/bluetooth/bt_stack.conf` | Likely required | AOSP/BT stack config lookup | Conservative BT stack trace/config file. Keep until confirmed unused by live stack. |
| `system/etc/bluetooth/mtk_bt_stack.conf` | Required | MTK BT stack config | Enables verbose MTK traces and HCI snoop settings. Useful for live debugging and MTK path. |
| `system/etc/bluetooth/mtk_bt_fw.conf` | Likely required | MTK firmware logging/config | Firmware log control for donor MTK path. Keep unless HAL runs without it in slim test. |
| `system/etc/permissions/privapp-permissions-ecarx-e02-bluetooth.xml` | Required | PackageManager permission grant | Grants privileged permissions requested by patched Bluetooth APK. Required. |
| `system/etc/sysconfig/hiddenapi-package-whitelist.xml` | Likely required | Framework hidden API policy | Adds `com.android.bluetooth` to hidden API whitelist because APK is patched/deodexed. Keep unless platform-signature exemption is proven sufficient. |
| `system/etc/a2dp_audio_policy_configuration.xml` | Candidate | Audio policy include path | Donor A2DP policy config in system path. Current confirmed playback may not require both system and vendor copies; test as part of audio-policy slim group. |
| `system/vendor/etc/a2dp_audio_policy_configuration.xml` | Candidate | Vendor audio policy include path | Vendor copy of donor A2DP policy config. Test together with system copy/audio HAL group. |
| `system/vendor/etc/permissions/android.hardware.bluetooth.xml` | Likely required | Framework feature declaration | Declares classic Bluetooth feature. Low risk, keep. |
| `system/vendor/etc/permissions/android.hardware.bluetooth_le.xml` | Likely required | Framework feature declaration | Declares BLE feature; HWGPS BLE depends on BLE feature path. Keep. |

## Vendor Bluetooth HAL Files

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `system/vendor/etc/init/android.hardware.bluetooth@1.0-service-mediatek.rc` | Required | init/service.sh | Defines `bluetooth-1-0` service started by `service.sh`. Required if donor HAL service is used. |
| `system/vendor/bin/hw/android.hardware.bluetooth@1.0-service-mediatek` | Required | `bluetooth-1-0` init service | MTK Bluetooth HAL service binary. Required for current MTK/STP path. |
| `system/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl-mediatek.so` | Required | HAL service | Implementation loaded by service. Required. |
| `system/vendor/lib64/libbluetooth_mtk.so` | Likely required | MTK vendor BT implementation | Depends on `libnvram`; likely part of HAL transport. Keep. |
| `system/vendor/lib64/libbluetooth_mtk_pure.so` | Candidate | MTK vendor BT variants | Similar dependency shape to `libbluetooth_mtk.so`; may be unused. Test only as vendor-HAL group. |
| `system/vendor/lib64/libbluetooth_relayer.so` | Likely required | MTK relayer path | Depends on `libbluetoothem_mtk.so`; keep until HAL symbol/load audit or live removal test. |
| `system/vendor/lib64/libbluetoothem_mtk.so` | Likely required | `libbluetooth_relayer.so` | Relayer dependency. Keep if relayer stays. |
| `system/vendor/lib64/libbluetooth_hw_test.so` | Candidate | Factory/test tooling | No observed live dependency except possible vendor diagnostics. Candidate for removal after a BT boot test. |

Vendor HAL dependency notes:

```text
android.hardware.bluetooth@1.0-service-mediatek
  -> android.hardware.bluetooth@1.0.so
  -> libbase.so, libcutils.so, libhardware.so, libhidlbase.so,
     libhidltransport.so, libutils.so

android.hardware.bluetooth@1.0-impl-mediatek.so
  -> android.hardware.bluetooth@1.0.so
  -> libbase.so, libcutils.so, libhardware.so, libhidlbase.so,
     libhidltransport.so, libutils.so

libbluetooth_relayer.so -> libbluetoothem_mtk.so
```

## Audio Files

| File | Status | Used by | Why it exists / notes |
| --- | --- | --- | --- |
| `system/vendor/lib/hw/audio.primary.ecarxp.so` | Required | Android audio HAL | Patched HFP call volume path. Current patch is dynamic `mov r4, r1, lsl #6`; keeps button-controlled volume behavior. Required for current HFP audio experiment. |
| `system/lib64/hw/audio.a2dp.default.so` | Candidate | Donor A2DP HAL experiment | Depends on `libchrome.so`; current A2DP Sink audio is confirmed, but this file came from broader donor HAL experiment. Test as audio-HAL group. |
| `system/lib64/android.hardware.audio@2.0.so` | Candidate | Audio HAL interface dependency | Donor audio HAL support. Test as group with `audio.a2dp.default.so`. |
| `system/lib64/android.hardware.audio.common@2.0.so` | Candidate | Audio HAL interface dependency | Donor audio HAL support. Test as group. |
| `system/lib64/android.hardware.audio.common@2.0-util.so` | Candidate | Audio HAL interface dependency | Donor audio HAL support. Test as group. |
| `system/lib64/android.hardware.audio.effect@2.0.so` | Candidate | Audio HAL interface dependency | Donor audio HAL support. Test as group. |
| `system/lib64/libfmq.so` | Candidate | HIDL/FMQueue support | Dependency of donor HAL support. Test as group. |
| `system/lib64/libprocessgroup.so` | Candidate | Donor support library | Depends on `libbase.so`. Test as group. |

Audio dependency notes:

```text
audio.a2dp.default.so -> libchrome.so, libcutils.so
audio.primary.ecarxp.so -> many stock/vendor audio libs:
  libtinyalsa.so, libtinycompress.so, libaudioutils.so,
  libaudiocustparam_vendor.so, libaudiocomponentengine_vendor.so,
  android.hardware.automotive.audiocontrol@1.1.so, etc.
```

## Release Cleanup Files

These files must not be shipped. The current module tree has been cleaned of
`.DS_Store` and `._*` files; keep it that way before every release build.

| File pattern | Status | Why |
| --- | --- | --- |
| `.git/**` | Cleanup | Local repo metadata. Never include in Magisk release ZIP. |
| `.DS_Store` | Cleanup | macOS metadata. It is not in `manifest.sha256`; remove before release if it reappears. |
| `._*` | Cleanup | AppleDouble files are dangerous in Android app directories. A previous `._Bluetooth.apk` caused PackageManager to reject `/system/app/Bluetooth`. Remove before release if any reappear. |

Packaging rule:

```sh
COPYFILE_DISABLE=1 zip -r ...
```

or an equivalent command that excludes `.git`, `.DS_Store`, and `._*`.

## Removal Test Order

Do not remove files individually from the proven payload without a live test.
Suggested slim-down order:

1. Keep cleanup files out of release archives: `.git`, `.DS_Store`, `._*`.
2. Test `libbluetooth_hw_test.so` removal.
3. Test donor audio HAL group removal:
   `audio.a2dp.default.so`, `android.hardware.audio*.so`, `libfmq.so`,
   `libprocessgroup.so`, and duplicate A2DP policy XMLs.
4. Test global duplicate `libchrome.so`, `libbase.so`,
   `libbluetooth-binder.so` only after confirming app-local copies satisfy
   PBAP/AVRCP and native namespace loading.
5. Test vendor BT variant libraries only as a group and only with logs from
   `bluetooth-1-0` startup.

Minimum regression suite after each removal:

- Bluetooth boots ON, no `com.android.bluetooth` crash.
- A2DP media connects and plays.
- HFP call reaches `AudioOn`; volume buttons affect call volume.
- PBAP contacts sync; call-log provider rows are populated.
- BLE/HWGPS still registers and connects.
