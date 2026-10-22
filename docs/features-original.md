# PuntoSwitcher 2.1.5 — полный список функций (восстановлен REA+Ghidra)

Источник: `/Applications/PuntoSwitcher.app` (x86_64, Obj-C + C++-ядро).
Адреса — image base 0x100000000. Псевдокод Ghidra.

## A. Ядро переключения раскладок (основное назначение)

| # | Функция | Доказательство |
|---|---------|----------------|
| A1 | Глобальный перехват клавиатуры и мыши через `CGEventTap` (keyDown/keyUp/sysKeyDown, клики) | `PuntoSwitcherCore::eventTapCreate` @0x10003d4af, `processKeyEvent:eventType:` @0x10003d7b7, `processMouseEvent:...` @0x100041b68 |
| A2 | Ручное переключение RU↔EN по хоткею через `TISInputSource.setActive` | `PuntoInputSourcesManager::switchLanguage` @0x10003c5c1 |
| A3 | Автоконвертация слова по разделителю (пробел/Tab/Enter/пунктуация): буфер keystrokes (до 32 симв.) виртуально перекодируется, проверяется по словарю; при совпадении — системная смена раскладки, стирание слова backspace'ами (`pressKey:0x33`), реплей нажатий (`postEventsFromBuffer`) | `autocorrectWordLayout:withEvent:` @0x10003e80e, `processKeyEvent:` @0x10003d7b7 |
| A4 | Автоконвертация частичного слова «на лету» по триггер-словам (`triggers.dat`, 4513 слов) | `autocorrectPartialWordLayout` @0x10003f411 |
| A5 | Проверка «неверная раскладка»: триггеры + пользовательский словарь + правила (regex), коды 2/4/8; режимы старых правил (таблицы `ps.dat`) и нового C++ чекера | `ConversionEngine::*` @0x100035d3e–0x1000398d1 |
| A6 | Конвертация строки между раскладками: 4 таблицы US_RUMAC / US_RUPC / RUMAC_US / RUPC_US (Apple vs PC-раскладки) | `convertStringLayout:withMode:isPCLayout:` @0x1000374e5 |
| A7 | Смена раскладки выделенного текста по хоткею: чтение выделения, пословная конвертация, замена через буфер обмена; опция «переключать системную раскладку» (`switchLayoutOnSelectedTextSwitch`) | `switchSelectionLayout:` @0x100042a07, `processSelectedTextWithMethod:` @0x100043295 |
| A8 | Смена регистра выделенного текста (ВЕРХНИЙ↔нижний) | `switchSelectionCase:` @0x100042fe5 |
| A9 | Отмена последней конвертации (undo) по отдельному хоткею; повторное нажатие — «постоянная» отмена с обучением словаря отмен (`PuntoUndoManager`, `undoLearning`) | `undoConvertion` @0x100040fc5 |
| A10 | Отмена автоконвертации следующего слова после ручного переключения (`shouldCancelNextWordConvertation`, `shouldNotAutoconvertAfterConvertion`) | `processKeyEvent:` @0x10003d7b7 |
| A11 | Опция «не конвертировать после Tab/Enter» (`shouldNotAutoconvertWithTabOrEnter`) | @0x10003d7b7 |
| A12 | Особое поведение в Apple Mail (не выделять/стирать слово иначе) | `applyMailBehaviourForFullWords:...` @0x1000421fd, `applyMailBehaviourForPartialWords:` @0x100041fee |
| A13 | Звуки: переключение RU→EN / EN→RU (разные), автоконвертация, undo, выделение; маска `enabledSounds`, `isSoundOn` | `SoundManager`, playSound:0x80/0x100/0x20/0x40/0x10 |
| A14 | Запоминание раскладки на приложение: словарь bundleID→inputSource, восстановление при активации окна | `ApplicationLayoutsManager::*` @0x1000350e0–0x100035cfb |
| A15 | Список исключённых приложений + опция «полностью отключать в исключениях» (`disabledApps`, `CompletelyDisableInExceptionApps`) | @0x100035acf, настройки plist |
| A16 | Выбор раскладок RU/EN из системных (incl. guessLayout, promptUserToInstallLayouts), поддержка Apple/PC-вариантов и Dvorak-фильтра | `PuntoInputSourcesManager::*` @0x10003b36a–0x10003cfa0 |
| A17 | Синтез клавиш: `CGEventCreateKeyboardEvent` + `CGEventPost(CGSessionEventTap)`; pressKey / pressKeyCombination (Cmd/Opt) | `pressKey:` @0x10003cb27, `postEvent:` @0x10003cdcd |
| A18 | Обработка Backspace (0x33), Esc (0x35 = сброс буферов), двойной пробел/прочие keycode-особенности; подавление собственных синтезированных событий (`suppresEvent`) | `processKeyEvent:` @0x10003d7b7 |
| A19 | Проверка secure input (`IsSecureEventInputEnabled`), обход ScreenSaver | `switchLanguage` @0x10003c5c1, `processKeyEvent:` |
| A20 | Пользовательские правила: слова-исключения/включения с regex, UI редактирования (UserRuleSheet) | `userRulesDictionary` (plist), `addUserRuleWithString:...` |

