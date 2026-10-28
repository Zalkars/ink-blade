# Схема контента — черновик на утверждение

**Статус:** черновик, требует подтверждения полей
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
| `camera_limits` | `Rect2` | Границы камеры |
| `music`, `ambient` | `String` | Аудио |
| `next_level` | `StringName` | Следующий уровень |
| `version` | `int` | Версия схемы уровня |

### `Placement`

| Поле | Тип | Назначение |
|---|---|---|
| `def_id` | `StringName` | Ссылка на карточку по ID |
| `position` | `Vector2` | Где стоит |
| `rotation`, `flip` | `float`, `bool` | Ориентация |
| `overrides` | `Dictionary` | Переопределения полей конкретного экземпляра |

`def_id` строкой, а не прямой ссылкой на ресурс: уровень остаётся валидируемым, переименование файла не ломает данные, отсутствующая карточка ловится валидатором.

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

- **в редакторе** — сканирование `res://content/**` через `EditorFileSystem`;
- **в билде** — сгенерированный `content/manifest.json` (`id → path → type → hash`).

Сканировать `res://` через `DirAccess` в экспортированном PCK нельзя — поведение отличается от редактора.

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

## 9. Открытые вопросы

1. **`Placement.overrides`** — свободный `Dictionary` с вайтлистом или типизированный `PlacementOverrides` с явными полями?
   Свободный гибче, типизированный безопаснее. Предложение: `Dictionary` + вайтлист в карточке.
2. **Уровень = `PackedScene` комнаты + `LevelData`** — подтверждено, но нужно решить, где живут чекпоинты: в сцене или в `LevelData`.
   Предложение: в `LevelData`, чтобы save не зависел от структуры сцены.
3. **Слоты** — сколько (3 или 5) и когда включаем остальные. Предложение: 3 слота, в срезе — 1.
4. **`content_version`** — хэш всех уровней или версия из `project.godot`. Предложение: хэш папки `content/levels`.
