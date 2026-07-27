# Bluetooth Magisk Module

This is an experimental Magisk module for ECARX E02 / IHU717P based Geely
and Knewstar head units. It overlays a patched Bluetooth APK, MTK/STP Bluetooth
libraries, permissions, boot scripts, and audio/Bluetooth HAL support files for
researching BLE/HWGPS, A2DP Sink, HFP Client, PBAP Client, and AVRCP Controller
behavior on the head unit.

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

---

# Magisk-модуль для Bluetooth

Перед вами экспериментальный Magisk-модуль для Bluetooth/BLE на головных
устройствах ECARX E02 / IHU717P для Geely и Knewstar. Модуль реализует
рабочий MTK/STP Bluetooth-стек, устанавливает патченный Bluetooth APK, необходимые 
библиотеки и конфиги в системный слой.

Модуль делает следующее:

- заменяет штатный каталог `/system/app/Bluetooth` через `.replace`;
- подменяет `/system/app/Bluetooth/Bluetooth.apk` в штатном PackageManager path;
- включает профильный набор для ГУ в ресурсах APK: `A2DP Sink`, `Headset Client`,
  `PBAP Client`, `AVRCP Controller`;
- подменяет Bluetooth-библиотеки в `/system/lib64` и app-local `lib/arm64`;
- добавляет `privapp-permissions-ecarx-e02-bluetooth.xml` с расширенным набором
  прав для Bluetooth/MAP/PAN/HFP/A2DP/AVRCP/audio/telephony;
- добавляет package-specific hidden API whitelist для `com.android.bluetooth`;
- выставляет `ro.ecarx.bt_ismtk=true`;
- загружает `/vendor/lib/modules/bt_drv.ko`;
- выдаёт runtime grants/appops для контактов, журнала звонков, SMS/MAP,
  storage/OPP, location scanning, accounts, overlay/settings и usage stats;
- патчит нативный A2DP Sink (`bta_av_co_audio_init` в `libbluetooth.so`): MTK-сборка
  не регистрировала локальные приёмные AVDTP-SEP, из-за чего музыка не играла;
- запрашивает audio focus при старте A2DP-потока (иначе декодер дропал кадры и звук
  не доходил до динамиков);
- чинит аудио звонка (HFP HF Client): подключает SCO при активном вызове, а патч
  аудио-HAL `audio.primary.ecarxp.so` делает громкость вызова динамической;
- авто-синхронизирует PBAP при подключении телефона (контакты, журнал вызовов,
  избранное) и обновляет их в UI штатного телефонного приложения;
- выставляет автомобильный Class of Device (`0x240420` — Audio/Video / Car audio)
  через `Settings.Global bluetooth_class_of_device`, чтобы iPhone предлагал
  синхронизацию контактов при сопряжении (стоковый MTK-класс — «смартфон»);
- сбрасывает зависшие отрицательные приоритеты Bluetooth-профилей;
- держит фоновый watchdog, который не даёт стоковому `gocsdk` подняться
  повторно после загрузки: `gocsdk` стартует только по событийному триггеру
  `on property:ro.ecarx.bt_ismtk=false` в `init.rc`, а наш модуль до этого
  выставлял свойство лишь один раз при загрузке. После сессии CarPlay
  Bluetooth иногда не восстанавливался — из-за возврата этого свойства и
  повторного старта GOC поверх уже работающего MTK/AOSP-стека. Watchdog
  каждые 15 секунд проверяет `ro.ecarx.bt_ismtk` и `gocsdk`, чинит их и сам
  завершается при отключении/удалении модуля;
- нативный патч `libbluetooth.so`, который чинит кнопки перемотки/паузы на
  руле и метаданные трека (название/исполнитель/альбом) для BT-музыки:
  реверс-инжинирингом (Ghidra) найдено, что обработка AVRCP-фич собеседника
  (`bta_av_rc_disc_done`) была завязана на SDP-хендл нашей же локальной
  AVRCP-записи, который стоковый код создаёт **только** при регистрации роли
  A2DP Source (`0x110a`). Модуль собран как sink-only (роль Source осознанно
  отключена ради чистоты A2DP-звука), поэтому этот хендл навсегда оставался
  `0` — и весь AVRCP CT feature-negotiation (`GetCapabilities`,
  `RegisterNotification`, метаданные трека) не выполнялся вообще, независимо
  от того, что реально поддерживает телефон. Патч убирает эту проверку одной
  инструкцией (`cbz→nop`), не трогая регистрацию профилей/SDP — не влияет на
  уже работающий A2DP-звук. Обложка альбома всё равно не отображается — это
  не баг, а платформенный потолок: в этой сборке (Android 9 / API 28) в
  `avrcpcontroller` нет кода для AVRCP Cover Art (BIP/OBEX), эта функция
  появилась в AOSP только в Android 12+.

