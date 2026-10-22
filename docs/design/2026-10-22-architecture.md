# FreentoSwitcher — дизайн-документ (2026-10-22)

## 1. Цель и рамки

Open-source замена PuntoSwitcher 2.1.5 для macOS arm64. Воспроизводим полный
функционал ядра (A), Accessibility-слоя (B) и UI (C) по `docs/features-original.md`.
Яндекс-специфика (телеметрия, поисковые хоткеи, YSB, remote config) — исключена.
Словари и данные — собственные, из открытых источников. Распространение —
GitHub Releases, ad-hoc подпись, MIT.

## 2. Стек

Swift 6 (строгая конкурентность: `Sendable`, акторы где уместно), SwiftPM,
AppKit (статус-бар, окна), SwiftUI (панели настроек), XCTest.
Сборка релизов — GitHub Actions (macos runner), упаковка в .dmg.

## 3. Архитектура: три слоя

```
┌─────────────────────────────── App (executable) ──────────────────────────────┐
│ StatusBarController · SettingsWindow (SwiftUI, 7 панелей) · Welcome/Undo/About │
│ LaunchAtLogin (SMAppService) · Updater (GitHub Releases)                      │
├────────────────────────────── Platform (SPM target) ──────────────────────────┤
│ EventTap (CGEventTap) · InputSourceManager (TIS) · AccessibilityController    │
│ EventSynth (CGEventPost) · TypingDetector (AX-роли)                           │
├────────────────────────────── Engine (SPM target, чистый Swift) ──────────────┤
│ KeyStrokeBuffer · ConversionEngine (таблицы) · LayoutChecker (словари/правила)│
│ WordDetector (разделители) · UndoManager · SettingsModel (типизированные)     │
└───────────────────────────────────────────────────────────────────────────────┘
```

**Engine не импортирует AppKit** — только Foundation. Полностью юнит-тестируется
без UI и event tap. Platform/App — тонкие, обмен через Engine API.

## 4. Engine — компоненты

- `KeyStrokeBuffer` — массив `KeyStroke{keycode, modifiers, layout}` (до 32),
  операции добавления/удаления, `stringValue` (перекодировка через текущую layout
  буфера), подсчёт пунктуации.
- `ConversionEngine` — 4 таблицы символьных пар (RU_MAC↔US, RU_PC↔US).
  Таблицы генерируются механически из системных раскладок (UCKeyTranslate по
  всем keycode×modifiers) — не копируются из оригинала, выводятся из фактов ОС.
  `convert(_:mode:isPCLayout:)` — посимвольно, символы вне таблицы сохраняются.
- `LayoutChecker` — возвращает enum {unknown, incorrect, exception}:
  1. пользовательский словарь (исключения/включения, regex-правила);
  2. триггер-слова (свой словарь из открытого корпуса);
  3. эвристики регистра/состава (`isStringUppercase`, тип строки).
- `WordDetector` — определяет завершение слова: пробел, Tab, Enter, знаки
  препинания-разделители; управляет raw/undo буферами (правила A10–A12).
- `UndoManager` — undo-буфер, «постоянная» отмена, словарь обучения отмен.
- `SettingsModel` — типизированные настройки (см. §8), Codable, дефолты.

## 5. Platform — компоненты

- `EventTap` — `CGEventTapCreate` на keyDown/keyUp/sysKeyDown + mouse,
  listen-only tap; фильтр собственных синтезированных событий (source ID);
  передача событий в Engine-оркестратор; отключение при secure event input.
- `InputSourceManager` — TIS: текущая раскладка, перечень RU/EN-раскладок,
  `switchLanguage()`, запоминание раскладки на приложение (словарь bundleID→ID),
  отслеживание изменений (distributed notifications).
- `AccessibilityController` — фокус в текстовом поле, выделенный текст
  (AXSelectedText), наблюдатели per-app, роли элементов; конфиг AX-исключений
  (свой формат, аналогичный по смыслу default-conf.json).
- `EventSynth` — `pressKey(_:)`, `pressKeyCombination(_:key:)` через
  CGEventSource + CGEventPost(tap: .cghidEventTap).
- `TypingDetector` — `lastKeystrokeInTextField` для исключений и автоправил.

