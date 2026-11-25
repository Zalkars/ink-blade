# Схема контента

**Статус:** конвейер и headless-валидатор реализованы в 0.5.0.
**Связано:** `docs/tech-brief.md`

Задача схемы: новый враг, проп или уровень добавляется **данными**, без правки игрового кода.

---

## 1. Общие правила

1. **Карточки врагов, оружия и пропов — `.tres` (Resource).** Они читаются инспектором Godot.
2. **Сохранения — JSON** в `user://saves/`. Легко отлаживать, версионировать, мигрировать.
3. **Уровни, индекс, локали, диалоги и катсцены** — JSON.
4. **ID неизменяемы.** Ссылки в уровнях и сохранениях — только на ID, никогда на пути нод или индексы.
5. **Один загрузчик.** Редактор, рантайм и валидатор читают одну и ту же схему.

---

## 2. ID

Формат: `категория.имя`, нижний регистр, латиница, точка-разделитель.

```
enemy.grunt
enemy.sentry
boss.warden
prop.column
prop.ink_gate
trigger.dialogue
pickup.health
level.ch01_01
```

Правила:

- ID не переиспользуется даже после удаления объекта.
- Переименование → запись в `content/aliases.tres`: `enemy.old → enemy.new`. Загрузчик резолвит алиасы, сохранения продолжают работать.
- Дубликат ID — ошибка валидации, сборка падает.

---

## 3. `EntityDef` — карточка врага/объекта

| Поле | Тип | Назначение |
|---|---|---|
| `id` | `StringName` | Уникальный ID |
| `display_name_key` | `String` | Ключ локализации, `entity.grunt.name` |
| `category` | `enum` | `enemy`, `boss`, `prop`, `trigger`, `pickup` |
| `scene` | `PackedScene` | Что создавать в мире |
| `icon` | `Texture2D` | Иконка для палитры и редактора |
| `tags` | `PackedStringArray` | `ground`, `flying`, `armored`, `save_state` |
| `stats` | `EntityStats` | HP, урон, скорость, радиус агрессии, время телеграфа |
| `ai_profile` | `AIProfile` | Тип поведения и его параметры |
| `loot` | `Array[LootEntry]` | Что выпадает |
| `sfx` | `Dictionary` | Звуки: атака, урон, смерть |
| `vfx` | `Dictionary` | Эффекты: телеграф, удар, смерть |
| `flags` | `Dictionary` | `persistent`, `blocks_path`, `participates_in_save` |
| `version` | `int` | Версия карточки |

Принцип: `scene` — **сцена из компонентов** (`Health`, `Hurtbox`, `Hitbox`, `Movement`, `AIController`, `Loot`, `Audio`, `VFX`), а не класс-наследник. Новый враг = другая комбинация компонентов + другая карточка.

Шаблоны сцен: наземный, летающий, турель, босс. Новые враги делаются дублированием шаблона.

Необязательные поля `EntityStats` из 0.6: `poise`, `ink_reward`, `parryable_melee`, `parryable_projectile`, `armor`, `shield_arc`, `contact_damage`. Значения по умолчанию (`0`, `true`, `0.0`) сохраняют поведение старых карточек. `AIProfile.Kind` получает новые роли только в конец enum: `SHIELDER=5`, `DISRUPTOR=6`, `DUELIST=7`, `BURROWER=8`, `TANK=9`, `TRAP=10`; значения `CHASER=1`…`BOSS=4` не сдвигаются.

---

## 4. `PropDef` — пикапы

Карточка `content/props/*.tres` задаёт `id`, `kind`, `scene`, `version`, `display_name_key`, `soul_amount`, `amount` и `payload`. `PDB` читает карточки из папки при работе с исходниками и из манифеста в экспорте. Новый экземпляр задаётся в `props` уровня как объект с `id`, `def_id`, `x`, `y`.

`kind` остаётся строкой. Допустимые значения: `pickup` (старый осколок души), `heart_shard`, `ink_vessel`, `mark`, `name`, `weapon`, `key`. Для `mark`, `name`, `weapon` и `key` обязателен `payload` — ID пометки, имени, оружия или ключа. Для `pickup` проверяется `soul_amount` (1–99); у остальных видов поле игнорируется. `amount` задаёт количество и должен быть не меньше 1.

