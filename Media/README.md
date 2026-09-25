# OnyxiaGold Media Pack

Runtime UI art for Warmane Onyxia / WoW 3.3.5a.

Files in this repo are intentionally compact:

- `Media/OnyxiaGoldUI_256x128.tga` — runtime texture atlas
- `Media/AtlasManifest.lua` — UV coordinates and dimensions
- this README

The editable/source pack is kept separately so the live addon does not carry duplicated textures.

## Design language

- dark, quiet surfaces
- restrained gold trim
- gold = primary action / money / selected
- blue = scan / information / secondary action
- green = profit / success / actionable
- red = blocked / loss / error
- text is never baked into artwork; all labels remain normal WoW FontStrings

The main action queue should always dominate visually. Ornament is secondary.

## Runtime atlas

Texture path:

```lua
Interface\\AddOns\\OnyxiaGold\\Media\\OnyxiaGoldUI_256x128.tga
```

Load `Media/AtlasManifest.lua` before the skin helper that consumes it.

Each region contains normalized `left`, `right`, `top`, `bottom` values for `Texture:SetTexCoord`.

Example:

```lua
local atlas = OnyxiaGold.MediaAtlas
local region = atlas.regions.button_primary_normal
texture:SetTexture(atlas.texture)
texture:SetTexCoord(region.left, region.right, region.top, region.bottom)
```

## Compact-frame mirroring

To keep the runtime atlas tiny, symmetric frame pieces are not all duplicated.

- bottom-right corner can be produced by mirroring `corner_tl` horizontally and vertically
- bottom edge can be produced by vertically mirroring `edge_top`
- right edge can be produced by horizontally mirroring `edge_left`

The manifest also includes explicit top-right and bottom-left corners.

Implement those transformations in `Skin.lua`; do not duplicate artwork unless testing shows the old client mishandles mirrored UV coordinates.

## Integration rules

1. Add `Media\\AtlasManifest.lua` to `OnyxiaGold.toc` before `Skin.lua` / `UI.lua`.
2. Create a dedicated `Skin.lua`; do not scatter UV coordinates through `UI.lua`.
3. Existing economic behaviour must not change because of the skin.
4. Primary gold buttons should be reserved for the most important action in a context, such as Buy, Post, Next Action or Scan when scanning is the main task.
5. Secondary controls use the blue-dark states.
6. Use glows and status icons sparingly.
7. Keep default WoW item icons for actual items. Do not replace useful semantic icons with decorative art.
8. The skin must degrade safely: if a texture fails, the control must remain usable and labelled.

## Button states

Atlas regions:

- `button_primary_normal`
- `button_primary_hover`
- `button_primary_pressed`
- `button_primary_disabled`
- `button_secondary_normal`
- `button_secondary_hover`
- `button_secondary_pressed`
- `button_secondary_disabled`

The texture contains no text, so existing labels remain dynamic.

## Other regions

- `background_dark_tile`
- `header_gold`
- `divider_gold`
- `status_success`
- `status_warning`
- `status_error`
- `status_info`
- `glow_gold`
- `glow_blue`
- `glow_green`
- `glow_red`
- `progress_track`
- `progress_fill_gold`
- `progress_fill_blue`
- `progress_fill_green`
- frame corners / edges

The intended result is a cleaner, more premium OnyxiaGold interface, not a heavily ornamented fantasy skin.

## Skin.lua

`Skin.lua` loads after this manifest and before `UI.lua`. `UI.lua` decides what a control is. `Skin.lua` decides how it looks. Keep texture coordinates in this manifest and in `Skin.lua`.

Colour in the live window:

- gold — primary Buy and Post buttons, and the next-action line
- blue — scan progress and market info
- green — profit, and a complete factory setup
- red — a loss, or a blocked post
- grey — disabled buttons and preview rows

Buy and Post use the gold primary button. The next-action line keeps its words, including the errand, and gets a quiet gold glow. It does not flash. Refresh, In bags, Take gold, Take mail, Quick Scan, Full Scan, Log, and Copy use the secondary button. Blizzard auction house, bag, mail, and tradeskill frames are left alone.

If the atlas or a region is missing, that control keeps the native button and its label.

To add a region: paint it into `OnyxiaGoldUI_256x128.tga` without moving the existing rectangles, add a `regions` entry here with `left`, `right`, `top`, `bottom`, `width`, and `height`, then use that name from `Skin.lua`.

Bottom-right is `corner_tl` flipped on both axes. The bottom edge is `edge_top` flipped vertically. The right edge is `edge_left` flipped horizontally. Corners stay at their pixel size. Edges stretch on one axis. `Skin.lua` insets each region by half a texel before the flip. Mirrored UVs and pixel bleed have not been checked in the WoW 3.3.5 client.
