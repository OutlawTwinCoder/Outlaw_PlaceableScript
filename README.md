# Outlaw Placeable

Placeable prop system for FiveM using **ox_inventory** and **ox_lib**. Players can preview a prop in front of them, rotate it, adjust distance, and confirm placement with a robust settle routine that prevents the prop from falling through the map.

## Features

- Modern ox_inventory integration through client exports (no RegisterUsableItem).
- Camera-based preview with ghost entity, rotation (Q/E) and optional distance scrolling.
- Validation for distance, slope and invalid surfaces.
- Physics settle routine to avoid props falling through the world.
- Config-driven item definitions and behaviour overrides.
- Example item definitions for ox_inventory.
- Server-side logging export and hooks ready for persistence.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_inventory](https://github.com/overextended/ox_inventory)

Ensure both dependencies are started before this resource.

## Installation

1. Clone or download the resource into your server's `resources` directory and rename the folder to `outlaw_placeable` if needed.
2. Add the resource to your `server.cfg` after `ox_lib` and `ox_inventory`:

   ```cfg
   ensure ox_lib
   ensure ox_inventory
   ensure outlaw_placeable
   ```

3. Configure your placeable items in `shared/config.lua` under `Config.Placeables`. Each entry requires a model hash (backticked for automatic joaat) and optional overrides such as custom rotation step, distance limits, or localisation strings.
4. Add matching items in `ox_inventory/data/items.lua`. The repository includes `data/example_items.lua` with two sample entries. Copy the structure into your inventory config, ensuring each item declares the export:

   ```lua
   placeable_crate = {
       label = 'Utility Crate',
       weight = 1000,
       stack = false,
       client = {
           export = 'outlaw_placeable.placeable_item'
       }
   }
   ```

   Optionally add a custom `buttons` table to display a *Place* button in the inventory UI.

## Usage

- Use the configured item in ox_inventory to start the preview.
- Rotate with **Q/E**, confirm with **Left Mouse Button**, cancel with **Right Mouse Button**.
- Scroll the mouse wheel to adjust distance when enabled in the config.
- On confirmation, the script will consume the item via `exports.ox_inventory:useItem` and spawn the prop with a physics settle routine.

Cancelling the preview keeps the item in the player's inventory. If the client disconnects or the resource stops, any preview entity is cleaned up automatically.

## Configuration

Key options in `shared/config.lua`:

- `Config.Distance`: Default distance limits and whether scrolling is enabled.
- `Config.RotationStep`: Global rotation step in degrees.
- `Config.MinPedDistance`: Minimum distance between player and prop.
- `Config.MinSurfaceNormalZ`: Minimum surface normal Z to consider a surface valid.
- `Config.Settle`: Parameters for the freeze and nudge routine preventing props from falling through the world.
- `Config.Callbacks`: Optional hooks (`OnPreviewStart`, `OnPreviewEnd`, `OnPlaced`, `OnPickup`) that can be assigned to custom functions.
- `Config.PersistenceMode`: Stub for future persistence modes (volatile by default).

Each placeable item can override distance limits, rotation step, forward mode (camera vs. ped), minimum distance and allowed surfaces.

## Server Hooks

`server/placeable.lua` exposes a basic event and export:

- `outlaw_placeable:placed`: Fired when a player confirms placement. Payload includes item name, coords, heading and model.
- `outlaw_placeable:previewCancelled`: Fired when a player cancels the preview.
- `exports.getPlacements()`: Returns a table with all placements recorded during the current session (volatile).

Use these hooks to implement persistence (KVP or database) or logging integrations.

## Custom Props

Place any custom models inside the `stream/` directory. Ensure each prop includes proper collision meshes; the physics settle routine relies on valid collision to keep the object above the map.

## Troubleshooting

- If the item is consumed instantly, verify that the item definition calls the `outlaw_placeable.placeable_item` export and does **not** use `RegisterUsableItem`.
- For jittery previews, double-check that no other scripts freeze or teleport the player during preview.
- If props clip through the ground, ensure the model has collision data and adjust the settle `epsilon` or `lockMs` in the config.

## Credits

Created by Outlaw Scripts. Inspired by the need for reliable prop placement with ox_inventory.
