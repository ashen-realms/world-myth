# Runtime package format 2

`world-myth build [project]` discovers saved source files, parses and validates
all documents, resolves references, normalizes data and writes a new SQLite
artifact. GUI Build requests Save All when buffers are dirty. GUI Validate
includes unsaved buffers. Neither validator writes source files.

Output is `dist/world.sqlite` and `dist/manifest.json`. The package is independent
of the editor and source directory. This is an internal format, with no claim of
Axiom or Aether compatibility. Runtime player state is never included.

## SQLite schema

`PRAGMA user_version = 2` (v1 was used before World Myth 0.2). Text identifiers are stable source IDs. Foreign keys
are checked during compilation. Tables:

| Table | Key / contents |
|---|---|
| world | World ID, name, source version, description, default region |
| regions | Region ID, name |
| terrain | Terrain ID, glyph, colors, passability, movement cost |
| maps | `(region_id,id)`, name, dimensions, default terrain |
| layers | `(region_id,map_id,kind)`, inherited width/height |
| cells | `(region_id,map_id,y,x)`, resolved terrain ID, collision override |
| entities | Entity ID, type, name, tags JSON, properties JSON |
| entity_positions | Entity ID, region/map ID and x/y |
| objects | `(region_id,map_id,id)`, entity ID and x/y |
| lore | Project-relative path, Markdown text |

The cells table is `WITHOUT ROWID`, ordered spatially by map/y/x. Object and
entity-position indexes support per-map coordinate lookup. Collision is SQL NULL
for inherited, 1 for blocked and 0 for explicitly passable. All positions use the
source convention: top-left origin and zero-based x/y. Consumers resolve effective
passability from override and terrain; World Myth implements no movement engine.

Properties are canonical JSON with sorted keys, preserving scalar types. Tags
retain their source order. Terrain symbols are resolved to IDs; a runtime loader
does not need YAML legends. No external files are needed to load the package.

The manifest contains `schema_version`, `compiler_version`, `world_id`,
`world_version`, `database` and a SHA-256 checksum of the complete SQLite file.

## Determinism and publication

Each build uses a fresh database, fixed schema creation order, stable ID/y/x
insertion order and one transaction. Artifacts contain no timestamps or absolute
paths. Repeated builds are byte-compared in tests. Byte identity is guaranteed
only within the same locked shard and system SQLite toolchain; SQLite is a system
library and can change representation between versions.

A nonblocking advisory file lock prevents competing World Myth builds. The
compiler stages both files in a sibling `.dist-stage-*` directory, checks SQLite
integrity and foreign keys, and verifies that the source snapshot is still current.
Only then is the previous `dist` moved to `.dist-backup` and the complete staged
directory moved to `dist`. Ordinary publication failures restore the backup.
The backup is removed after success; a subsequent build recovers a backup left by
an interrupted rename sequence. A process/machine crash can briefly leave `dist`
absent with the previous package in `.dist-backup`; directory-pair publication is
recoverable rather than a promise of power-loss atomicity. Do not consume a package
while it is being published. No WAL sidecars are required.

Generated artifacts, staging/backup directories and the build lock are ignored by
Git. Source validation failures leave the previous published package untouched.

## Runtime schema v2

World Myth 0.2 writes `PRAGMA user_version = 2` and manifest `schema_version: 2`,
including when compiling legacy v1 sources. This is an internal format change;
old readers must reject it rather than assume v1. Existing metadata, `cells`,
`layers`, entities and placement tables remain, with `cells` describing ground.
The additional tables are:

| Table | Content / key |
|---|---|
| `sprites` | ID, name, dimensions, anchor, default direction, canonical palette JSON |
| `animations` | `(sprite_id,id)`, loop flag |
| `sprite_frames` | `(sprite_id,animation_id,direction,ordinal)`, duration and ASCII row JSON |
| `surfaces` | `(region_id,map_id,id)`, surface kind |
| `surface_cells` | `(region_id,map_id,surface_id,y,x)`, elevation, shape, terrain ID, collision |
| `walls` | Map-local ID, surface, coordinates, edge, height, material |
| `entity_visuals` | Entity ID, optional sprite ID, default animation |
| `terrain_visuals` | Terrain ID, optional top and side sprite IDs |
| `placement_surfaces` | Object placement's supporting surface and facing |
| `position_surfaces` | Entity position's supporting surface and facing |

Only occupied surface cells are written. Dimensions come from `maps`; missing
cells in additional surfaces are empty. Ground is also present in `surface_cells`
with zero heights for v1. Foreign keys link assets and supporting surfaces. Source
validation additionally checks support at the actual x/y coordinate, animation
names, directions and frame/palette consistency. Sprite art is fully embedded;
the runtime package needs no world-source files. Insert order remains stable and
compilation includes no current animation time or player state.
