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

### 2026-06-30: iPhone PBAP, Class of Device, and auto-sync chain

A live iPhone exposed three regressions versus the legacy GOC stack: no
"Sync Contacts" prompt at pairing, contact sync hanging, and the call log
never importing. These were resolved as one chain and released as
`v2026.06.30`.

Class of Device (contacts prompt):

- The head unit advertised a smartphone CoD (`0x5a020c`), so iOS treated it
  as a phone and never offered phonebook sync.
- A rodata patch in `libbluetooth.so` and a `DevClass` edit in
  `bt_config.conf` both had no runtime effect.
- Root cause: AOSP `AdapterService.setBluetoothClassFromConfig()` reads the
  CoD from `Settings.Global bluetooth_class_of_device`, overriding the
  config. Writing `2360352` (`0x240420`, Audio/Video / Car audio) made the
  live CoD change to `240420` and the iPhone began offering contacts sync.
  This is now done in `service.sh` on every boot.

Auto-connect and auto-sync (sync no longer needs a manual button):

- `PbapClientService` registers for `ACL_CONNECTED`; the receiver
  auto-calls `connect(device)` so PBAP attaches as soon as the phone links.
- `PbapClientConnectionHandler` retries `addAccount` (remove + re-add) when
  account creation fails, then fires the UI sync callback after the call-log
  pull completes.

Call-log UI display (`subscription_id`):

- Provider rows existed but `NSBTPhone`/`XCBTPhone` showed nothing because it
  matches the account by MAC string while `CallLogPullRequest` wrote
  `mAccount.hashCode()` (numeric) into `subscription_id`.
- `CallLogPullRequest` now writes `mAccount.name` (the MAC string), so the UI
  call log populates.

Infinite-loop fix:

- An initial implementation fired `onSyncPhonebookStatusChanged` for sync
  types 1, 2, and 3, which made the UI's sequential download chain restart
  forever (~every 15 s, effectively a DoS on the paired iPhone).
- Fixed by firing a single sync type (`sEcarxSyncType`, defaulting to `1`)
  and removing the extra delayed retries. Verified on the head unit: two
  downloads then silence, no periodic "sync complete" churn.

Release `v2026.06.30`:

- `module.prop` `2026.06.30`; APK `cbfe73aa…`; native `libbluetooth.so`
  `6675f14c…`.
- `rollback.sh` extended to clear the forced `bluetooth_class_of_device` and
  reset profile priorities so removal returns to stock.
- README rewritten in Russian (root-only requirement, full feature list,
  live-confirmed status, correct artifact link).
- Committed `df864f3`, tagged `v2026.06.30`, pushed, GitHub release created
  (asset SHA-256 `057be7cc…`).

### 2026-06-30: Stock bt_config backup and restore on removal

To make uninstall return the head unit to its *original* pairings rather
than a wiped Bluetooth config, install/removal now manage a one-time backup.
Released as `v2026.06.30.1`.

- `customize.sh` copies the stock
  `/data/misc/bluedroid/bt_config.conf` (and `.bak`) to
  `/data/adb/ecarx-bt-stock-backup` on install, only when no backup exists
  yet, so the first install captures true stock state and later updates keep
  it. The backup lives outside the module, so it survives uninstall.
- `rollback.sh` `cleanup_bluetooth_data()` restores that backup on removal
  (with `chown bluetooth:bluetooth` + `restorecon`, then deletes the backup
  dir). If no backup exists it falls back to deleting the experimental
  config so the stock stack starts clean. Snoop/firmware logs and transient
  caches are always cleared afterward.
- Note: the development head unit had already lost its stock `bt_config`
  earlier in the session (the MTK stack overwrote it), so this feature is
  forward-looking — it benefits future clean installs. Verified by review
  and `sh -n`, not by a live install/uninstall cycle (which would disrupt
  the working in-car Bluetooth).
