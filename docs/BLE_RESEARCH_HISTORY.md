# Bluetooth/BLE Research History

This document summarizes the Bluetooth/BLE research that led to the current
Magisk module for ECARX E02 / IHU717P based Geely and Knewstar head units. It
focuses on what was tested, why it was tested, how patches were made, which
tools were used, and what is currently known.

The initial problem was that the head unit exposed only the classic Bluetooth
phone/media feature set expected by the original vehicle software, while many
modern external devices and integrations use Bluetooth Low Energy instead of
Classic Bluetooth. The HWGPS module was one of those BLE devices: it connected
over GATT rather than through the legacy phone/audio profiles. Because of that,
we had to investigate not only one application-level connection but the whole
Bluetooth service boundary on the head unit.

The word "BLE" is used here in the project sense: the original driver was the
HWGPS BLE/GATT integration, but the work quickly expanded into the surrounding
Android Bluetooth stack because the same head-unit Bluetooth service boundary is
shared by GATT, PBAP, HFP Client, A2DP Sink, and AVRCP Controller.

## Executive Summary

The original question was whether an Android phone and a BLE HWGPS module could
be observed and integrated through the ECARX head unit. The head unit had a
stock ECARX/GOC Bluetooth path and a dormant or incomplete MTK/STP path. We
eventually moved the active experiment to an MTK Android 9 Bluetooth userspace
stack, packaged as a Magisk module.

The current result is:

- BLE/GATT can coexist with the patched Bluetooth stack. The HWGPS application
  package is `org.astpepper.hwgps`; live dumps showed it as a GATT client.
- A2DP Sink is working in live testing. Music plays through the head unit with
  usable volume.
- HFP Client connects and reaches call audio state. HFP volume was tuned through
  the ECARX audio HAL and remains the most sensitive audio area.
- PBAP contacts and call-log provider rows have worked after restoring the
  app-local MTK `libchrome.so` / `libbase.so` dependency set. Favorites and UI
  call-log display still need follow-up.
- The module intentionally keeps `gocsdk` stopped. It should not be re-enabled
  unless a later test proves that a specific ECARX/GOC path is needed.

## Target Environment

- Head unit: ECARX E02 / IHU717P family.
- Vehicle families discussed in this work: Geely / Knewstar.
- Android version on the head unit: Android 9.
- Root path: Magisk.
- Main live transport:
  - SSH to `root@172.20.10.11` when available.
  - ADB over `172.20.10.11:5555` for earlier tests and when explicitly useful.
- Reboot handling:
  - SSH can hang during reboot; do not wait on a dead SSH command.
  - Poll ports `22` and `5555` after reboot.
- Module repository:
  - `work/magisk_modules/ecarx_e02_ihu717p_bt`
  - GitHub remote: `git@github.com:nearlynydev/magisk-ecarx02-ble.git`

## Research Artifacts

Important local artifacts used during the work:

- `work/analysis/libGbtsDriver_summary_20260611.md`
- `work/analysis/libGbtsTask_scheduler_tasks.md`
- `work/analysis/stock_classic_bluetooth_hfp_path_20260612.md`
- `work/analysis/cubot_x20pro_v07_bluetooth_live_20260612.md`
- `work/ble_lib_compare/*`
- `work/tmp_cubot_deodex/*`
- `work/tmp_nearlynyble_bt/*`
- `work/logs/live_a2dp_*`
- `work/logs/a2dp_*`
- `work/logs/hwgps_*`
- Current module payload and dependency map:
  - `docs/FILE_DEPENDENCY_MAP.md`
  - `manifest.sha256`

## Tooling

The work used a mixed Android reverse-engineering and live-device toolchain:

- Device access:
  - `ssh`
  - `adb`
  - `su -mm`
  - `logcat`
  - `dumpsys bluetooth_manager`
  - `dumpsys audio`
  - `cmd package`, `pm`, `cmd appops`, `settings`
  - `sqlite3` for contacts/call-log provider databases
- APK work:
  - `apktool`
  - `jadx`
  - `vdexExtractor`
  - `compact_dex_converter`
  - `zipalign`
  - `apksigner` / `jarsigner`
  - AOSP/platform signing keys for the module APK builds
