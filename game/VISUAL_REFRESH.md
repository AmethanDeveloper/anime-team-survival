# Visual refresh — 2026-11-09

## Added / reused free assets
- **Brown Mud Leaves 01**, Rob Tuytel / Poly Haven. CC0 1.0.
  Source: https://polyhaven.com/a/brown_mud_leaves_01
  License: https://polyhaven.com/license
  Download: https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/brown_mud_leaves_01/brown_mud_leaves_01_diff_1k.jpg
  Local: assets/visual_refresh/soil.jpg (1K diffuse, mipmaps enabled).
  Used in world-space terrain and worn-path shaders; grass transition is procedural.
- **Medieval Village MegaKit (FREE)**, Quaternius. CC0 1.0.
  Source: https://quaternius.com/packs/medievalvillagemegakit.html
  Existing local license: assets/quaternius/License_Village.txt.
  Reused model: assets/quaternius/mesh/Wall_Arch.res.
  Portal proportions adapted to existing locations; gold trim and animated shader added.
  Reused textures: T_RoundTiles_BaseColor.png and T_UnevenBrick_BaseColor.png.
- **Stylized Nature MegaKit**, Quaternius. CC0 1.0.
  Source: https://quaternius.com/packs/stylizednaturemegakit.html
  Existing local license: assets/quaternius/License_Nature.txt.
  Existing rock, pebble, grass and foliage assets retained, snow/frost reduced.
- Shader code, shrine/tower additions and HUD ornament drawing were created for this project.
  No paid asset, external font, or new character artwork was downloaded.
- Existing hero portraits, skill images and item icons remain project assets; this refresh does not
  change their provenance or grant a new license to them. Portraits are reframed, not repainted.
- ui-concept.png is the user's supplied visual reference, not a downloaded asset.

## Integration
- Existing scripts changed: scripts/world.gd, scripts/decor.gd, scripts/hud.gd; scripts/game.gd (two label-height adjustments only).
- New visual resources: assets/visual_refresh/{visual_props.gd,terrain.gdshader,path.gdshader,portal.gdshader,soil.jpg}.
- New review tool: tools/visual_refresh_check.gd.
- World.prop("Portal") now assembles the CC0 arch with the animated veil.
- World.prop("Crystal") and World.prop("Tower") add shrine/roof details to existing models.
- Existing navigation, collision shapes, spawn positions, portal routing, combat values and controls
  were not changed. Only two portal label heights were changed in game.gd; hero.gd, unit.gd and data files were not edited.
- HUD: cropped existing portrait with 3D fallback, red health / turquoise mana, gold corner frames,
  item rarity borders, and a live read-only character sheet opened via "Характеристики".
  Item actions still use existing inventory controls / keys 1–6.
- Existing files were backed up before editing:
  D:/Anime Team Survival/backup_visual_20261109_103810/{world.gd,hud.gd,decor.gd,game.gd}.

## Verification
Godot 4.7.2, Forward+, NVIDIA RTX 4060:
- Editor import and script compilation completed without script errors after fixes.
- Normal game startup and base screenshot completed.
- tools/visual_refresh_check.gd: character sheet open/close, filled inventory, shop and portal render passed.
- Existing --uitest --seed=42 completed with UITEST DONE:
  base/forest/center teleports; plateau height 1.40; portal destination area 1;
  courier delivery; tower damage 130 -> 7; potion charges; stat tome; assembled hero set;
  antimagic shield; team fight; maze movement; pause menu.
- Original and updated builds both report 12 ObjectDB instances and 2 resources still in use at exit.
  These pre-existing shutdown diagnostics were not addressed in this visual change.
- Screenshots in D:/Anime Team Survival:
  before-visual.png, after-visual.png, character-visual.png, portal-visual.png, shop-visual.png.
- No claim of exhaustive gameplay coverage or performance benchmarking.

## Reproduce
From the project parent folder:
```powershell
& '.\Godot_v4.7.2-stable_win64_console.exe' --path '.\game' --headless --editor --quit
& '.\Godot_v4.7.2-stable_win64_console.exe' --path '.\game' --headless -- --uitest --seed=42
& '.\Godot_v4.7.2-stable_win64_console.exe' --path '.\game' --script res://tools/visual_refresh_check.gd
```

## Approved material update - 2026-11-09

User approved soil and walls; the previous UI candidates were rejected.

### Sources and licenses
- Dirt Floor, Poly Haven: https://polyhaven.com/a/dirt_floor
- Medieval Blocks 03, Poly Haven: https://polyhaven.com/a/medieval_blocks_03
- Both texture sets: CC0 1.0, https://polyhaven.com/license
- Installed 2K JPG color, OpenGL normal and roughness maps for each set in
  assets/approved_materials/. Exact download URLs and verified MD5 checksums:
  assets/approved_materials/sources.json.