- `module.prop` `2026.06.30.1`; committed `c19bd07`, tagged `v2026.06.30.1`.

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
- Writes the car-audio Class of Device to
  `Settings.Global bluetooth_class_of_device` (`2360352` / `0x240420`) so
  iOS offers contacts sync.
- Starts Bluetooth.

`customize.sh`:

- Sets file permissions on the payload and scripts.
- Backs up the stock `bt_config.conf` (and `.bak`) to
  `/data/adb/ecarx-bt-stock-backup` once, before the MTK stack overwrites it,
  for `rollback.sh` to restore on removal.

`rollback.sh`:

- Reverts runtime state as far as possible.
- Reverts `ro.ecarx.bt_ismtk` to `false`.
- Clears the forced `bluetooth_class_of_device` and resets the profile
  priorities back to undefined so the stock stack manages them.
- Clears imported Bluetooth phonebook and call-log provider data. These rows are
  written into `ContactsProvider` / `CallLogProvider`, so clearing only
  `com.android.bluetooth` is not enough.
- Restores the stock `bt_config.conf` from the install-time backup (original
  pairings), or deletes the experimental config if no backup exists.
- Clears Bluetooth pairing/profile/GATT cache and btsnoop/firmware logs so the
  stock stack starts without experimental state after module removal.
- Removes the donor OPP database so stock Bluetooth does not crash-loop with
  "Can't downgrade database".
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
2026.06.30.1
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
  - Capture a clean BLE session log with the final payload.
  - HWGPS does not connect over BLE during an active call: single-antenna SCO
    starves the LE scan. Treated as an inherent coexistence limitation.
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
  - Pairing-time iPhone prompt for contacts: resolved via car-audio CoD in
    `Settings.Global` (confirmed live).
  - Call-log UI display: resolved by writing the MAC string into
    `subscription_id` (confirmed live).
  - Auto-connect and auto-sync on pairing: resolved (no manual button).
  - Still open: import or display favorites.
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

## 2026-07-19 — Android media: A2DP Sink force-connect + NSMedia auto-pause

Live investigation on an IHU717P (root, adb) driven by two Android-phone
complaints: (1) music "plays for a second then pauses", (2) the phone connects
but has no media audio ("calls only"). iPhone was reported fine. Both turned out
to be head-unit-side, and the "iPhone is fine" belief was wrong.

### Auto-pause root cause (symptom 1)

The stock ECARX media app `com.ecarx.multimedia` (NSMedia; the `[XCMedia2Log]`
logger) enforces that Bluetooth audio may only play when the head unit's selected
**external source** is Bluetooth. Live log at the moment of the pause:

```
BluetoothManager: isCurrentBtAudio   current external = fm
[XCMedia2Log]BTMusicStateManagerP: bt pause but current external is not bt status:11
BTMusicActionImpl: pause:true
[XCMedia2Log]BTMusicStateManagerP: checkAndSendControl = RC_COMMAND_PAUSE ,isSuccess = true
bt_btif: send_passthrough_cmd   (AVRCP PASS-THROUGH PAUSE, key 0x46, to the phone)
```

`com.ecarx.multimedia` = `/system/app/NSMedia/NSMedia.apk`, build
`NSMedia_202408011547`. The pause class `BTMusicStateManagerP` and its messages
are **not** plaintext in the dex/vdex (Mars-xlog string obfuscation; only the
`XCMedia2Log` prefix is a literal), so it cannot be located by log string and is
not a plain smali patch target. The determinant is **only** `current external`,
not the phone brand: with the source on FM the iPhone is paused exactly like the
S24. Earlier "iPhone just works" measurements simply had the source already on
Bluetooth.

### Who owns auto-connect: car policy, not PhonePolicy