- Native reverse engineering:
  - `llvm-objdump`
  - `objdump`
  - `readelf`
  - `nm`
  - Capstone-based Python scripts
  - `rizin` for selected disassembly checks
  - `strings`, `rg`, `shasum`
- Runtime probing and patch support:
  - custom Python patch scripts under `work/tools`
  - temporary `LD_PRELOAD` probe sources under `work/tools`
  - Frida helper `work/tools/frida/force_a2dpsink_connect.js`
- Packaging and release:
  - Magisk module layout
  - `zip -r9 -X` with `COPYFILE_DISABLE=1`
  - `gh` GitHub CLI
  - `manifest.sha256` verification

## Chronology

### 2026-06-06: HWGPS application and BLE UI reconnaissance

The early BLE work focused on `org.astpepper.hwgps`. UI dumps and live logs
were collected to understand how the application exposes connection settings,
server settings, tracker state, and BLE-related screens.

Representative artifacts:

- `work/logs/hwgps_discoverthread_test_20260606_170946.log`
- `work/logs/hwgps_v31_vdex06_live_ui_20260608_182328.xml`

This stage established that the HWGPS side was an Android application using the
normal Android app surface, while the difficult part was the underlying
head-unit Bluetooth stack.

### 2026-06-08 to 2026-06-10: BLE callback and VDEX/JNI patch exploration

We explored whether the stock stack could be patched narrowly enough to make the
HWGPS BLE path work without replacing the whole Bluetooth service. Several
patch scripts were created under `work/tools`, including:

- `patch_bluetooth_vdex_system_ble_variants.py`
- `patch_bluetooth_vdex_v07_phyread.py`
- `patch_bluetooth_vdex_v08_phy_mtu.py`
- `patch_bluetooth_vdex_v09_phyread_mtu_setphy_noop.py`
- `patch_bluetooth_vdex_v10_discover_read_write_callbacks.py`
- `patch_bluetooth_vdex_onsearch_sync_getdb.py`
- `patch_libbluetooth_jni_char_read_bridge.py`
- `patch_libbluetooth_jni_v31_dispatch_blefix_db*.py`
- `patch_libbluetooth_jni_getdb_*`

The purpose was to trace and repair callback delivery around GATT database
discovery, characteristic reads, descriptor reads, writes, PHY/MTU calls, and
thread/attach behavior. These patches were exploratory; they helped map the
failure area but did not become the final module architecture.

### 2026-06-11: ECARX/GOC stack reverse engineering

We mapped the stock GOC/GBTS Bluetooth implementation. The key native files
were `libGbtsDriver.so` and `libGbtsTask.so`.

Findings from `libGbtsDriver.so`:

- It is a 32-bit ARM library with many dynamic symbols.
- It contains Goodocom authentication/licensing/database code.
- It contains UART/transport code for H4/BCSP paths.
- It contains vendor patch/init code for Broadcom, Qualcomm, Realtek, and MTK.
- It contains an MTK path with strings pointing to
  `libbluetooth_mtk/mtk.c` and `goc_thread_mtk`.
- It has Goodocom server/license strings and serial-number probing paths.

Important implication:

The stock ECARX/GOC stack is not a clean AOSP Bluetooth stack. It combines a
GOC control path, vendor UART/HCI transport, license checks, and multiple vendor
support paths. This made a small, confident BLE-only patch risky.

Findings from `libGbtsTask.so` scheduler mapping:

- BLE-related task registrations were identified:
  - `CSR_BT_ATT`
  - `CSR_BT_GATT`
  - `CSR_BT_APP_LE_BROWSER`
  - `CSR_BT_APP_GAP`
- `LD_PRELOAD` wrappers for obvious init functions did not catch the internal
  registrations.
- The next reliable probe would have been either a scheduler-table dump after
  `CsrSchedInit` or direct patch/logging near the call sites.

This pushed us toward trying a more standard Android/MTK userspace Bluetooth
stack instead of continuing with GOC internals first.

### 2026-06-12: Stock Classic Bluetooth and HFP path analysis

We deodexed and inspected the stock phone UI `NSBTPhone.apk`.

Important classes:

- `UiCallManager`
- `InCallPresenter`
- `CarAmpManager`

Important API usage:

