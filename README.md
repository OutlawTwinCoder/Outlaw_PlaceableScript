# Outlaw Placeable

A complete placeable-item system for FiveM inspired by KuzQuality scripts. It supports camera-based preview, car trunk fitting, persistence, drop/throw modes and multiple inventory frameworks.

## Features

- Place any configured inventory item as a physical prop, or enable the fallback to allow every item to become placeable.
- Camera-driven preview with distance scroll, rotation snapping and green/red validation feedback.
- Optional drop/throw placement (toggle with the drop key) where the prop stays dynamic instead of freezing, or can be thrown using the player momentum.
- Automatic trunk handling with capacity per vehicle class and grid fitting to avoid overlapping.
- Anti-stacking checks on world placements to prevent exploits.
- Persistence layer (optional) to respawn important props after a server restart.
- Integrations for `ox_inventory`, `qs-inventory`, `qb-inventory` or a standalone fallback.
- Optional `ox_target` entries for collecting, inspecting and staff removal.
- Localised notifications (FR/EN provided).

## Installation

1. Place the resource in your `resources/` folder and ensure it is started after your inventory system.
2. Import [`sql/outlaw_placeable.sql`](sql/outlaw_placeable.sql) into your database if you enable persistence.
3. Configure `config.lua` for distances, trunk settings, persistence and item definitions.
4. Add the resource to your server configuration: `ensure Outlaw_Placeable`.

## Configuration

`config.lua` exposes:

- `Distances` – minimum/maximum placement range and safety distances.
- `Preview` – mode (`camera` or `ped`), rotation steps and alpha blending values.
- `Controls` – keybinds for confirm, cancel, rotation, drop toggle and interaction.
- `MakeEverythingPlaceable` – enable to make all inventory items spawn the fallback prop.
- `AntiStacking` – enforce minimum spacing between world placements.
- `FreezePlacedObjects` – freeze props after settling.
- `Persistence` – enable global persistence or per-item (`persistent = true`).
- `InventoryProvider` – choose between `ox`, `qs`, `qb` or `standalone`.
- `Trunk` – toggle trunk logic, capacity per class and candidate bones.
- `Items` – define item-specific models, permissions and metadata.
- `Commands` & `Security` – command names and ACE required for cleanup.

## Commands

- `/place <item>` – start placement preview for an inventory item.
- `/place_cancel` – cancel the current preview.
- `/place_remove_near` – request removal of the closest owned placement.
- `/place_cleanup_all` – staff-only command to clean every placement (requires ACE defined in `Config.Security.staffAce`).

Default keybinds are registered via `RegisterKeyMapping`: `G` to start `/place`, `BACKSPACE` to cancel and `H` to remove a nearby prop. You can remap them in FiveM settings.

## Events & Exports

The resource exposes client/server events for starting placement and removing props. It also registers ox_target options when the dependency is running. Developers can hook into `outlaw_placeables:placementCreated` and `outlaw_placeables:placementRemoved` events to extend behaviour.

## Inventory integrations

Set `Config.InventoryProvider` to match your framework. The resource automatically registers usable items via the provider and handles add/remove logic. When using `standalone`, it will not touch the player inventory – you must manage item consumption manually.

## Persistence

When persistence is enabled globally or for a specific item, the server inserts placement records into the `outlaw_placeables` table and respawns them on resource start. Removing a persisted placement cleans up its database row.

## Troubleshooting

- Ensure the prop models you configure are available. Stream custom YDR/YTYP assets alongside the resource if necessary.
- If `ox_target` is disabled, the script falls back to a 3D prompt using the collect key (`Config.Controls.collect`).
- Use the ACE permission configured in `Config.Security.staffAce` to allow staff to cleanup all objects.