## Лицензия

Оригинальная упаковка модуля, скрипты, документация и проектная обвязка
распространяются по лицензии MIT. См. `LICENSE`.

Сторонние прошивки, APK, бинарные файлы, библиотеки, символы, названия и
протоколы, на которые ссылается этот эксперимент или которые входят в его
состав, остаются под лицензиями и правами их владельцев. MIT-лицензия этого
модуля не даёт дополнительных прав на сторонние компоненты.

## Отказ от ответственности 

Этот модуль экспериментальный и предназначен только для исследований,
диагностики и работ по совместимости. Он предоставляется "как есть", без
каких-либо гарантий.

Вы единолично отвечаете за его использование. Авторы и участники не несут
ответственности за повреждённые или заблокированные устройства, boot loop,
потерю данных, потерю гарантии, небезопасное поведение автомобиля, юридические
проблемы, нарушения лицензий и любой другой прямой или косвенный ущерб,
возникший из-за установки, модификации, распространения или использования.


## Статус

Модуль объединяет два связанных, но отдельных направления:

- BLE/GATT для HWGPS-модуля. HWGPS подключается по BLE и виден Android как
  `org.astpepper.hwgps`; этот путь отделён от Classic Bluetooth audio/phone
  профилей.
- Classic Bluetooth для интеграции телефона с ГУ: HFP/HF Client, PBAP Client,
  A2DP Sink и AVRCP Controller.

Подтверждено на живом ГУ (iPhone): музыка по A2DP играет, звонки HFP со звуком,
BLE/HWGPS подключается, контакты и журнал вызовов синхронизируются и видны в UI,
при сопряжении iPhone предлагает синхронизацию контактов, физические кнопки
руля (перемотка/пауза) и метаданные трека (название/исполнитель/альбом)
работают через AVRCP.

## Требования

- **Только устройство с root (Magisk).** Модуль ставится через Magisk и заменяет
  системные Bluetooth-файлы через systemless-оверлей; без root он не установится
  и не заработает.
- ECARX E02 / IHU717P (MediaTek MT6771, Android 9). На другом железе не
  тестировался.
- Перед установкой держите наготове резервный канал доступа (UART/ADB): модуль
  перезапускает Bluetooth и меняет системные настройки.

## Установка

Установить release ZIP через Magisk и перезагрузить ГУ.

Актуальный артефакт (в `work/releases/`):

```text
ecarx_e02_ihu717p_bt_v2026.07.04.zip
```

Ожидаемый эффект от модуля:

- `ro.ecarx.bt_ismtk=true`;
- `/dev/stpbt` существует и принадлежит `bluetooth:bluetooth`;
- Bluetooth доходит до `state: ON` без повторяющихся падений `com.android.bluetooth`.

## Откат

Штатные файлы вернутся после отключения/удаления модуля и перезагрузки ГУ
(оверлей systemless — реальный `/system` не меняется). При удалении модуль
автоматически запускает `rollback.sh`, который возвращает ГУ в стоковое
состояние:

- возвращает `ro.ecarx.bt_ismtk=false` (стоковый ECARX/GOC-путь поднимется после
  ребута, `gocsdk` снова запустится сам);
- удаляет из `Settings.Global` навязанный `bluetooth_class_of_device` (CoD) и
  сброшенные приоритеты профилей;
- отзывает выданные runtime-права и сбрасывает appops для `com.android.bluetooth`;
- очищает импортированные через Bluetooth контакты и журнал звонков из
  `ContactsProvider` / `CallLogProvider` (они записаны в системные provider-базы
  и не удаляются простым `pm clear com.android.bluetooth`);
- **восстанавливает стоковый `bt_config.conf` bluedroid** из копии, снятой при
  установке (в `/data/adb/ecarx-bt-stock-backup`), — оригинальные сопряжения
  возвращаются; если копии нет, конфиг экспериментального стека удаляется, и
  стоковый Bluetooth стартует с чистого листа;
- удаляет данные приложения Bluetooth (включая OPP-базу, иначе стоковый Bluetooth
  падает в цикле `Can't downgrade database`) и btsnoop/firmware-логи.

После удаления обязателен ребут, чтобы systemless-оверлеи исчезли.

> Резервная копия стокового `bt_config.conf` снимается **один раз при первой
> установке** (`customize.sh`), пока ещё активен стоковый стек, и хранится вне
> модуля, поэтому переживает удаление. Если во время использования модуля
> сопрягались новые устройства, при откате вернётся именно то состояние
> сопряжений, что было до установки модуля.

## Поддержка автора

Благодарность за работу автора можно выразить материально:

[<img src="https://nearlynydev.github.io/static/qr.jpg" width="200px" />](https://pay.cloudtips.ru/p/627dbed1)

https://pay.cloudtips.ru/p/627dbed1

## Группа поддержки

Обсуждение, вопросы по установке и обратная связь — в Telegram-группе:

https://t.me/ecarx02_ble

---

## v2026.07.19 — A2DP Sink force-connect (+ NSMedia auto-pause investigation)

### Shipped fix — A2DP Sink never connects (phone shows Phone-audio only)

Some phones (observed: Samsung Galaxy S24) cache an incomplete SDP record for
the head unit, show **no "Media audio" toggle**, and connect HFP/PBAP only —
A2DP never comes up. The head unit's own A2DP Sink works (iPhone uses it), so the
fix is to **initiate the A2DP Sink connection from the head unit side**, which
brings the link up regardless of the phone's stale cache and also registers the
device with the car `BluetoothDeviceConnectionPolicy` for later auto-connects.

The privileged call `BluetoothA2dpSink.connect()` is hidden API, so it lives in a
bundled system app `com.ecarx.btautosource` (`/system/app/EcarxBtAutoSource`,
listed in `hiddenapi-package-whitelist.xml`; placed in `/system/app`, not
priv-app, so it needs no `privapp-permissions` entry and cannot bootloop). A
`service.sh` loop watches for a connected phone with A2DP Sink still down and
fires the helper (idempotent — `connect()` returns false if already up):

```
am start -n com.ecarx.btautosource/.A2dpConnectActivity --es addr AA:BB:CC:DD:EE:FF
```

The loop self-exits when the module is disabled/removed. Log:
`/data/adb/ecarx-bt-autosource.log`. Validated live on an S24:
`A2dpSinkStateMachine 0->1->2 CONNECTED`, streaming, and the phone registered in
the car connection policy.

### Investigated, NOT auto-fixed — spurious BT auto-pause ("plays 1s, then pauses")

Root cause (confirmed live): the stock ECARX media app `com.ecarx.multimedia`
(NSMedia) only lets Bluetooth audio play when the head unit's selected
**external source** is Bluetooth. With the source on FM/AM/etc, its
`BTMusicStateManagerP` sends AVRCP PASS-THROUGH **PAUSE** at the phone, logging
`bt pause but current external is not bt`. This is **source-selection, not phone
brand** — iPhone is affected identically when the source is not Bluetooth (the
old "iPhone just works" belief was because its source happened to already be
Bluetooth).

Switching the source to Bluetooth stops it. NSMedia has no clean binder API for
that (the MediaCenter widget AIDL `onWidgetSourceSelected` is radio-centric;
`selectMediaPlay`/`handleCtrlApp` no-op for BT). The one thing that works is
NSMedia's **activity router**:

```
am start -n com.ecarx.multimedia/.MainActivity --es route \
 '{"currentJump":"activityMain","showIndex":4,"nextJump":{"currentJump":"mainBluetooth","showIndex":4}}'
```

**Why there is no automatic fix (yet).** A timing capture showed NSMedia sends
the PAUSE only **~28 ms** after it sees the phone start playing
(`onPlayStateChange:10` → `RC_COMMAND_PAUSE` at +28 ms). A userspace watcher
(`logcat` → `am start` → NSMedia processes the route) takes hundreds of ms, so it
**cannot win that race**. On top of that the router switch is transient (the
source reverts to FM within seconds when Bluetooth is not actively streaming) and
no-ops when NSMedia is already foreground. A reliable fix needs either a runtime
hook into NSMedia's pause decision (the class is Mars-xlog string-obfuscated, so
not a plain smali patch) or a native AVRCP change that can't cleanly tell the
spurious pause from a legitimate one. Both are deferred.

**Workaround (reliable):** on the head unit, **select Bluetooth as the audio
source once** — it holds while playing and the pause stops. Full teardown of the
investigation is in `docs/BLE_RESEARCH_HISTORY.md`.

---

## v2026.07.19.1 — Fix BLE/HWGPS freezing during phone calls (disable MAP MCE)

Symptom: on some Android phones (observed: Samsung Galaxy S24) a connected BLE
device (HWGPS) **freezes for the whole duration of a phone call** — GATT
notifications stop the moment call audio (SCO) starts and resume the instant it
ends. iPhone is unaffected.

Root cause (found by live A/B verbose capture, iPhone vs S24, identical mSBC/eSCO
params): during a call the head unit tries to put the phone's ACL link into
**sniff** so BLE keeps getting radio slots. The iPhone link sniffs fine
(`bta_dm_pm_sniff info:0x10/0x11` → SNIFF ok, `ssr:2`). The S24 link takes the
**INT_SNIFF** path (`bta_dm_pm_sniff info:0x12`) and the controller **rejects**
it (`bta_dm_pm_btm_status hci_status=26`, "Unsupported Remote Feature"), so the
link stays ACTIVE and SCO + active-ACL starve BLE. The differentiator is
**MAP (Message Access, MCE client)**: with MAP connected the S24 link uses the
0x12 path (freeze); with MAP not connected it uses 0x10 (BLE survives).