- `BluetoothHeadsetClient.getConnectedDevices()`
- `BluetoothHeadsetClient.getCurrentCalls(device)`
- `BluetoothHeadsetClient.connectAudio(device)`
- `BluetoothHeadsetClient.disconnectAudio(device)`
- `BluetoothHeadsetClient.getAudioState(device)`

The stock UI uses the Android `BluetoothHeadsetClient` API surface, but the
native implementation below it is ECARX/GOC-specific. The stock
`/system/lib64/libbluetooth_jni.so` contains GOC HFP-client symbols and AT
command strings.

This analysis gave us a decision tree for later HFP debugging:

1. If the UI never calls `connectAudio()`, inspect call-list reporting and
   `getCurrentCalls()`.
2. If `connectAudio()` is called but `mAudioState` remains `0`, inspect native
   HFP/SCO.
3. If `mAudioState` becomes `2` but no sound reaches the speakers, inspect car
   audio routing, Bose amp mode, and the audio HAL.

### 2026-06-12: Cubot Android 9 MTK Bluetooth transplant

We tested an Android 9 MTK Bluetooth userspace donor from Cubot X20 Pro V07.
The live target was the IHU717P at `172.20.10.11:5555`.

Initial candidate:

- `work/ble_patch/full_transplant_candidates/03_cubot_x20pro_v07_minimal_bt`

Files transplanted in the early candidate:

- `Bluetooth.apk` / `MtkBluetooth.apk`
- `libmtkbluetooth_jni.so`
- `libbluetooth.so`
- `libbluetooth-binder.so`
- `libchrome.so`
- `libbase.so`
- `mtk_bt_stack.conf`
- `mtk_bt_fw.conf`
- app-local native libraries under `lib/arm64`

First failure:

- The donor APK was odex-only.
- The head unit failed with `ClassNotFoundException` for
  `com.android.bluetooth.btservice.AdapterApp`.
- ART reported that no original dex files were available for the APK.

Second failure:

- Copying donor `MtkBluetooth.odex` / `MtkBluetooth.vdex` did not work on the
  IHU.
- The preopt files were likely tied to the donor boot classpath/framework image.

Deodex approach:

- Extract CompactDex from donor VDEX with `vdexExtractor`.
- Convert CompactDex on the head unit using `compact_dex_converter`.
- Rebuild the APK with embedded `classes.dex`.
- Align and sign the rebuilt APK.
- Remove donor oat files so ART used the embedded dex.

Next failure:

- Re-signing changed the certificate.
- The Bluetooth app lost some signature/privileged permissions.
- A crash appeared around `BluetoothOppFileProvider` and
  `INTERACT_ACROSS_USERS_FULL`.

Mitigations:

- Added a `privapp-permissions` XML for `com.android.bluetooth`.
- Tried a diagnostic edit of `/data/system/packages.xml`; PackageManager
  recalculated and ignored the manual grants.

Conclusion:

The donor MTK stack was viable, but it needed to be packaged carefully at the
stock app path with the right permissions and signing assumptions. This became
the basis for the Magisk module.

### 2026-06-12 to 2026-06-14: Stock-path PBAP bridge modules

Several temporary Magisk/TAR/ZIP candidates were built to find a usable
packaging shape:

- `ecarx_bt_mtk_cubot_stockpath_pbapbridge_20260612_no_libchrome.zip`
- `ecarx_bt_mtk_cubot_stockpath_pbapbridge_20260613_symlinks.zip`
- `ecarx_bt_mtk_cubot_stockpath_pbapbridge_20260613_symlinks_profile_perms.zip`
- `ecarx_bt_knewstar_stockpath_pbapbridge_20260614_symlinks_profile_perms.zip`

The important lessons were:

- The module must replace the stock `/system/app/Bluetooth` directory cleanly.
- App-local native libraries matter for the Bluetooth APK namespace.
- PBAP/AVRCP behavior changed when `libchrome.so` and `libbase.so` were present
  in the expected places.
- The module needed runtime grants/appops in addition to static privapp XML.

### 2026-06-16: First publishable Magisk module

The work was consolidated into:

- `work/magisk_modules/ecarx_e02_ihu717p_bt`

Initial release hygiene was added:

- `LICENSE`
- README disclaimer
- `manifest.sha256`
- GitHub CLI release flow
- version `2026.06.16`