- Dirt Floor replaces the earlier Brown Mud Leaves texture in the terrain and
  worn-path shaders; the older file remains available but is no longer used there.
- Medieval Blocks 03 is applied to LowWall models and arena wall meshes with
  world-space triplanar mapping. Arena visibility and purple band are retained.
- Mipmaps enabled on all six textures. Normal maps marked as normal-map imports.

### Files and preservation
- Updated scripts/world.gd, scripts/arena.gd,
  assets/visual_refresh/terrain.gdshader and path.gdshader.
- Added assets/approved_materials/materials.gd and wall.gdshader.
- Pre-update backup: D:/Anime Team Survival/backup_approved_materials_20261109_194210/
- This material update does not change navigation, colliders, spawn positions,
  combat values, HUD code or game.gd.

### Verification
- Godot editor import completed; no script compilation errors.
- Graphical startup and arena battle render completed with exit code 0.
- Screenshots: D:/Anime Team Survival/approved-materials.png and approved-arena.png.
- The existing shutdown messages about 12 ObjectDB instances and 2 resources
  remain present, as recorded in the earlier baseline.
- Existing gameplay UITEST passed during the initial refresh; it has not been
  rerun for this material-only update.

### Pending assets (not installed)
- User approved Stylized Stone Portal by SlyCoopxr jpg, TurboSquid ID 2033290:
  https://www.turbosquid.com/3d-models/3d-stylized-stone-portal-2033290
  Offered free under TurboSquid Standard License, not CC0:
  https://www.turbosquid.com/licensing
  Added to the user's downloads after login, but the in-app browser blocks the
  archive download with ERR_BLOCKED_BY_CLIENT. Awaiting the downloaded archive.
- Gilded Fantasy UI and Kenney borders are not approved for the requested new UI.
- A new ImageGen frame concept based on the user's ui-concept.png was generated
  for review only. It is not a downloaded asset pack and is not referenced by the game.


## Approved portal and anime UI integration — 2026-11-09

This section supersedes the pending portal/UI status above. The user downloaded
Portal_All_Files.zip and approved the generated frame style, requesting 6 items
and 6 skills with one emphasized set ability.

### Completed
- Installed the approved TurboSquid Stylized Stone Portal at mob spawn gates.
  FBX geometry retained; Godot PBR materials rebuilt from included stone/skull maps.
  Added smooth animated violet veil and subtle ground rings.
  Sources, archive checksum and license: assets/approved_portal/README.md.
- Installed the approved anime UI style as separate panel/slot PNGs with alpha.
  The real HUD layout is retained and fitted to the 1600x900 logical viewport.
  Six item slots use a 3x2 grid; six skill controls occupy one group.
  The sixth, T, is larger, stays visible while locked and highlights on set equip.
- Portrait framing, character stats window, item/skill borders and panel backgrounds
  use the same art. Character sheet contains 6 skills and 6 item slots.
- Sources and exact image-generation prompts: assets/anime_ui/README.md and
  assets/anime_ui/GENERATION_PROMPTS.md. These are generated assets, not downloaded UI.
- This phase modifies scripts/hud.gd and scripts/world.gd only among existing gameplay
  source files. World changes select a different SpawnGate visual and ground material.
  Existing control handlers, unlock checks, spawns, collisions and combat logic are preserved.
- Pre-change backups: D:/Anime Team Survival/backup_anime_portal_20261109/
  (hud.gd, world.gd, VISUAL_REFRESH.md).

### Verified
- Godot resource import succeeded. Compilation and graphical startup succeeded.
- tools/anime_visual_check.gd: ANIME_VISUAL_QA PASS, exit 0.
  Checks six item controls and six skill controls, viewport bounds for every slot
  and console panel, no panel overlap, locked set rejects targeting, equipped set
  highlights, character sheet opens/closes, shop renders, approved portal instantiates.
- Existing --uitest --seed=42: UITEST DONE, exit 0. Teleports, courier, tower damage,
  potions, tome, set assembly, antimagic, duel, maze movement and pause menu completed.
- Baseline shutdown diagnostics remain: 12 ObjectDB instances and 2 resources in use.
  No new script or shader errors were observed in the final graphical test.
- Final screenshots in D:/Anime Team Survival/:
  anime-hud.png, anime-hud-locked.png, anime-character.png, anime-shop.png,
  anime-spawn-portal.png.
- Logs: anime-visual-test.log, anime-gameplay-test.log.

