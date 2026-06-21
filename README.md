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
  storage/OPP, location scanning, accounts, overlay/settings и usage stats.

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


## Установка

Установить release ZIP через Magisk и перезагрузить ГУ.

Актуальный артефакт (с фиксом A2DP Sink):

```text
work/releases/ecarx_e02_ihu717p_bt_v2026.06.21.zip
```

Ожидаемый эффект от модуля:

- `ro.ecarx.bt_ismtk=true`;
- `/dev/stpbt` существует и принадлежит `bluetooth:bluetooth`;
- Bluetooth доходит до `state: ON` без повторяющихся падений `com.android.bluetooth`.

## Откат

Штатные файлы вернутся после отключения/удаления модуля и перезагрузки ГУ.

## Поддержка автора

Благодарность за работу автора можно выразить материально:

[<img src="https://nearlynydev.github.io/static/qr.jpg" width="200px" />](https://pay.cloudtips.ru/p/627dbed1)

https://pay.cloudtips.ru/p/627dbed1
