# Demo XML format (`10 vs 10`)

This document defines the minimal XML contract for demo data loading.

## Files

- `assets.xml`: master catalog of asset definitions.
- `units.xml`: unit logical contracts referencing assets by id.

## `assets.xml`

Root:

- `<assets version="1">`

Entry:

- `<asset id="" type="" display_name=""> ... </asset>`

Required attributes:

- `id`: unique string key used by unit references.
- `type`: one of `core`, `weapon`, `container`, `inventory`.
- `display_name`: human readable label for logs/debug UI.

Supported child blocks (by type):

- `core`:
  - `<stats mass="" durability="" />`
  - `<visual scene="" />`
- `weapon`:
  - `<weapon projectile_scene="" fire_rate="" projectile_speed="" range="" />`
- `container`:
  - `<capacity slots="" />`
- `inventory`:
  - `<inventory capacity="" item_kind="" />`

Validation rules:

- `id` must be unique in the file.
- `type` must be one of the 4 supported values.
- `weapon` assets must define `projectile_scene`, `fire_rate`, `projectile_speed`, `range`.
- Unknown child blocks should be treated as configuration errors.

## `units.xml`

Root:

- `<units version="1">`

Entry:

- `<unit id="" display_name=""> ... </unit>`

Required child blocks:

- `<runtime team="" hp="" move_speed="" aggro_range="" attack_range="" respawn_sec="" />`
- `<assets> ... <asset_ref ... /> ... </assets>`

`asset_ref` attributes:

- `id`: must match an existing `assets.xml` `asset.id`.
- `role`: semantic use in runtime, for example `platform`, `primary_weapon`, `ammo`.
- `required`: `true` or `false`; loader fails if required asset is missing.

Validation rules:

- `unit.id` must be unique.
- `team` must be non-empty string (demo currently uses `red` and `blue`).
- numeric runtime fields must be parseable and greater than zero (`hp` may be `1`).
- each unit must contain at least:
  - one required `platform` asset_ref;
  - one required `primary_weapon` asset_ref.
- all `asset_ref.id` values must resolve in `assets.xml`.

## Runtime expectations for first demo

- Unit remains a two-level entity:
  - logical unit definition from `units.xml`;
  - attached asset data from `assets.xml`.
- Runtime can still instantiate a single visual scene per unit for now.
- Complex ORBAT behavior is intentionally out of scope for this version.