## B. Accessibility-слой (обход ограничений браузеров и нестандартных приложений)

| # | Функция | Доказательство |
|---|---------|----------------|
| B1 | Определение фокуса в текстовом поле через AX API (`isFocusedWindowTextField`) | @0x100034d91 |
| B2 | Детектор «набор идёт в текстовом поле» — управляет исключениями и автоактивацией | `PSTextFieldTypingDetector::handleKeypress:` @0x10002f087 |
| B3 | AccessibilityObserver + PSObservationController: per-app наблюдатели, focusedElementRole | классы, @0x10002f087 |
| B4 | Три typing-контекста: Naive / Accessibility / Combined (выбор стратегии определения слова) | `PSNaiveTypingContext`, `PSAccessibilityTypingContext`, `PSCombinedTypingContext` |
| B5 | `selectedText` через AX (проверка выделения перед стиранием слова) | `AccessibilityController::selectedText` @0x100034b17 |
| B6 | Конфиг исключений по AX-ролям для браузеров/приложений (`default-conf.json`: search.bar/search.click exceptions, eui/inject списки) | ресурс default-conf.json |
| B7 | Помощник AppleScript для открытия панели «Универсальный доступ» | `showAccesibilityPrefPane*.spt` |

## C. Меню-бар, настройки, окна

| # | Функция | Доказательство |
|---|---------|----------------|
| C1 | Agent-приложение без Dock (NSUIElement=1), иконки статуса active/inactive/disabled | `MenubarController`, Info.plist |
| C2 | Окно настроек, 7 панелей: Общие / Горячие клавиши / Звуки / Поиск / Правила пользователя / Исключённые приложения / Обновления | `*PreferencesPaneController` |
| C3 | Редактор хоткеев с перехватом нажатий (ShortcutField со своим event tap) | `ShortcutField::eventTapCreate` @0x1000342df |
| C4 | Окна: Welcome (онбординг + доступность), Undo, About, Updater | `*WindowController`, ru.lproj/*.nib |
| C5 | Запуск при входе (`launchesOnStartup`) | `LaunchAtLoginController` |
| C6 | Обучение отмене конвертации (undo window + undoDictionary) | `undo_learning` (plist) |

## D. Яндекс-специфика (предлагается ИСКЛЮЧИТЬ из клона)

| # | Функция | Доказательство |
|---|---------|----------------|
| D1 | Телеметрия: счётчики набора (символы/слова/переключения), clicker, поисковая строка; UUID устройства | `PSDayuseStat` (1 448 020 симв. у юзера), `PSClickerStat`, `PSCompoundStat`, `PSStatService` |
| D2 | Хоткеи «Найти в Яндексе» / «Найти в Словарях» выделенного текста (clid=141986 — монетизация) | `processSelectedTextWithYandex` @0x100043408, строки yandsearch |
| D3 | Поисковая строка с подсказками suggest.yandex.ru, геолокация api.lbs.yandex.net | классы YSB* |
| D4 | Click-search: поиск по клику с модификатором | `processMouseEvent:`, `isClickSearch` |
| D5 | Удалённая конфигурация с download.yandex.ru/punto/config (команды серверу: shouldEraseOnReturnIn и др.) | `PSRemoteConfiguration` |
| D6 | Автообновление с серверов Яндекса | `PSUpdater`, `download.yandex.ru` |
| D7 | Счётчики yandex.ru/clck | строки бинарника |

## E. Инфраструктура (техническая, входит в пересборку по необходимости)

- Логирование CocoaLumberjack (DD*) — заменить os_log
- AFNetworking/SBJson — только для D-блока, не нужны
- Ресурсы: звуки (en.wav + дефолтные), иконки статуса, шрифты

## Пользовательские настройки (ru.yandex.punto.plist)

englishLayoutID, russianLayoutID, shortcutChangeLayout, shortcutCancelLayoutChange,
shortcutChangeCase, shortcutFindInSlovari, shortcutFindInYandex, shortcutSwitchAutocorrection,
isAutocorrectionActive, shouldNotAutoconvertAfterConvertion, shouldNotAutoconvertWithTabOrEnter,
shouldRememberInputSourceForEachApp, switchLayoutOnSelectedTextSwitch,
CompletelyDisableInExceptionApps, disabledApps[], enabledSounds (маска), isSoundOn,
launchesOnStartup, shouldCheckForUpdatesAutomatically, userRulesDictionary[],
undo_learning{undoDictionary}, configVersion.

## Данные

- `ps.dat` 286 КБ, 37749 записей — таблицы перекодировки символов (старые правила)
- `triggers.dat` 4513 слов (mac-cyrillic, как физические клавиши) — триггеры автоконвертации
- `default-conf.json` — AX-исключения (браузеры и спецприложения)