Fix: disable the MAP MCE client in the bundled `Bluetooth.apk`
(`res/values/bools.xml`: `profile_supported_mapmce=false`, re-signed with the
device platform key `c8a2e9bc`). `AdapterServiceConfig` then never adds
`MapClientService` — clean, with none of the retry-loop log spam that a runtime
`pm disable` of the component produces. This head unit has no message-notification
UI, so MAP provided nothing. Verified live: a ~20 s call with MAP off keeps
HWGPS GATT notifications flowing with zero drops (`info:0x10`, no `hci_status=26`
stall). Removing the module reverts to the stock Bluetooth app (MAP intact).

Prior candidate SSR / sniff-spec native patches were investigated and turned out
**unnecessary** — the real lever was the MAP profile. Full teardown in
`docs/BLE_RESEARCH_HISTORY.md`.

---

## v2026.07.19.2 — AVRCP-safe MAP disable; A2DP force-connect removed

Two changes over v2026.07.19.1:

- **MAP MCE now disabled without touching classes.dex.** v2026.07.19.1 flipped
  `profile_supported_mapmce` by rebuilding the whole APK with apktool, which
  recompiles `classes.dex` from smali — that regressed AVRCP on iOS (track
  switching from the head unit and track-info transfer stopped). This build
  instead binary-patches the single bool value in `resources.arsc` (4 bytes,
  `0xFFFFFFFF` → `0`) on the original APK, so **`classes.dex` stays byte-identical**
  to the known-good v2026.07.19 build (verified by SHA-256) and is re-signed with
  the device platform key. MAP stays off, AVRCP is untouched.
- **A2DP Sink force-connect helper removed.** The `com.ecarx.btautosource` system
  app and its `service.sh` watcher are gone, to observe stock A2DP connection
  behaviour. It remains in git history if needed again.

---

## v2026.07.27 — Fix missing AVRCP track metadata (GetCapabilities race)

Symptom (reported on iOS, reproduced live): BT music plays and the steering-wheel
buttons work, but the head unit shows no track info and track switching from the
HU does nothing. The stock ECARX firmware does not have this problem.

Root cause (proven with an A/B against stock plus a verbose capture — full
teardown in `work/bt_stock_vs_module/`): our stack brings the **AVRCP link up
before A2DP** and immediately issues `GetCapabilities(COMPANY_ID)`. The phone is
still establishing A2DP and does not answer in time:

```
15:06:50.358  getcapabilities_cmd: cap_id: 2
15:06:52.359  handle_get_capability_response: Error capability response: 0xFE   <- timeout
```

AOSP's `btif_rc.cc` then returns early — the upstream TODO
`/* Todo: Do we need to retry on command timeout */` is still unfixed as of
Android 14 — so `EVENTS_SUPPORTED` is never queried and `RegisterNotification`
is never sent. Metadata is dead for the whole session, while passthrough and
absolute volume keep working (hence "buttons work, no track info").

There is no retry either, because `handle_rc_ctrl_features()` latches
`p_dev->rc_features_processed = true` on that first attempt. The latch also makes
the *next* feature event drop `BTRC_FEAT_METADATA` from the value reported to the
Java controller (observed: CTRL `0` → `3` → `2`).

Fix: NOP that latch store in `libbluetooth.so`
(`work/tools/patch_libbluetooth_avrcp_metadata_retry.py`, vaddr `0x1afd60`).
Each feature event then re-runs the block, so `GetCapabilities` is retried — by
the later events A2DP is up and it succeeds — and `BTRC_FEAT_METADATA` stays set.

Verified live on the same iPhone that failed before:

```
15:06:55.836  getcapabilities_cmd: cap_id: 2     <- retry
15:06:55.844  getcapabilities_cmd: cap_id: 3     <- EVENTS_SUPPORTED, succeeded
RegisterNotification: 36                          (was 0)
btavrcp_track_changed_callback: 11                (was 0)
BTMusicManager: title : Stars, album : Stars, artist : Simply Red
```

Upstream AOSP fixes the same race differently (Android 16): it defers
`GetCapabilities` until A2DP is connected (`btif_av_is_connected_addr(...)`,
otherwise `launch_cmd_pending |= RC_PENDING_ACT_GET_CAP`). Porting that needs new
code; swapping the existing `btif_av_is_sink_enabled()` call for
`btif_av_is_connected()` was considered and rejected — the latter resolves the
*active* peer, which is not reliably set at that point on this build.