`id` экземпляра уникален внутри `props` уровня. Сохранение запоминает его после подбора, поэтому при перемещении предмета сохраняйте тот же ID. `prop.soul_shard` добавляет до 10 чернил с текущим пределом игрока (база 100).

---

## 5. `LevelData` — уровень

`content/levels/index.json` содержит `version: 1`, `first` и массив `levels`. Каждая запись указывает `id`, `scene`, `data`, целочисленный `order` и необязательный `qa_only`. `LVL` загружает записи в `LevelData` и предоставляет `get_level(id)`, `ids()`, `first_id()` и `has(id)`.

Сцена-обёртка на `Level` задаёт тот же `data_path`. JSON уровня содержит `version: 1`, тот же `id`, `bounds` для камеры, `spawn`, тайлы, чекпоинты, врагов и необязательные триггеры и пропы. Для названия можно дать `display_name_key` из обеих локалей или строку `name`.

### Интерактивные связи

| Секция | Дополнительные поля к стабильному `id`, `x`, `y` |
|---|---|
| `doors` | `w`, `h`. Координаты указывают на середину основания двери |
| `switches` | `targets`, массив локальных ID дверей |
| `entries` | Точка прибытия по ногам |
| `exits` | `level`, необязательный `entry` и массив локальных условий `requires` |

У финиша авторского маршрута есть `finish: true` и необязательный `requires`. Поля `level` и `entry` у финиша отсутствуют или пусты. Для встроенной сюжетной карты `next_chapter` задаёт следующую главу, а `finale_cutscene` переопределяет ID ролика. Пустая строка открывает окно завершения сразу.

Обмен картами использует обычный JSON уровня или пакет `{"format":"ink-blade-levels","version":1,"root":"room_a","rooms":[...]}`. `root` указывает стартовую комнату, `rooms` содержит полные JSON каждой достижимой комнаты. Пакет может содержать до 24 комнат и должен занимать меньше 4 МБ. Все переходы пакета замкнуты внутри него. Состояние игрока и сейвы в пакет не входят.

У побочной комнаты можно задать `story_finale: false`, чтобы устранение всех врагов оставляло игрока исследовать карту. Сохранение v7 хранит активированные рычаги и состояние посещённых комнат. См. [схему сохранений](saves.md).

### `Placement`

| Поле | Тип | Назначение |
|---|---|---|
| `id` | `String` | Локальный стабильный ID внутри уровня: по нему сохранение помнит убитых |
| `def_id` | `StringName` | Ссылка на карточку по ID |
| `position` | `Vector2` | Где стоит |
| `rotation`, `flip` | `float`, `bool` | Ориентация |
| `overrides` | `Dictionary` | Переопределения полей конкретного экземпляра |

`id` у спавна обязателен для всего, что может исчезнуть из мира. Сохранение хранит список убитых ID, поэтому перенос врага в другое место не «оживляет» его и не путает прогресс.

Чекпоинт в JSON каркаса — `{ "id": "cp_mid", "x": 1300, "y": 600 }`, координаты по ногам. Касание лечит игрока и пишет автосейв; после смерти он появляется здесь.

`def_id` строкой, а не прямой ссылкой на ресурс: уровень остаётся валидируемым, переименование файла не ломает данные, отсутствующая карточка ловится валидатором.

### `Trigger`

| Поле | Тип | Назначение |
|---|---|---|
| `id` | `String` | Стабильный ID, попадает в сохранение |
| `x`, `y` | `float` | Где стоит NPC и где срабатывает сцена |
| `dialogue` | `String` | ID файла из `content/dialogue` |
| `npc` | `String` | Кого нарисовать: `scribe` — Переписчик |

Триггер срабатывает один раз, когда игрок доходит до `x`. Уровень только шлёт сигнал `trigger_reached`, а `game_flow` решает, что показать: диалог, катсцену или ничего. Уровень не знает про UI и локализацию.

### Диалог и катсцена

Сценарии лежат отдельно от кода и от текста:

```json
// content/dialogue/archivist.json
{
  "version": 1,
  "id": "archivist",
  "lines": [
    { "speaker": "dialogue.archivist.name", "text": "dialogue.archivist.1" },
    { "speaker": "dialogue.archivist.name", "text": "dialogue.archivist.2" }
  ],
  "grant": "weapon.brush"
}
```

```json
// content/cutscenes/intro.json
{
  "version": 1,
  "id": "intro",
  "slides": [
    { "text": "cutscene.intro.1", "art": "city" },
    { "text": "cutscene.intro.2", "art": "ink" }
  ]
}
```

| Поле | Что значит |
|---|---|
| `lines[].speaker` | Ключ локализации с именем говорящего |
| `lines[].text` | Ключ локализации с репликой |
| `grant` | ID карточки оружия, которое выдаётся после разговора |
| `slides[].text` | Ключ локализации со строкой слайда |
| `slides[].art` | Имя процедурной картинки: `city`, `ink`, `blade`, `hall`, `pen` |

Текст никогда не лежит в JSON сценария: там только ключи. Поэтому перевод добавляется без правки сценария, а сценарий — без правки перевода.

Диалог и катсцена живут в `CanvasLayer` с `process_mode = ALWAYS`, ставят дерево на паузу и возвращают состояние `PLAY` по сигналу `finished`. Управление в мир в это время не уходит.

`overrides` — только по вайтлисту полей, объявленному в карточке. Иначе через год никто не поймёт, почему конкретный враг на конкретном уровне ведёт себя иначе.

---

## 6. `EntityDatabase` — каталог

API:

```
get_def(id) -> EntityDef
has(id) -> bool
all(category) -> Array[EntityDef]
instantiate(id, overrides) -> Node
```

Источник данных:

- **в редакторе и при обычном запуске** — папка `res://content/entities`;
- **в экспортированной сборке** — сгенерированный `content/manifest.json` (`id → path → type → hash`).

Сканировать `res://` через `DirAccess` в экспортированном PCK нельзя — поведение отличается от редактора, поэтому в билде источником становится манифест.

### Оружие

Оружие — такие же карточки, но отдельного типа `WeaponDef` и отдельного каталога `WDB`:

```
id: StringName                 # weapon.blade
display_name_key: String       # ключ локализации
order: int                     # порядок переключения
damage: int
windup / active / cooldown: float
reach: Vector2
knockback: float
hit_both_sides: bool
heavy_damage: int
heavy_windup / heavy_active / heavy_cooldown: float
heavy_reach: Vector2
heavy_ink_cost: int
heavy_pierce: int
heavy_marks: bool
ranged: bool
projectile_scene: PackedScene
projectile_speed: float
ink_cost: int
pierce: int
ink: Color
swing_radius / swing_width: float
```

Группа «Тяжёлый удар» и поля дальнего боя необязательны: их значения по умолчанию (`heavy_damage = 2`, `heavy_ink_cost = 25`, `ranged = false`, `ink_cost = 6`) сохраняют поведение клинка и кисти 0.5.2.

`Player` при старте берёт все карточки из `WDB`, сортирует по `order` и применяет текущую к удару. Новое оружие = новый `.tres` в `content/weapons` и ключ имени в локализации; код игрока не меняется.

Каталог `WDB` читает папку `content/weapons` в редакторе и секцию `weapons` манифеста в сборке.

---

## 7. `SaveData` — сохранение

```
schema_version: int
content_version: String
slots: Array[Slot]
autosave: Slot
world: WorldState
```

`Slot`:

```
slot_id: int
level_id: StringName
checkpoint_id: StringName
playtime: float
timestamp: int
world_state: WorldState
```

`WorldState`:

```
flags: Dictionary[StringName, bool]
defeated_bosses: Array[StringName]
collected: Array[StringName]
opened_doors: Array[StringName]
abilities: Array[StringName]
```

Правила:

- Атомарная запись: `slot_1.json.tmp` → rename; предыдущая версия остаётся как `.bak`.
- Неизвестные ключи при загрузке **не удаляются** — forward-compatibility.
- `content_version` фиксирует, что чекпоинт не переехал; расхождение — предупреждение, не краш.
- Миграции — цепочка функций `1→2`, `2→3`; версия повышается только вместе с миграцией.