The module was explicitly documented as systemless: it overlays files through
Magisk instead of physically rewriting `/system`.

### 2026-06-17: Rollback support and release refresh

Rollback was added because the module changes runtime state, not only file
overlays.

Rollback behavior:

- Set `ro.ecarx.bt_ismtk=false` for the current boot.
- Revoke or reset Bluetooth runtime grants/appops where possible.
- Stop Bluetooth-related processes.
- Create the Magisk module `disable` marker.
- Write rollback logs.

`uninstall.sh` was updated to delegate to `rollback.sh` when available.

The release was refreshed as `v2026.06.17`.

### 2026-06-20: A2DP Sink investigation

The A2DP problem became the main blocker. The phone could pair, but media audio
was not working correctly.

Tests and observations:

- We captured `dumpsys bluetooth_manager` before and after connection attempts.
- We captured focused logcat extracts around A2DP, AVRCP, BTIF, and native
  stack logs.
- We tested with `gocsdk` stopped. The same A2DP blocker remained, which showed
  that `gocsdk` was not the immediate A2DP failure cause.
- We tested profile-resource variants:
  - dual A2DP Source + Sink
  - sink-only
  - AVRCP-enabled and AVRCP-reduced variants

Important early symptom:

- `A2DP Sink State: Enabled`
- `A2DP Source State: Enabled` or later source disabled, depending on APK build
- Local sink SEP entries had `SEP AVDTP handle: 0`
- The source side showed registered SEPs, while the sink side had zero usable
  local endpoints.

Native reverse engineering:

- We compared the binary to Android 9 AOSP `bta_av_api_register`.
- We used `strings`, section mapping, `llvm-objdump`, and Capstone scripts.
- We found MTK-custom logging around `bta_av_co_audio_init`, including the
  repeated source-only path text.

Conclusion:

The MTK customization matched codecs from an ordered source list but did not
initialize sink codec indexes correctly. For sink indexes the init callback
returned false, so `AVDT_CreateStream()` was never called for local A2DP Sink
SEPs.

Patch:

- Patch `system/lib64/libbluetooth.so` around `bta_av_co_audio_init`.
- Force the local A2DP Sink codec registration path to continue far enough to
  create nonzero local sink SEPs.

Result:

- Local AVDTP sink handles became nonzero in live `dumpsys`.
- A2DP opened and started.
- Logs showed a selected sink codec, including `Current Codec: AAC SINK`.

Second A2DP failure:

- After the SEP/native patch, A2DP packets and decoding started, but the head
  unit was silent.
- Native logs showed frames being skipped because audio focus was not present.

Patch:

- Patch the Bluetooth APK A2DP Sink path so it requests Android audio focus when
  the incoming stream starts.
- Build signed APK variants:
  - `nearlynyble-bluetooth-sinkonly-audiofocus.platform.apk`
  - `nearlynyble-bluetooth-sinkonly-focusrequest.platform.apk`

Result:

- A2DP media became audible through the head unit.
- Live user validation confirmed that music played and volume was good.

### 2026-06-21: HFP call audio and volume work

After A2DP media became audible, HFP calls were still problematic.

Observed symptoms:

- Calls could connect.
- The phone saw an audio device.
- At first the call path could be silent or very quiet.
- Later patches could make it too loud.
- Some fixed-gain patches made volume buttons ineffective.

Java-side HFP patch:

- Inspect `NSBTPhone` and the MTK Bluetooth APK behavior.
- Identify that a call could become `ACTIVE` while HFP Client audio remained
  disconnected.
- Patch `HfpClientConnection.updateCall()` so it calls
  `BluetoothHeadsetClient.connectAudio(device)` when a call becomes `ACTIVE`
  and HFP audio is idle.

Live result:

- `dumpsys bluetooth_manager` moved from `mAudioState: 0` / connected to
  `mAudioState: 2` / `AudioOn`.

Audio HAL volume tuning:

- The ECARX audio HAL file is:
  - `system/vendor/lib/hw/audio.primary.ecarxp.so`
- Multiple temporary 32-bit HAL patch variants were produced under
  `work/tmp_nearlynyble_bt/audio_hal32/`, including:
  - fixed multipliers
  - `lsl #8`
  - `lsl #6`
  - fixed `0x1000`
  - set-volume variants