## 6. App — компоненты

- `StatusBarController` — NSStatusItem, три состояния (active/inactive/disabled),
  меню: переключить раскладку, отменить, настройки, о программе, выход.
- `SettingsWindow` — SwiftUI, панели: Общие / Горячие клавиши (свой capture) /
  Звуки / Правила / Исключённые приложения / Обновления.
- `WelcomeWindow` — онбординг: запрос доступности (AXIsProcessTrustedWithOptions),
  выбор раскладок RU/EN.
- `UndoWindow` — обучение отмене (повторное нажатие undo).
- `LaunchAtLogin` — SMAppService (современный API, без устаревшего LSSharedFileList).
- `Updater` — **Sparkle 2.x**: проверка обновлений, скачивание .dmg, подпись
  релизов EdDSA, канал «stable» по тегам `v*`.

## 7. Ключевые потоки

**Автоконвертация слова (A3):** keyDown → буфер += keystroke → разделитель →
`LayoutChecker.check(buffer)` → если incorrect: switchLanguage → стирание слова
(N×backspace) → replay буфера через EventSynth → звук, undo-копия.
Если unknown/exception — буфер сбрасывается, событие проходит как есть.

**Undo (A9):** по хоткею — восстановление undo-буфера (обратная конвертация,
replay), повторное нажатие → регистрация в словаре обучения отмен.

**Конвертация выделения (A7/A8):** selectedText через AX → пословная конвертация
→ замена через NSPasteboard + Cmd-V (как оригинал) → опционально switchLanguage.

## 8. Настройки

UserDefaults (JSON-backed, наша схема `configVersion=1`): раскладки RU/EN,
4 хоткея: переключение раскладки (в т.ч. выделенного текста), отмена конвертации,
смена регистра выделения, вкл/выкл автокоррекции (поисковых хоткеев нет),
звуки (битовая маска: переключение RU→EN, EN→RU, автоконвертация, undo,
конвертация выделения), автокоррекция (on/off,
не конвертировать после ручного переключения, не после Tab/Enter), раскладка
на приложение (on/off), исключённые приложения, пользовательские правила,
запуск при входе, автообновление (on/off), показ расширенных настроек.

## 9. Данные

- `triggers.txt` — свой список триггер-слов (генератор: открытый корпус
  (OpenCorpora), критерии: короткие слова с однозначной двухраскладочной
  диагностикой). Генератор — отдельный инструмент в `Tools/DictionaryGenerator`.
- Mapping-таблицы — генерируются при сборке/первом запуске из системных
  раскладок пользователя (Apple/PC варианты, Dvorak-исключения).
- AX-исключения — свой `ax-exceptions.json`, список приложений сокращён до
  актуальных (браузеры), расширяемый пользователем.

## 10. Отличия от оригинала (сознательные)

- Нет телеметрии вообще; нет сети, кроме Updater'а (по opt-in).
- Словари свои; формат данных свой; настройки — новая схема (миграция из
  оригинала не планируется, импорт настроек — nice-to-have позже).
- SMAppService вместо LSSharedFileList; Sparkle/свой апдейтер вместо PSUpdater.
- Swift strict concurrency, нет ручного управления памятью.
- Кодировка данных: UTF-8 (в оригинале — legacy mac-cyrillic).

## 11. Тестирование

- Engine: XCTest — конвертация (таблицы), LayoutChecker (словари/правила/regex),
  WordDetector (разделители, A10–A12), UndoManager, сериализация настроек.
  Плюс golden-файлы: примеры слов «верная/неверная раскладка».
- Platform: ручной чек-лист (event tap в целевых приложениях: Safari, Chrome,
  Telegram, Mail, Xcode, терминал).
- Сборка: `swift build` + `swift test` в CI на каждый PR; релизный workflow
  собирает .dmg и публикует Release.

## 12. Риски

- **CGEventTap требует Accessibility-доступ** — онбординг должен чётко вести
  пользователя в настройки системы.
- Replay через синтез клавиш может конфликтовать с некоторыми приложениями —
  покрываем AX-исключениями (слой B).
- Парольные поля (secure input) — обязательная проверка `IsSecureEventInputEnabled`.
