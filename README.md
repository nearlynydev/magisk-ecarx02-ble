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
- сбрасывает зависшие отрицательные приоритеты Bluetooth-профилей.

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
при сопряжении iPhone предлагает синхронизацию контактов.

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
ecarx_e02_ihu717p_bt_v2026.06.30.1.zip
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
