# Схема контента

**Статус:** реализовано в каркасе; редактор и валидатор — позже
**Связано:** `docs/tech-brief.md`

Задача схемы: новый враг, проп или уровень добавляется **данными**, без правки игрового кода.

---

## 1. Общие правила

1. **Контент — `.tres` (Resource).** Текст, читается инспектором Godot, мержится в git, не требует парсера.
2. **Сохранения — JSON** в `user://saves/`. Легко отлаживать, версионировать, мигрировать.
3. **JSON для контента** — только если появится UGC/моды. Один источник правды на режим.
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

---

## 4. `PropDef` — статика, динамика, триггеры, пикапы

Те же поля плюс:

| Поле | Тип | Назначение |
|---|---|---|
| `kind` | `enum` | `static`, `dynamic`, `trigger`, `pickup` |
| `collision_layer` | `int` | С какими слоями сталкивается |
| `sort_layer` | `int` | Порядок отрисовки |
| `light` | `LightDef` | Источник света, если есть |
| `state_script` | `Script` | Поведение для динамики (дверь, платформа) |

Статика и динамика — один тип с разным `kind`, чтобы в палитре была одна категория «Объекты».

---

## 5. `LevelData` — уровень

| Поле | Тип | Назначение |
|---|---|---|
| `id` | `StringName` | `level.ch01_01` |
| `display_name_key` | `String` | Название для меню |
| `scene` | `PackedScene` | Комната/чанки, `TileMapLayer` |
| `placements` | `Array[Placement]` | Кто и где стоит |
| `checkpoints` | `Array[Checkpoint]` | Точки возрождения |
| `triggers` | `Array[Trigger]` | Сюжетные сцены на оси X |
| `camera_limits` | `Rect2` | Границы камеры |
| `music`, `ambient` | `String` | Аудио |
| `next_level` | `StringName` | Следующий уровень |
| `version` | `int` | Версия схемы уровня |

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
| `slides[].art` | Имя процедурной картинки: `city`, `ink`, `blade`, `hall` |

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
ink: Color
swing_radius / swing_width: float
```

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

В срезе реализована упрощённая версия этой схемы: один автосейв, плоский JSON с полями `level`, `checkpoint`, `killed`, `triggers`, `weapons`, `weapon`, `hp`, `enemies_left`, `cleared`. Точные поля и правила описаны в `docs/saves.md`. Слоты и `WorldState` из схемы выше появятся вместе с меню профиля.

---

## 8. Валидация

`ContentValidator` — один скрипт, работает в редакторе (`@tool`) и в CI headless:

- дубликаты ID;
- битые ссылки `def_id` в уровнях;
- пустой `scene` или `icon`;
- уровень без входа/выхода;
- спавн внутри стены;
- отсутствующие ключи локализации;
- `overrides` с полями вне вайтлиста;
- алиасы, указывающие на несуществующий ID.

Ошибка валидации = красная сборка.

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
| `scripts/actors/sentry.gd` | поведение часового |
| `scripts/actors/blot.gd` | поведение кляксы и сигнал `split` |
| `scripts/actors/ink_bolt.gd` | снаряд часового |
| `scripts/ui/cutscene.gd` | катсцена-слайдшоу из JSON |
| `scripts/ui/dialogue.gd` | нижняя панель диалога из JSON |
| `content/cutscenes/intro.json` | вступление, 4 слайда |
| `content/dialogue/archivist.json` | разговор с Переписчиком, 5 реплик |
| `content/weapons/blade.tres` | чернильный клинок |
| `content/weapons/brush.tres` | тяжёлая кисть |
| `content/aliases.tres` | таблица переименований (пока пустая) |
| `content/manifest.json` | генерируется, лежит в git |
| `tools/build_manifest.gd` | генератор манифеста |
| `scripts/content/weapon_def.gd` | `WeaponDef` — карточка оружия |
| `scripts/content/weapon_database.gd` | автозагрузка `WDB` |
| `scripts/world/level.gd` | сцена уровня: тайлы, враги, чекпоинты |
| `scripts/world/checkpoint.gd` | чекпоинт-метка |
| `scripts/world/ink_tileset.gd` | `TileSet` из атласа, коллизии тайлов |
| `tools/build_tileset.gd` | генератор `assets/tiles/ink_tiles.png` |

`DB` в редакторе и при обычном запуске читает папку `content/entities`, а в экспортированной сборке — `manifest.json`. Пути разные, API один.

### Клякса и деление

Клякса при смерти шлёт `split(pos, def_id)` **до** `died`, чтобы уровень успел создать детей раньше, чем проверит «зал очищен». Уровень создаёт двух малых клякс с `overrides: { "generation": 1 }`; поле `generation` объявлено в `overridable` карточки. Малая клякса не делится, потому что `generation > 0`.

Уровень считает детей обычными врагами: они в группе `enemies`, попадают в `enemy_count()` и переживают только текущую загрузку. Их ID вида `split_<n>` в сохранение не входят — при перезагрузке родитель уже мёртв и дети не нужны.

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

- `PropDef` и `LevelData` как ресурсы: уровень пока JSON + сцена.
- Валидатор и редактор.
- Чтение манифеста на Android-устройстве не проверено.

---

## 10. Открытые вопросы

1. **`Placement.overrides`** — свободный `Dictionary` с вайтлистом или типизированный `PlacementOverrides` с явными полями?
   Свободный гибче, типизированный безопаснее. Предложение: `Dictionary` + вайтлист в карточке.
2. **Уровень = `PackedScene` комнаты + `LevelData`** — подтверждено, но нужно решить, где живут чекпоинты: в сцене или в `LevelData`.
   Предложение: в `LevelData`, чтобы save не зависел от структуры сцены.
3. **Слоты** — сколько (3 или 5) и когда включаем остальные. Предложение: 3 слота, в срезе — 1.
4. **`content_version`** — хэш всех уровней или версия из `project.godot`. Предложение: хэш папки `content/levels`.
