# Outlaw Placeable

Outlaw Placeable is a FiveM resource providing camera-driven placement, vehicle trunk fitting, and optional persistence for any inventory item. It ships with plug-and-play support for **ox_inventory**, **qs-inventory**, **qb-inventory**, **ox_target** and **ox_lib** while remaining functional without them.

## Features

- 🔭 Camera or ped based preview with semi-transparent ghost entity, rotation snap, distance scroll and drop/throw toggle.
- 🧠 Smart validation for distance, stacking, blocked surfaces and trunk capacity with automatic vehicle trunk grids.
- 🚗 Trunk placement auto fits objects inside vehicle storage volumes with per-class capacity handling.
- 💾 Optional SQL persistence with automatic respawn on restart and cleanup utilities.
- 🧰 Inventory provider abstraction to switch between ox, qs, qb or a standalone stub without touching gameplay code.
- 🎯 ox_target interactions (pickup, inspect, staff removal) and ox_lib notifications/menu support when available.
- 🧪 Testing command to stress the pipeline and monitor resmon usage.

## Installation

1. Copy the resource folder into your server `resources` directory and ensure its name stays `Outlaw_Placeable`.
2. Import the SQL schema if persistence is enabled:
   ```sql
   SOURCE resources/Outlaw_Placeable/sql/outlaw_placeable.sql;
   ```
3. (Optional) Start the optional dependencies before this resource when you need them:
   ```cfg
   ensure ox_lib
   ensure ox_inventory
   ensure ox_target
   ensure oxmysql
   ensure Outlaw_Placeable
   ```
4. Configure items in `config.lua`. Each entry under `Config.Placeables` defines the model and behaviour for a usable item.

## Configuration Overview (`config.lua`)

- `Config.Distance`, `Config.Preview` – control minimum/maximum placement distance, rotation steps, snap angle and scroll speed.
- `Config.MakeEverythingPlaceable` – enable to allow any item to spawn using a fallback model.
- `Config.AntiStacking` – set minimum separation to avoid props intersecting.
- `Config.Trunk` – enable trunk mode, define per-class capacities and cell padding.
- `Config.Persistence` – toggle SQL persistence and automatic cleanup window.
- `Config.InventoryProvider` – choose `'ox'`, `'qs'`, `'qb'` or `'standalone'`.
- `Config.Commands` – change command names (`/place`, `/place_cancel`, `/place_remove_near`, `/place_cleanup_all`).
- `Config.Testing` – tweak the stress test command name and spawn count.

## Inventory Integration

The inventory abstraction registers usable items automatically on resource start. Define items in your inventory system and ensure they trigger a “use” event:

- **ox_inventory**: standard item with `client = { export = 'Outlaw_Placeable.StartPlacement' }` or rely on the automatic usable registration.
- **qs-inventory / qb-inventory**: the resource registers `RegisterUseItem` / `CreateUseableItem` handlers internally.
- **Standalone**: a simple in-memory store is provided for testing; use `/use_<item>` commands to simulate consumption.

## Commands & Exports

| Command | Description |
|---------|-------------|
| `/place <item>` | Start placement for a configured item. |
| `/place_cancel` | Cancel the current preview. |
| `/place_remove_near` | Remove nearby props (owner or staff permission). |
| `/place_cleanup_all` | Staff command to remove all spawned props. |
| `/place_testbatch` | Spawn a batch of props to test resmon performance (staff/console). |

Exports:
```lua
exports['Outlaw_Placeable']:StartPlacement(itemName, metadata)
```

## Optional Integrations

- **ox_target**: automatically registers pickup/inspect/remove options for every placed prop.
- **ox_lib**: notifications and future UI menus use lib APIs when the resource is running.
- **oxmysql**: required for persistence. Disable `Config.Persistence.enabled` to skip database usage.

## Persistence

With persistence enabled, every eligible placement is stored in `outlaw_placeables`. Objects respawn on resource start, and the optional purge process removes entries older than `Config.Persistence.cleanupDays`.

## Testing & Performance

Use `/place_testbatch` to spawn a configurable number of props (default 50) around the player. Monitor client `resmon` to ensure idle time remains 0.00–0.02 ms. Run `/place_cleanup_all` afterwards to delete the spawned props.

## Troubleshooting

- Props refuse to place: verify the item is configured and the model hash matches the item definition.
- Trunk placement fails: ensure the target vehicle class has a non-zero capacity and the trunk is unobstructed.
- SQL errors: confirm `oxmysql` is running and the schema has been imported.

## Credits

Created by Outlaw Scripts. Contributions and pull requests are welcome.
