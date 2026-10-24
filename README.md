# FreentoSwitcher

Открытая замена PuntoSwitcher для macOS на Apple Silicon (arm64).
Переключение раскладки, автоконвертация слов, набранных в неверной раскладке.

Open-source replacement for the discontinued PuntoSwitcher on Apple Silicon macOS.
Keyboard layout switching and automatic correction of words typed in a wrong layout.

**Не аффилировано с Яндексом. Все словари и данные собраны заново из открытых источников.**
**Not affiliated with Yandex. All dictionaries are rebuilt from open data.**

## Статус / Status

✅ **MVP-ядро работает — готово к ручной приёмке.** Ветка `feature/mvp-core`:
33 юнит-теста зелёные, release-сборка и упаковка в `.app` проходят.

Что уже есть / What works:

- Перехват клавиатуры через `CGEventTap` и переключение между двумя
  настроенными раскладками по горячей клавише **Cmd+\`**.
- Автоконвертация слова, набранного в неверной раскладке, по триггер-словарю
  (seed-версия, 248 слов) с переключением раскладки и звуком.
- Undo-конвертация по **Option+`** (откат последней автоконвертации).
- Иконка в статус-баре с меню: Switch Layout / Toggle Autocorrection /
  Debug Logging / Quit.
- Детальный лог для диагностики: персистентный переключатель **Debug Logging**
  в меню иконки пишет клавиши/хоткеи/эффекты в `$TMPDIR/freento-debug.log`
  (ленивый, при выключенном состоянии накладных расходов нет).
- Архитектура Engine (чистый Swift, без платформы) / Platform (CGEventTap,
  TIS, синтез клавиш) / App (NSStatusItem): `Sources/Engine`, `Sources/Platform`,
  `Sources/App`.

Известные ограничения MVP / Known MVP limitations:

- Подпись ad-hoc — при первом запуске нужен обход Gatekeeper (см. ниже).
- LaunchAtLogin пока не подключён (код есть, wiring отложен).
- Триггер-словарь — seed-версия на 248 слов (полный генератор из открытых
  корпусов — в плане).
- UI настроек нет: параметры можно изменить через `defaults` в группе
  `com.freento.FreentoSwitcher` (см. `Sources/Engine/Settings/AppSettings.swift`).
- Accessibility-слой оригинала (per-app исключения, особые правила для
  браузеров) не реализован — в плане.

План B (после приёмки MVP): Accessibility-слой, конвертация/регистр выделения,
раскладка на приложение, окна настроек, генератор словарей, Sparkle-апдейтер,
CI + релизный workflow.

## Ручная приёмка / Manual smoke checklist

1. Запустить `build/FreentoSwitcher.app` (правый клик → «Открыть», чтобы
   обойти Gatekeeper). В статус-баре появляется иконка **⇄**.
2. В *System Settings → Privacy & Security → Accessibility* разрешить
   приложение (перетащить из Finder, если не появилось само), перезапустить.
3. В TextEdit набрать `ghbdtn` (рус. раскладка) → пробел → слово конвертируется
   в `привет`, раскладка переключается, слышен звук.
4. Набрать `привет` в русской раскладке → пробел → конвертации **нет**
   (слово корректное для своей раскладки).
5. **Cmd+`** — ручное переключение раскладки без автоконвертации.
6. После автоконвертации нажать **Option+`** — слово возвращается в исходную
   раскладку.
7. Меню иконки: Toggle Autocorrection отключает автоконвертацию, Quit
   завершает приложение.
8. Перезапуск приложения — настройки (например, выключенная автоконвертация)
   сохраняются.

## Development

```sh
swift build          # отладочная сборка
swift test           # 33 теста Engine + Platform (7 suites)
swift build -c release
./Scripts/package-app.sh   # собирает build/FreentoSwitcher.app, ad-hoc подпись
```

Требуется macOS 14+, Swift 6, Xcode Command Line Tools.

## Установка / Installation

### Сборка из исходников / Build from source

Требуется: macOS 14+, Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/Glukmann/FreentoSwitcher.git
cd FreentoSwitcher
swift build -c release
```

### Готовая сборка / Prebuilt release

Скачайте `FreentoSwitcher.dmg` из [Releases](../../releases).
Приложение подписано ad-hoc (без сертификата Apple Developer). При первом запуске:
правый клик по приложению → «Открыть» → «Всё равно открыть».
Или в терминале: `xattr -cr /Applications/FreentoSwitcher.app`

## Лицензия / License

MIT, см. [LICENSE](LICENSE). Софт предоставляется «как есть» (as is),
без гарантий любого рода — используйте на свой страх и риск.
