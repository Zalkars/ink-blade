# Шрифты

## Что было

`ink.gd` принимал `font_kind`, но игнорировал его: все шесть видов рисовались одним `ThemeDB.fallback_font`. В C#-версии (`native/InkBlade/Core/Ink.cs`) использовались системные шрифты:

| Вид | C#-версия | Начертание |
|---|---|---|
| `F_TITLE` | Georgia | Bold Italic |
| `F_DISPLAY` | Palatino Linotype | Bold |
| `F_BODY` | Georgia | Regular |
| `F_BOLD` | Georgia | Bold |
| `F_ITALIC` | Georgia | Italic |
| `F_HAND` | Segoe Script | Regular |

Все они проприетарные (Microsoft), в поставку их класть нельзя — особенно в Android-сборку, где их просто нет.

## Что стало

В `godot/assets/fonts/` лежат свободные аналоги под лицензией SIL OFL 1.1, с полной кириллицей:

| Файл | Заменяет | Лицензия |
|---|---|---|
| `PTSerif-Regular.ttf` | Georgia Regular | OFL 1.1 |
| `PTSerif-Bold.ttf` | Georgia Bold, Palatino Bold | OFL 1.1 |
| `PTSerif-Italic.ttf` | Georgia Italic | OFL 1.1 |
| `PTSerif-BoldItalic.ttf` | Georgia Bold Italic (заголовок) | OFL 1.1 |
| `MarckScript-Regular.ttf` | Segoe Script (рукописный) | OFL 1.1 |

Тексты лицензий: `OFL-PTSerif.txt`, `OFL-MarckScript.txt`. Их нужно оставлять рядом со шрифтами при поставке.

PT Serif выбран вместо метрически совместимого с Georgia Gelasio, потому что у Gelasio нет кириллицы. PT Serif — «книжная» антиква с полным русским набором, по пропорциям ближе к Georgia, чем системный DejaVu.

## Как это устроено в коде

В `ink.gd`:

```gdscript
const FONT_TITLE := preload("res://assets/fonts/PTSerif-BoldItalic.ttf")
...
static func font_for(kind: int) -> Font
```

`text()` и `measure_text()` берут шрифт по `font_kind`. Замена шрифта — правка одной строки в блоке констант.

## Как заменить шрифт

1. Положить `.ttf`/`.otf` в `godot/assets/fonts/`.
2. Прогнать импорт: `Godot --headless --path godot --import`.
3. Поменять путь в константе `FONT_*`.
4. Проверить кириллицу: в шрифте должны быть глифы `А–я`, `Ё`, `ё`.
5. Проверить лицензию: для коммерческой поставки подходит OFL, Apache 2.0, CC0. Системные шрифты Windows — нельзя.

## Что осталось

- Подписи в HUD и подсказки проверены глазами; при смене шрифта нужно перепроверить переносы и центровку.
- `measure_text()` без `font_kind` меряет основным шрифтом. Для заголовков лучше передавать вид явно — сейчас это делается только внутри `text()`.