A2DP auto-connect on the head unit is managed by the car service
`com.android.car.BluetoothDeviceConnectionPolicy` (in `CarService.apk`), not by
`com.android.bluetooth`'s `PhonePolicy`. `dumpsys car_service` confirmed it live:
the policy is active and tracks HFP/PBAP/MAP/PAN/**A2DP_SINK**; `mProfilesToConnect`
includes `A2DP_SINK` (0xb). The ECARX variant `ECarxBluetoothDeviceConnectionPolicy`
keys off remote UUIDs including `AudioSource` (0x110A). Our transplanted stack
also starts its own `PhonePolicy` (gated by `config_bluetooth_phone_policy_enabled`,
`R.bool` id `0x7f020001`, `AdapterService` ~line 5131), whose
`setAutoConnectForA2dpSink` is wired to the source-side `getA2dpService()`
(null on this sink-only build) — a dead end for A2DP Sink. The real symptom for
the S24 was that the phone advertised no A2DP (stale SDP cache, no "Media audio"
toggle), so the car policy had it with `A2DP_SINK #Paired = 0`.

### A2DP Sink force-connect (symptom 2 — SHIPPED)

Initiating the A2DP Sink connection from the head unit brings the link up
regardless of the phone's stale cache. Live result on the S24:

```
BluetoothA2dpSink.connect(48:EF:1C:15:5F:D5) -> true
bta_av_start_ok: peer 48:ef:1c:15:5f:d5 ... AVDT_CONNECT_IND_EVT
A2dpSinkStateMachine: Connection state 0->1->2  (CONNECTED), A2DP Playing state 10->11
```

It also registered the device in the car policy (`A2DP_SINK #Paired 0 -> 1`).
`BluetoothA2dpSink.connect()` is hidden API; on Android 9 it is blocked from
reflection for a normal app (dark-greylist), so it is packaged as the bundled
system app `com.ecarx.btautosource` in `/system/app` (listed in the module's
`hiddenapi-package-whitelist.xml`; `/system/app` rather than priv-app to avoid any
priv-app permission bootloop — the call only needs `BLUETOOTH_ADMIN`). A
`service.sh` loop fires it (idempotent) when a phone is connected but A2DP Sink is
still down.

### Source-switch options tried (symptom 1)

To force the source to Bluetooth programmatically:

- `IMediaCenterWidgetApiSvc.onWidgetSourceSelected(2 /*SOURCE_TYPE_BT*/)` — bind
  to `ecarx.xsf.mediacenter/.MediaCenterService` (action
  `ecarx.xsf.ACTION_MEDIA_CENTER_WIDGET_API_SERVICE`) and transact. Reaches
  NSMedia but is **radio-centric** in this build (switched to FM, not BT).
  `selectMediaPlay(2, "")` and `handleCtrlApp(2,1)` no-op.
- **NSMedia activity router — the only thing that works.** Launch its
  `MainActivity` with a `RouteAction` JSON to the Bluetooth screen (`showIndex 4`
  = `RouteConstant.MAIN_INDEX_BLUETOOTH`, key `route`); a flat `"mainBluetooth"`
  string gives "No route info":

  ```
  am start -n com.ecarx.multimedia/.MainActivity --es route \
   '{"currentJump":"activityMain","showIndex":4,"nextJump":{"currentJump":"mainBluetooth","showIndex":4}}'
  ```

  Result: `PlayControl switchEngineByExternal: bt`, `curExternal = bt,301`,
  `plugin-external ... type:42008 jsonData:301 switchExternal`, and the pauses
  stop.

### Why symptom 1 has no automatic fix (deferred)

A timing capture is decisive:

```
onPlayStateChange:10 (playing), isCurrentBtAudio: current external = fm   @ T
checkAndSendControl = RC_COMMAND_PAUSE                                    @ T + ~28 ms
```

NSMedia pauses **~28 ms** after it sees the stream start. A userspace watcher
(`logcat` → `am start` → NSMedia route processing) is hundreds of ms, so it
cannot prevent the pause. Additionally the router switch is transient (the source
reverts to FM within seconds when Bluetooth is not actively streaming) and no-ops
when NSMedia is already foreground. A reliable fix would require a runtime hook
into NSMedia's obfuscated pause decision, or a native AVRCP change that can tell
the spurious pause from a legitimate one — both deferred. A `service.sh` watcher
that fired the router on the pause line was prototyped and **removed**: it lost
the 28 ms race and, by spamming the route, left NSMedia stuck foreground.

**Decision:** ship the A2DP force-connect; keep the manual workaround for the
pause (select Bluetooth as the head-unit source — it holds while playing).

### Tooling notes

- NSMediaCenter (`ecarx.xsf.mediacenter`) is not obfuscated; deodex via
  `vdexExtractor` → `.cdex` → `compact_dex_converter` → baksmali.
- Helper APK build: `javac --release 11` + `d8 --min-api 28` + `aapt2 link` +
  `zipalign` + `apksigner` (build-tools 36.1.0), debug keystore.
- `dumpsys car_service` (BluetoothDeviceConnectionPolicy) and
  `dumpsys bluetooth_manager` (A2dpSinkStateMachine state, `Streaming audio
  channels mask`) were the key state sources.

## 2026-07-19 — BLE/HWGPS freeze during calls: root-caused to MAP MCE

Symptom: a connected BLE device (HWGPS, `org.astpepper.hwgps`, peer
`1C:DB:D4:D0:BD:36`) stops receiving GATT notifications for the entire duration
of a phone call on some Android phones (Samsung Galaxy S24), resuming instantly
when the call ends. iPhone is unaffected.

### Live A/B (iPhone vs S24), verbose BT (TRC=5)

Both phones use mSBC/WBS with identical eSCO params (`lat 0x8, retrans 0x02,
pkt 0x03c8`), so codec/eSCO are ruled out. During the call the head unit tries
to return the phone's ACL link to sniff on a 7 s timer so BLE keeps getting
slots:

- **iPhone:** `bta_dm_pm_sniff idx:3, info:0x10/0x11` → `btm_pm_proc_mode_change
  → SNIFF` succeeds; link oscillates SNIFF↔ACTIVE; `bta_dm_pm_ssr ssr:2,
  lat:1200`. HWGPS notify_cb steady 7-8/s throughout.
- **S24:** `bta_dm_pm_sniff idx:3, info:0x12` → `bta_dm_pm_btm_status
  hci_status=26` (Unsupported Remote Feature); link stays ACTIVE; `ssr:0`.
  notify_cb drops to ~0 for the whole call.

`info` bits (`tBTA_DM_DEV_INFO`): `0x10`=USE_SSR, `0x01`=SET_SNIFF,
`0x02`=INT_SNIFF. The S24's `0x12` = USE_SSR+**INT_SNIFF** path re-negotiates the
existing interval-sniff and the controller rejects it during SCO; the iPhone's
clean-sniff path (`0x10`) is accepted. `idx` (sniff-interval spec row) is the
same (3) for both, so the sniff-interval spec table is not the lever.

### The differentiator is the MAP (MCE) profile

Empirically reducing the S24's connected profiles: with MAP connected the link
takes the `info:0x12` freeze path; with MAP **not** connected it takes
`info:0x10/0x11` and BLE survives. HFP-only and HFP+PBAP (MAP off) both keep
notify_cb flowing.

### Fix (shipped)

Disable the MAP MCE client in the bundled `Bluetooth.apk`:
`res/values/bools.xml` → `profile_supported_mapmce=false` (apktool rebuild,
zipalign, re-sign with the device platform key — cert SHA-256 `c8a2e9bc…`,
identical to the original so it installs in place). `AdapterServiceConfig` then
never adds `MapClientService`; the profile list becomes A2dpSink / Avrcp
Controller / Opp / Gatt / HeadsetClient / PbapClient. This is clean, unlike a
runtime `pm disable` of the component, which leaves AdapterService retrying the
start every ~2 s ("Unable to start MapClientService … not found") forever. This
head unit has no message-notification UI, so MAP provided nothing.

Verified live: ~20 s call with MAP off — `MceSM Connected=0`, `bta_dm_pm_sniff
info:0x10`, HWGPS notify_cb zero drops. The candidate SSR / sniff-spec native
`libbluetooth.so` patches from the earlier Ghidra pass turned out unnecessary.

## 2026-07-27 — AVRCP track metadata: GetCapabilities race (fixed)

Reported on iOS: BT music plays, steering-wheel buttons work, but the head unit
shows no track info and HU-side track switching does nothing. Stock ECARX
firmware is unaffected.

### Method: A/B against stock

The module was removed, the head unit booted to the stock CSR/GOC stack, and the
same iPhone was paired and exercised (call + music + buttons). Then the module
was reinstalled and the same cycle repeated. Logs in `work/bt_stock_vs_module/`.

| Run | AVRCP up | A2DP up | Order | metadata |
|---|---|---|---|---|
| stock | 13:53:26 | 13:53:22 | **A2DP → AVRCP** | 164 events |
| module, MAP off | 14:10:56 | 14:10:58 | AVRCP → A2DP | 0 |
| module, MAP on | 14:17:56 | 14:17:58 | AVRCP → A2DP | 0 |
| module, fresh pairing | 14:34:57 | 14:34:58 | AVRCP → A2DP | 0 |

Ruled out by these runs: the MAP profile (A/B on/off), the bond cache (full
unpair plus re-pair), our own module deltas (`Bluetooth.apk` and
`libbluetooth.so` were byte-identical to the last known-good build;
`mtk_bt_stack.conf` differed only in trace levels), the A2DP force-connect
helper, and the phone itself.

### Root cause

A verbose capture (`TRC_AVRC/BTIF/SDP=5`) showed the mechanism:

```
bta_av_rc_opened: rcb[0] shdl:0                       AVRCP opens before A2DP
btif_rc_handler: Peer_features: 3    -> CTRL: 0
btif_rc_handler: Peer_features: 24b  -> CTRL: 3       (METADATA present)
  getcapabilities_cmd: cap_id: 2
  build_and_send_vendor_cmd: AVRC_PDU_GET_CAPABILITIES
