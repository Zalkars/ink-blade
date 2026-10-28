# Ink Blade — Godot-порт (Windows + Android)

Полный 1:1 порт игры Ink Blade (C#/WinForms/SkiaSharp, `InkBladeWin/ink-blade-main`)
на Godot 4. Откройте эту папку в Godot 4.5+ (GL Compatibility) и запустите `main.tscn`.

## Архитектура

Внутреннее разрешение — 1280×720 (stretch `canvas_items`, aspect `ignore`),
холст заполняет весь экран без боковых рамок, а сенсорные координаты учитывают
масштабирование по ширине и высоте,
ориентация `sensor_landscape` на Android.
FloorY = 620, спавн игрока (300, 574). На Android включена
`sensor_landscape`-ориентация (orientation = 4) и immersive mode.

### Чернильный рендер — `scripts/ink.gd` (автокласс `InkR`)

Всё рисование идёт через статический класс `InkR` — прямой аналог `Ink.cs`:
`text / line / poly / fill_poly / rect / blob / circle / arc / taper_arc /
ellipse_shadow / hatch / radial_glow / radial_rect / paper / stage / title /
vignette` и т.д. Важно: аргументы позиционные, как в оригинале, например
`text(s, x, y, size, font_kind, align, color2, a, spacing, ghost, baseline)`.

Палец-джиттер, «звёздный» шум и dash-линии совпадают с C# версией;
seed = `xorshift32((n*2654435761) ^ (boil*0x9e3779b1))`, где `boil = int(realTime*10)`.

### Запекание статики

Большие статичные картинки запекаются через `SubViewport` + `InkBakeNode`
(`bake_node.gd`, поля `w/h` и `fn: Callable`), порядок критичен:

1. `paper` (1280×720);
2. `stage` (1480×900, PAD=80 — داخل `InkWorld.bake_stage`, включая пыль);
3. `title` (1280×720, рисует поверх tex_paper).

Каждое запекание ждёт два `RenderingServer.frame_post_draw`, затем читает
`get_image()` и создаёт `ImageTexture`.

### Автолоады

- `L10N` (`i18n.gd`) — локализация: JSON-словари из `locale/`, `t(key, args)`,
  `next_lang()`, `set_lang()`, `lang_name()`, `audit()`. Новый язык — это новый
  файл, правки кода не нужны.
- `SND` (`audio_ink.gd`) — порт `Audio.cs`: синтез на `AudioStreamGenerator`
  (22050 Гц), класс `SNDCore`, voice-и (tone/noise), ambient drone + wind,
  `ui()`/`ui_confirm()`/`hit()`/`unlock()`/`set_muted()`.
- `CTL` (`input_ink.gd`) — порт `Input.cs`: собственный ввод без Input Map,
  класс `INKCtl`. `CTL.update(dt)` вызывается один раз за кадр, все подшаги
  симуляции (шаги ≤ 1/120 с guard < 10) видят одни и те же edges.

  - Клавиатура — прямая таблица `KEYBOARD`.
  - Геймпад: XInput→Godot маппинг через
    `PAD_BUTTON_JOY = [0,1,2,3,9,10,-1,-2,4,6,7,8,11,12,13,14]`
    (-1 = LT ось 4, -2 = RT ось 5), данные прямым опросом `Input`,
    deadzone 0.32 c ремапом; вибрация — `start_joy_vibration` + `vibrate_handheld`.
  - Тач: зоны `TOUCH_ZONES`/`TOUCH_LABELS` единый источник в `game.gd`,
    multitouch по pointer-id; для UI-навигации — `CTL.touch_tap(action)`
    (отложенный edge), удержание — `touch_enter/touch_exit` с refcount.

### Локализация

Все строки интерфейса — в `locale/*.json` с полями `name` (название языка на
нём самом), `order` (порядок в переключателе) и `strings` (ключ → текст).
Автолоад `L10N` сканирует каталог при запуске, поэтому для нового языка
достаточно скопировать `ru.json` в `<код>.json` и перевести значения.

Если ключ пропущен, берётся русский вариант; в debug-сборке печатается
предупреждение, полный отчёт даёт `L10N.audit()`. Выбор языка хранится в
`user://settings.cfg` (`[locale] lang`). После смены языка `game.gd`
перезапекает `stage` и `title` — в этих слоях есть текст. В обоих пресетах
экспорта прописан `include_filter="locale/*.json"`, иначе JSON не попадёт в
PCK.

### Игровые скрипты

- `game.gd` — порт `Game.cs`: состояния title/play/paused/dead, combat
  (pogo, дефлект снарядов, хитстоп), hazard-телепорт, комбо, баннер, экраны
  паузы/управления/смерти/отладки, оркестрация запекания, тач-UI.
- `world.gd` (`InkWorld`) — физика, платформы, hazard-зона, свечи, пыль,
  трава и `bake_stage`.
- `player.gd` (`InkPlayer`) — порт `Player.cs`.
- `enemy_base.gd` + `grunt/sentry/dummy/enemy_bolt` — враги; у подклассов
  метод называется `draw()` (не `_draw()`).
- `hud.gd` (`InkHud`) — душа, рывок, комбо, баннер, подсказки, панели.
- `fx.gd` (`InkFx`) — частицы, спарки, кольца, shake/flash/damage-оверлеи.

## Управление

Клавиатура: A/D — движение, Пробел/Z — прыжок, J/X — атака, K/SHIFT — рывок,
L/V — лечение, ESC — пауза, ENTER — подтверждение, R — заново, M — звук,
F1 — управление, F2 — хитбоксы, F11 — полный экран, F12 — скриншот.
Геймпад: стик — движение, A/X/B/Y, LB/RB/LT/RT, START/BACK.
Тач: плавающий стик слева и большие виртуальные кнопки A/X/B/Y, Ⅱ справа.
Сенсорные зоны работают с несколькими пальцами одновременно, автоматически
переводятся из координат окна в логический холст 1280×720 и остаются доступны
на титульном экране, в паузе, в окне управления и после смерти.

## Экспорт

Пресеты в `export_presets.cfg`: Windows (`builds/InkBlade-Windows.exe`) и
Android debug APK (arm64 + armeabi-v7a, пакет `org.inkblade.game`,
разрешение VIBRATE). Готовый проверенный debug APK лежит в
`../builds/InkBlade-debug.apk`. Для публикации нужен release keystore и AAB.
