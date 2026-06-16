# ECARX E02 IHU717P Geely/Knewstar Bluetooth Magisk Module

This module packages the reduced Bluetooth experiment for ECARX E02 / IHU717P
based Geely and Knewstar head units. Files that matched the stock IHU717P
firmware byte-for-byte were removed from the payload.

- replaces the stock `/system/app/Bluetooth` directory via `.replace`;
- overlays `/system/app/Bluetooth/Bluetooth.apk` at the stock PackageManager code path;
- patches the APK resource profile flags to the car/head-unit profile set
  (`A2DP Sink`, `Headset Client`, `PBAP Client`, `AVRCP Controller`);
- overlays Bluetooth libraries in `/system/lib64` and app-local `lib/arm64`;
- adds `privapp-permissions-ecarx-e02-bluetooth.xml` with the broader
  Bluetooth/MAP/PAN/HFP/A2DP/AVRCP/audio/telephony privilege set requested by
  the bundled Bluetooth APK;
- adds a package-specific hidden API whitelist for `com.android.bluetooth`;
- sets `ro.ecarx.bt_ismtk=true`;
- loads `/vendor/lib/modules/bt_drv.ko`;
- grants runtime/appops for contacts, call log, SMS/MAP, storage/OPP, location
  scanning, accounts, overlay/settings, and usage stats;
- fixes `/dev/stpbt` owner/mode and enables Bluetooth after boot.

The bundled APK is still the receiver-patched build. A fully unpatched APK did
not receive `android.permission.INTERACT_ACROSS_USERS_FULL` because the IHU
framework declares that permission as `signature|installer`, not
`signature|privileged`.

License:

This module's original packaging, scripts, documentation, and project glue are
released under the MIT License. See `LICENSE`.

Third-party firmware, APKs, binaries, libraries, symbols, names, and protocols
referenced by or bundled with this experiment remain subject to their own
licenses and rights holders. The MIT License for this module does not grant any
extra rights to third-party components.

Disclaimer:

This module is experimental and provided for research, diagnostics, and
interoperability work only. It is provided "AS IS", without warranty of any
kind.

You are solely responsible for using it. The authors and contributors are not
liable for damaged or bricked devices, boot loops, data loss, warranty loss,
unsafe vehicle behavior, legal issues, license violations, or any other direct
or indirect damage caused by installation, modification, redistribution, or use.

Open TODO:

- Music/audio path is not finished yet: validate A2DP Sink connection, media
  audio routing into the head unit mixer, AVRCP metadata, and play/pause/track
  controls from the car UI.
- Phone call path is not finished yet: validate HFP/HF Client registration,
  SCO audio routing, microphone capture, call state updates, caller ID, answer,
  reject, hangup, and in-call volume controls.

Current caution: this module intentionally forces the MTK/STP path. It is not
the stable stock Classic Bluetooth setup, which uses the ECARX/GOC path with
`ro.ecarx.bt_ismtk=false`.