BTA_AV_OPEN_EVT  StateOpening -> StateOpened          A2DP finishes 1.1 s later
btif_rc_handler: Peer_features: 24b  -> CTRL: 2       (METADATA dropped)
handle_get_capability_response: Error capability response: 0xFE    timeout
```

`BTRC_FEAT_*`: 1 = METADATA, 2 = ABSOLUTE_VOLUME, 4 = BROWSE.

Two defects combine, both in `handle_rc_ctrl_features()` / the capability path:

1. `GetCapabilities(COMPANY_ID)` is issued while A2DP is still connecting. The
   phone does not answer within the AVRCP timeout, so
   `handle_get_capability_response()` takes AOSP's early `return` — the upstream
   TODO `/* Todo: Do we need to retry on command timeout */` is still unfixed as
   of Android 14. `EVENTS_SUPPORTED` is never queried and `RegisterNotification`
   is never sent, so metadata is dead for the whole session.
2. `p_dev->rc_features_processed = true` latches on that first attempt, so the
   block never runs again — no retry, and the next feature event reports the
   controller a value without `BTRC_FEAT_METADATA` (the `3 → 2` above).

### Fix

NOP the latch store, so every `BTA_AV_RC_FEAT_EVT` re-runs the block:

```
vaddr 0x1afd60 (foff 0x174d60)   strb w9, [x8]  0x39000109  ->  nop  0xd503201f
```

Tool: `work/tools/patch_libbluetooth_avrcp_metadata_retry.py` (verifies the
original word before patching, supports `--revert`). `rc_features_processed` has
no other consumer in Android 9 (`btif_rc.cc` lines 471/478, reset on connect), so
the NOP is self-contained.

Verified live on the same iPhone that failed before:

```
15:06:50.358  getcapabilities_cmd: cap_id: 2
15:06:52.359  Error capability response: 0xFE      first attempt still times out
15:06:55.836  getcapabilities_cmd: cap_id: 2       retry (enabled by the NOP)
15:06:55.844  getcapabilities_cmd: cap_id: 3       EVENTS_SUPPORTED, succeeded
RegisterNotification: 36                            (was 0)
btavrcp_track_changed_callback: 11                  (was 0)
btavrcp_play_status_changed_callback: 15            (was 0)
BTMusicManager: title : Stars, album : Stars, artist : Simply Red
```

### Upstream comparison

Android 16 fixes the same race in `handle_rc_ctrl_features()` by deferring the
command until A2DP is connected:

```c
if (btif_av_is_connected_addr(p_dev->rc_addr, A2dpType::kSink)) {
  ...
  getcapabilities_cmd(AVRC_CAP_COMPANY_ID, p_dev);
} else {
  p_dev->launch_cmd_pending |= (RC_PENDING_ACT_GET_CAP | RC_PENDING_ACT_REG_VOL);
}
```

Porting that needs new code (a pending-command queue fired on A2DP connect).
Swapping the existing `btif_av_is_sink_enabled()` call for `btif_av_is_connected()`
was considered and rejected: the latter resolves the *active* peer, which is not
reliably set at that point on this build, and would risk suppressing the command
entirely. The retry approach achieves the same end state with one instruction.

Cost: `handle_get_capability_response()` allocates a fresh
`rc_supported_event_list` per successful response without freeing the previous
one, so a few small leaks per connection are possible — bounded by the handful of
feature events per connect, and judged acceptable.

## Delta against the donor — what we changed and why

Donor baseline: **Cubot X20 Pro V07** (Android 9 / MT6771), kept at
`work/ble_patch/full_transplant_candidates/03_cubot_x20pro_v07_minimal_bt/payload/`.
(Oukitel C21 V08 was evaluated and rejected — Android 10 / VNDK 29 against the
head unit's Android 9 / VNDK 28.) The `restore_payload/` tree in the same folder
holds the head unit's own stock files.

### `libbluetooth.so` — exactly three native patches

Byte diff donor → shipped (same file size, three 4-byte words changed;
geometry `vaddr = foff + 0x3b000`):

| foff | vaddr | before → after | why |
|---|---|---|---|
| `0x085fac` | `0x0c0fac` | `cbz w8, …` `0x340005e8` → `nop` | `bta_av_rc_disc_done`: AVRCP CT feature negotiation was gated on our own local AVRCP SDP handle, which stock code only creates when registering the A2DP **Source** role. Sink-only build ⇒ handle stays `0` ⇒ no GetCapabilities / RegisterNotification / metadata at all. Removing the check restores media buttons and track info. |
| `0x121fe8` | `0x15cfe8` | `mov w22, wzr` `0x2a1f03f6` → `mov w22, #1` `0x52800036` | `bta_av_co_audio_init`: the MTK build registered no local **sink** AVDTP SEPs, so A2DP could connect but never stream — no music. |
| `0x174d60` | `0x1afd60` | `strb w9, [x8]` `0x39000109` → `nop` | `handle_rc_ctrl_features`: drops the `rc_features_processed` latch so `GetCapabilities` is retried after its first attempt races A2DP setup and times out (`0xFE`). See the 2026-07-27 entry. |