Important results:

- Fixed `0x1000` was loud and did not respond correctly to volume changes.
- Old dynamic `lsl #8` was too loud.
- The retained patch is dynamic:
  - `mov r4, r1, lsl #6`
- This keeps the call path tied to the incoming volume value instead of using a
  fixed gain.

Current HFP status:

- HFP Client reaches audio-on state.
- Call volume is usable enough for the current release, but exact subjective
  tuning remains sensitive and should be revisited only with live car testing.

### 2026-06-21: PBAP contact and call-log work

PBAP regressed several times while we were adjusting the Bluetooth APK.

Observed symptoms:

- The phone sometimes did not show the contact-sync setting.
- The head unit reported sync failure.
- Contacts had previously worked after adding `libchrome.so` and `libbase.so`.

Fix direction:

- Restore and keep the app-local MTK support libraries:
  - `system/app/Bluetooth/lib/arm64/libchrome.so`
  - `system/app/Bluetooth/lib/arm64/libbase.so`
  - `system/app/Bluetooth/lib/arm64/libbluetooth-binder.so`
- Keep global native copies where the stack/HAL namespace still needs them.
- Avoid broad PBAP autoconnect patches that caused regressions.

APK variants tested:

- `nearlynyble-bluetooth-pbap-auto.platform.apk`
- `nearlynyble-bluetooth-pbap-auto-keeplog.platform.apk`
- `nearlynyble-bluetooth-pbap-force-priority.platform.apk`
- `nearlynyble-bluetooth-pbap-priority-only.platform.apk`
- `nearlynyble-bluetooth-pbap-priority-only-v2.platform.apk`

Retained approach:

- Keep the APK narrow.
- Set PBAP Client priority to `100` during profile-priority initialization.
- Do not force a wider PBAP autoconnect / keep-call-log patch in the current
  release, because the wider patch broke contact sync.

Live result:

- After reboot, PBAP connected and Android providers were populated:
  - 325 contacts
  - 300 call-log rows
- Favorites still were not imported.
- UI call-log display may still fail because provider rows use numeric
  `subscription_id`, while `NSBTPhone` had previously been seen querying by the
  phone MAC string.

### 2026-06-21: Module cleanup and dependency map

We audited the module tree because the payload had grown during live debugging.

Actions:

- Removed duplicate `system/lib64/vndk-28`.
- Removed macOS `.DS_Store` files.
- Removed AppleDouble `._*` files.
- Documented why AppleDouble files are dangerous in Android app directories:
  a previous `._Bluetooth.apk` caused PackageManager to reject the whole
  `/system/app/Bluetooth` directory.
- Added `docs/FILE_DEPENDENCY_MAP.md`.

The dependency map classifies payload files as:

- Required
- Likely required
- Candidate
- Cleanup
- Metadata

It also defines a removal-test order and minimum regression suite.

### 2026-06-21: Release v2026.06.21

The current work was released as:

- Tag: `v2026.06.21`
- ZIP: `ecarx_e02_ihu717p_bt_v2026.06.21.zip`
- ZIP SHA-256:
  `8808a45e70c13eea513e66a7bdaebb8073a9aa47292c9c5676c2f8dc16438349`

Release preparation:

- Updated `module.prop` to `2026.06.21`.
- Recomputed `manifest.sha256`.
- Built the ZIP with `COPYFILE_DISABLE=1` and `zip -r9 -X`.
- Verified the extracted ZIP with `shasum -a 256 -c manifest.sha256`.
- Published through `gh release create`.
- Removed older GitHub releases and tags.

## Patch Inventory

### Bluetooth APK

Current APK hash in the module:

```text
0ad9772bf72b32e00b64f1c029b2f5adcdf0063a5fa25285a327d7cd9afdfee5
```

Functional changes accumulated into the current APK:

- Enable car/head-unit profile set:
  - A2DP Sink
  - HFP Client
  - PBAP Client
  - AVRCP Controller
  - GATT/BLE service paths
- Keep the build sink-only for A2DP to avoid source/sink role confusion.
- Request audio focus for incoming A2DP Sink playback.
- Request HFP Client audio when a call becomes active and audio is still idle.
- Initialize PBAP Client priority to `100` without forcing broad PBAP
  autoconnect logic.