Текущая схема v7 использует автосейв, три ручных слота, словарь `rooms` для посещённых комнат и поля прогрессии `PGS`. Чернила хранятся в `ink`; `soul` читается только при миграции старых слотов. Точные поля и правила описаны в [схеме сохранений](saves.md).

---

## 8. Валидация

```powershell
Godot --headless --path godot --script res://tools/build_manifest.gd
Godot --headless --path godot --script res://tools/validate_content.gd
```

Валидатор проверяет индекс и сцены, повторные ID, ссылки на карточки и диалоги, координаты в `bounds` и ключи обеих локалей. Он сравнивает ожидаемый манифест с сохранённым и возвращает `1` при ошибке. Генератор обновляет секции `levels`, `entities`, `weapons` и `props`.

---

## 9. Реализация в каркасе

| Файл | Что делает |
|---|---|
| `scripts/content/entity_def.gd` | `EntityDef` — карточка |
| `scripts/content/entity_stats.gd` | `EntityStats` — числа |
| `scripts/content/ai_profile.gd` | `AIProfile` — тип поведения |
| `scripts/content/loot_entry.gd` | `LootEntry` — добыча |
| `scripts/content/content_aliases.gd` | `ContentAliases` — переименования ID |
| `scripts/content/entity_database.gd` | автозагрузка `DB` |
| `content/entities/enemy_grunt.tres` | ползун: идёт к игроку, бьёт касанием |
| `content/entities/enemy_sentry.tres` | часовой: висит, стреляет болтами |
| `content/entities/enemy_blot.tres` | клякса: прыгает, делится при смерти |
| `content/entities/enemy_blot_small.tres` | малая клякса: то же тело, 1 HP, не делится |
| `content/entities/boss_keeper.tres` | Хранитель: карточка босса, 40 HP, категория `BOSS` |
| `scripts/actors/sentry.gd` | поведение часового |
| `scripts/actors/blot.gd` | поведение кляксы и сигнал `split` |
| `scripts/actors/keeper.gd` | босс: фазы, печать, волны, дождь, призыв |
| `scripts/actors/ink_wave.gd` | волна чернил по полу |
| `scripts/actors/ink_drop.gd` | капля с потолка и сигнал `landed` |
| `scripts/actors/ink_bolt.gd` | снаряд часового |
| `scripts/ui/cutscene.gd` | катсцена-слайдшоу из JSON |
| `scripts/ui/dialogue.gd` | нижняя панель диалога из JSON |
| `content/cutscenes/intro.json` | вступление, 4 слайда |
| `content/cutscenes/finale.json` | финал после босса, 3 слайда |
| `content/dialogue/archivist.json` | разговор с Переписчиком, 5 реплик |
| `content/weapons/blade.tres` | чернильный клинок |
| `content/weapons/brush.tres` | тяжёлая кисть |
| `content/aliases.tres` | таблица переименований (пока пустая) |
| `content/manifest.json` | генерируется, лежит в git |
| `tools/build_manifest.gd` | генератор манифеста |
| `scripts/content/weapon_def.gd` | `WeaponDef` — карточка оружия |
| `scripts/content/weapon_database.gd` | автозагрузка `WDB` |
| `scripts/systems/progression.gd` | автозагрузка `PGS`: способности, осколки, сосуды, пометки, имена |
| `scripts/world/level.gd` | сцена уровня: тайлы, враги, чекпоинты |
| `scripts/world/checkpoint.gd` | чекпоинт-метка |
| `scripts/world/ink_tileset.gd` | `TileSet` из атласа, коллизии тайлов |
| `tools/build_tileset.gd` | генератор `assets/tiles/ink_tiles.png` |

`DB` в редакторе и при обычном запуске читает папку `content/entities`, а в экспортированной сборке — `manifest.json`. Пути разные, API один.

### Клякса и деление

Клякса при смерти шлёт `split(pos, def_id)` **до** `died`, чтобы уровень успел создать детей раньше, чем проверит «зал очищен». Уровень создаёт двух малых клякс с `overrides: { "generation": 1 }`; поле `generation` объявлено в `overridable` карточки. Малая клякса не делится, потому что `generation > 0`.