### `Bluetooth.apk` — role flip from phone to head unit

Profile bools, donor → ours:

| bool | donor (phone) | ours (head unit) |
|---|---|---|
| `a2dp` | true | **false** |
| `a2dp_sink` | false | **true** |
| `avrcp_target` | true | **false** |
| `avrcp_controller` | false | **true** |
| `hs_hfp` | true | **false** |
| `hfpclient` | false | **true** |
| `pbap` | true | **false** |
| `pbapclient` | false | **true** |
| `map` | true | **false** |
| `mapmce` | false | false (kept off — see the MAP/BLE entry) |
| `hdp`, `hid_device`, `hid_host`, `pan`, `sap` | true | **false** (not useful in a car) |
| `gatt`, `opp` | true | true (unchanged) |

Code patches inside the APK (documented in the sections above): A2DP Sink audio
focus request, `HfpClientConnection.updateCall()` → `connectAudio()` for call
audio, and the PBAP client auto-sync/`addAccount` retry work.

Everything else the module does lives outside the APK — `service.sh` (car Class
of Device, runtime grants/appops, profile priority reset, `gocsdk` watchdog) and
the transplanted MTK libraries/configs.

### Consequence worth remembering

`avrcp_controller` false → **true** is what activates AOSP's
`AvrcpControllerStateMachine`. That class applies remote AVRCP absolute-volume
commands to the local stream **unconditionally**
(`setStreamVolume(STREAM_MUSIC, maxVol * absVol / 127)`), which the donor never
ran (it was an AVRCP target) and which the head unit's own stock CSR stack does
not implement at all (zero absolute-volume events in the stock capture). Any
absolute-volume misbehaviour is therefore inherent to the CT path we enabled,
not to the three native patches.

