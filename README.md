# FreentoSwitcher

Открытая замена PuntoSwitcher для macOS на Apple Silicon (arm64).
Переключение раскладки, автоконвертация слов, набранных в неверной раскладке.

Open-source replacement for the discontinued PuntoSwitcher on Apple Silicon macOS.
Keyboard layout switching and automatic correction of words typed in a wrong layout.

**Не аффилировано с Яндексом. Все словари и данные собраны заново из открытых источников.**
**Not affiliated with Yandex. All dictionaries are rebuilt from open data.**

## Статус / Status

🚧 В активной разработке. Первый релиз ещё не вышел.

## Установка / Installation

### Сборка из исходников / Build from source

Требуется: macOS 13+, Xcode Command Line Tools (`xcode-select --install`).

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