- Keep the receiver/current-user patch needed by the deodexed donor APK path.

### Native Bluetooth stack

Current `libbluetooth.so` role:

- MTK Android 9 Bluetooth stack library.
- Patched around the A2DP Sink local SEP registration failure.
- Required for current A2DP Sink operation.

Main patch concept:

- The MTK `bta_av_co_audio_init` customization initialized source codec indexes
  but skipped sink codec indexes.
- The patch makes sink registration continue so `AVDT_CreateStream()` is called
  and local sink SEPs receive usable handles.

### HFP audio HAL

Current HAL file:

```text
system/vendor/lib/hw/audio.primary.ecarxp.so
```

Current hash:

```text
141a85ad3a972221ae9f477849c84cc97db311f12af4f46b9d7267977d55ace2
```

Current retained volume patch:

```text
mov r4, r1, lsl #6
```

Reason:

- Fixed gain made the call path too loud and broke useful volume control.
- `lsl #8` was too loud.
- `lsl #6` kept a dynamic relationship to the requested volume while producing
  a more usable level in live tests.

### Boot scripts

`post-fs-data.sh`:

- Sets `ro.ecarx.bt_ismtk=true`.
- Stops `gocsdk` early.

`service.sh`:

- Keeps `gocsdk` stopped.
- Waits for `vendor.connsys.driver.ready`.
- Loads `/vendor/lib/modules/bt_drv.ko`.
- Fixes `/dev/stpbt` owner/mode.
- Grants runtime permissions and appops to `com.android.bluetooth`.
- Resets stale negative Bluetooth profile priorities.
- Starts Bluetooth.

`rollback.sh`:

- Reverts runtime state as far as possible.
- Creates the Magisk disable marker.
- Leaves the real system partitions untouched because the module is systemless.

## Test Methods

### Boot and package tests

Typical checks:

```sh
pm path com.android.bluetooth
dumpsys package com.android.bluetooth
dumpsys bluetooth_manager
logcat -d -v time | grep -i -E 'Bluetooth|btif|A2DP|PBAP|HeadsetClient|GATT'
```

Expected:

- `com.android.bluetooth` resolves to `/system/app/Bluetooth/Bluetooth.apk`.
- Bluetooth reaches ON.
- No repeated `com.android.bluetooth` crash loop.

### BLE/HWGPS checks

Typical checks:

```sh
dumpsys bluetooth_manager | grep -i -E 'gatt|org.astpepper|hwgps'
logcat -d -v time | grep -i -E 'org.astpepper|hwgps|gatt|ble'
```

Expected:

- `org.astpepper.hwgps` appears as a GATT client when HWGPS is active.
- GATT registration and BLE connection survive Classic Bluetooth changes.

### A2DP checks

Typical checks:

```sh
dumpsys bluetooth_manager | sed -n '/A2DP Source State/,+120p'
logcat -d -v time | grep -i -E 'A2dpSink|BTA_AV|AVDT|Current Codec|focus|AudioTrack'
```

Decision points:

- Zero sink SEP handles: native `libbluetooth.so` registration problem.
- AVDTP open/start succeeds but silence remains: audio focus or audio routing.
- Decoder logs frame skipping due to missing focus: Java-side audio focus patch.

### HFP checks

Typical checks during an active call:

```sh
dumpsys bluetooth_manager | sed -n '/HeadsetClientService/,+80p'
logcat -d -v time | grep -i -E 'HeadsetClient|HfpClient|connectAudio|AudioOn|SCO|CURRENT_CALLS'
dumpsys audio | grep -i -E 'mode|sco|voice|bluetooth|route|device'
```

Decision points:

- Call active but `mAudioState: 0`: Java/native HFP audio request problem.
- `mAudioState: 2` but silence: audio HAL / mixer / vehicle route problem.
- Volume fixed and buttons ineffective: avoid fixed-gain HAL patch.

### PBAP checks

Typical checks:

```sh
dumpsys bluetooth_manager | grep -i -E 'pbap|phonebook|profile'
logcat -d -v time | grep -i -E 'PBAP|Pbap|Phonebook|contacts|calllog'
sqlite3 contacts2.db 'select count(*) from raw_contacts;'
sqlite3 calllog.db 'select count(*) from calls;'
```