## 2026-07-28 — CORRECTION: disabling MAP does NOT fix the in-call BLE freeze

The 2026-07-19 conclusion above ("MAP MCE is the culprit") is **disproven**. A
strict per-second measurement on the shipped build, with MAP already disabled,
shows the freeze is unchanged.

`v2026.07.27.1`, `TRC_BTIF=5`, Galaxy S24 + HWGPS (`org.astpepper.hwgps`),
log `work/bt_stock_vs_module/ble_call_base271.log`:

| period | GATT notify |
|---|---|
| before call | 6.9 /s |
| **during call (26 s)** | **0.0 /s - zero for every one of the 26 seconds** |
| after call | 7.3 /s |

Cross-checked on the `slim_A` build (`ble_call_slimA.log`): call 1 (9 s) 1.6/s
with 8 of 9 seconds at zero, call 2 (30 s) 0.0/s throughout. Identical picture,
so the payload-slimming work is unrelated to this defect.

**Why the earlier conclusion was wrong.** The 2026-07-19 runs that appeared to
prove MAP differed in more than MAP: call duration, whether the link had been
idle beforehand, and - decisively - in the MAP-on retest `MceSM` never actually
reached Connected, so the variable under test was never really applied.
Correlation was read as causation.

A second error, made and corrected on 2026-07-28, is worth recording: an initial
per-second count reported "only an 8 s dropout", because the assumed call window
spanned call 1 plus the idle gap between two calls while excluding call 2
entirely. Re-deriving the windows from the Telecom `SET_DIALING` /
`SET_DISCONNECTED` timestamps gave the correct result above.

**What still stands** is the iPhone-versus-S24 comparison (identical mSBC and
eSCO parameters): the iPhone link carries `ssr:2 lat:1200` and its in-call sniff
requests (`info:0x10/0x11`) succeed, while the S24 link has `ssr:0` and its
single request (`info:0x12`, i.e. USE_SSR + INT_SNIFF) is refused with
`hci_status=26` (Unsupported Remote Feature), leaving the link ACTIVE. The
sniff-interval spec row (`idx`) is the same for both, so that table is not the
lever. The open question is why the S24 link ends up with `ssr:0`, and whether
the phone supports SSR at all.

**Consequence for this module:** disabling MAP MCE brings no BLE benefit. Its
only observable effect is that the iOS "Messages" toggle disappears. The
rationale given for it in this document, in the README and in the v2026.07.19.1
release notes is incorrect, and whether to keep MAP disabled at all is now an
open decision.