Уровень считает детей обычными врагами: они в группе `enemies`, попадают в `enemy_count()` и переживают только текущую загрузку. Их ID вида `split_<n>` в сохранение не входят — при перезагрузке родитель уже мёртв и дети не нужны.

### Босс и печать

Босс — такая же карточка `EntityDef` с категорией `BOSS`, но с своим поведением в `scripts/actors/keeper.gd`. Уровень узнаёт его по типу `Keeper`, запоминает в `boss` и соединяет сигнал `summon` с созданием обычных врагов. Никакого отдельного загрузчика для боссов нет.

`keeper.hit()` принимает урон только при `seal_open`. Печать открывает сам босс: капля от удара сверху шлёт `landed`, и в этот момент начинается окно 1,3 с. Тяжёлая кисть (урон 3) получает +1 по открытой печати, поэтому снимает 4 HP за удар, клинок — 1.

Призыв идёт сигналом `summon(pos, def_id, count)`: уровень создаёт клякс с ID `summon_<n>`. Они не попадают в сохранение и удаляются, когда босс умирает. Остальные расстановки уровня при этом не трогаются.

`AIProfile.Kind.BOSS` пока только помечает карточку: поведение живёт в сцене, а не в общем профиле. Когда боссов станет несколько, общие поля (фазы, арена) можно будет вынести в `params`.

### Финал и временные враги

Когда в сюжетном уровне с финалом не остаётся врагов, `game_flow` пишет автосейв с `cleared: true`, играет `content/cutscenes/finale.json` и после последнего слайда открывает окно «Уровень пройден». Побочные комнаты могут отключать этот сценарий в своих данных.

`Level.is_temporary_id()` отсекает ID `split_*`, `summon_*` и `spawn_*`. Такие враги живут только в текущей загрузке: они не попадают в `killed` и не вызывают лишнюю запись автосейва. Постоянные расстановки приходят из JSON и помнятся по своим `e1`…`e30`.

### Тайлы

Сетка — 32×32. Геометрия уровня задаётся прямоугольниками в пикселях, кратными 32, и при загрузке растеризуется в `TileMapLayer`: коллизия и картинка берутся из одного тайлсета. Верхний ряд платформы — тайл с рваной кромкой, низ — заливка, односторонние платформы — отдельный тайл с односторонней коллизией.

Тайлсет рисуется процедурно, поэтому его можно перерисовать одной командой:

```
Godot --headless --path godot --script res://tools/build_tileset.gd
```

Прямоугольники — временный формат авторинга. Будущий редактор будет писать клетки напрямую, схема от этого не меняется.

### Как добавить врага

1. Собрать сцену из готовых компонентов (пока шаблон один — `scenes/actors/grunt.tscn`).
2. Создать карточку в `content/entities/`: `id`, `scene`, `stats`, `ai_profile`.
3. Поставить врага на уровень в `placements` по `def_id`.
4. Пересобрать манифест:

```
Godot --headless --path godot --script res://tools/build_manifest.gd
```

5. Прогнать smoke-тест.

Код игры при этом не правится. Новое поведение — это новая сцена/компонент, а не правка загрузчика.

### Переопределения

Уровень может переопределить только поля из `overridable` карточки: сейчас `max_hp`, `damage`, `speed`. Неизвестное поле не применяется и пишет предупреждение — уровень не может молча сломать баланс.

### Чего ещё нет

- Игровой редактор сохраняет пользовательские черновики отдельно от встроенного индекса. Движущиеся платформы и другие динамические пропы запланированы отдельно.

---

## 10. Открытые вопросы

1. **`Placement.overrides`** — свободный `Dictionary` с вайтлистом или типизированный `PlacementOverrides` с явными полями?
   Свободный гибче, типизированный безопаснее. Предложение: `Dictionary` + вайтлист в карточке.
2. **`content_version`** — выбирать ли отдельную версию игровых данных при развитии механизма миграции сохранений. Хеши отдельных файлов уже есть в манифесте.