Expected in the current known-good state:

- Contacts provider rows appear.
- Call-log provider rows appear.
- Favorites are not yet imported.
- UI call-log display may need a separate NSBTPhone-side patch.

## Donor Firmware Findings

Oukitel C21 V08:

- Contains Bluetooth Audio HAL 2.0 pieces:
  - `android.hardware.bluetooth.audio@2.0.so`
  - `android.hardware.bluetooth.audio@2.0-impl-mediatek.so`
  - `libbluetooth_audio_session_mediatek.so`
- Rejected as a poor donor for this module because it is Android 10 / VNDK 29,
  while the head unit is Android 9 / VNDK 28.

Android 9 MTK donor family:

- Better ABI/VNDK match for the head unit.
- Did not provide Bluetooth Audio HAL 2.0.
- Provided useful Android 9 Bluetooth stack, HAL 1.0, APK, `libchrome.so`,
  `libbase.so`, and MTK config files.

## Current Module State

Version:

```text
2026.06.21
```

Main payload paths:

- `system/app/Bluetooth/Bluetooth.apk`
- `system/app/Bluetooth/lib/arm64/libchrome.so`
- `system/app/Bluetooth/lib/arm64/libbase.so`
- `system/app/Bluetooth/lib/arm64/libbluetooth-binder.so`
- `system/lib64/libbluetooth.so`
- `system/lib64/libmtkbluetooth_jni.so`
- `system/vendor/bin/hw/android.hardware.bluetooth@1.0-service-mediatek`
- `system/vendor/lib64/hw/android.hardware.bluetooth@1.0-impl-mediatek.so`
- `system/vendor/lib/hw/audio.primary.ecarxp.so`
- `post-fs-data.sh`
- `service.sh`
- `rollback.sh`

Runtime policy:

- Keep `gocsdk` disabled.
- Keep `inputservice` disabled as previously decided.
- Do not remove additional files without live regression testing.

## Known Open Items

- BLE/HWGPS:
  - Continue checking that HWGPS GATT survives every Classic Bluetooth stack
    change.
  - Capture a clean BLE session log with the final v2026.06.21 payload.
- A2DP:
  - Verify AVRCP metadata.
  - Verify play/pause/next/previous from the vehicle UI.
  - Verify reconnect/resume behavior.
  - Verify ducking/priority with radio and navigation prompts.
- HFP:
  - Validate microphone capture.
  - Validate answer/reject/hangup from the vehicle UI.
  - Re-check call volume only with live car audio available.
- PBAP:
  - Confirm pairing-time phone prompt for contacts/call history.
  - Import or display favorites.
  - Resolve UI call-log display if `NSBTPhone` expects a MAC string while
    provider rows use numeric `subscription_id`.
- Payload cleanup:
  - Test whether donor audio HAL support files are still needed.
  - Test whether vendor Bluetooth diagnostic libraries can be removed.
  - Keep `.DS_Store`, `._*`, `__MACOSX`, and `.git` out of release ZIP files.

## Lessons Learned

- A BLE-only fix was not enough because the stock ECARX/GOC stack hides BLE,
  Classic Bluetooth, HFP, PBAP, and vendor transport behind the same service
  boundary.
- Donor odex/vdex artifacts are not portable by themselves. Deodexing was
  required.
- Re-signing a privileged system APK can break signature permissions unless the
  package path, permissions, and framework policy are handled together.
- App-local native libraries matter. The PBAP/AVRCP path regressed when
  `libchrome.so` / `libbase.so` were missing from the Bluetooth app namespace.
- `gocsdk` can interfere with Classic Bluetooth ownership, but stopping it did
  not by itself solve A2DP. It should remain disabled for the MTK/STP path.
- `dumpsys bluetooth_manager` was one of the most valuable tools: it exposed
  profile state, local AVDTP handles, HFP audio state, and GATT clients.
- A2DP had two separate blockers:
  - no local sink SEPs in the native stack;
  - missing Java-side audio focus after SEPs were fixed.
- HFP had two separate layers:
  - Java-side call-audio activation;
  - ECARX audio HAL gain/routing.
- macOS AppleDouble files are not harmless in Android app directories. A
  `._Bluetooth.apk` file can make PackageManager reject the whole app directory.
